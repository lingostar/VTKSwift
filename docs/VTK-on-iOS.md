# VTK on iOS - Volume Rendering 구현 기획서

## 1. 개요

VTK(Visualization Toolkit) 9.4를 사용하여 iOS(iPhone/iPad)에서 DICOM 의료영상의 3D Volume Rendering을 구현한 과정을 정리한 문서이다. macOS에서는 정상 동작하는 Volume Rendering이 iOS에서는 OpenGL ES 3.0의 제약으로 인해 다수의 호환성 문제가 발생하였으며, 이를 하나씩 해결하여 최종적으로 iPhone에서 Volume Rendering 표시에 성공하였다.

**핵심 환경:**
- VTK 9.4 (소스 빌드)
- iOS 18+ / OpenGL ES 3.0 (Metal 백엔드)
- EAGLContext + GLKView 렌더링 방식
- Apple A-series GPU (테스트: A18)

---

## 2. VTK iOS 렌더링 아키텍처

### 2.1 렌더링 파이프라인

```
GLKView (CAEAGLLayer 기반)
   │
   ├── [glkView display] 호출
   │      │
   │      ├── 1) GLKView가 자체 FBO를 바인딩
   │      ├── 2) delegate의 glkView:drawInRect: 호출
   │      │      │
   │      │      └── performVTKRender 호출
   │      │             │
   │      │             ├── VTK State Tracker 동기화
   │      │             │   (GLKView FBO → vtkglBindFramebuffer)
   │      │             │
   │      │             └── renderWindow->Render()
   │      │                    │
   │      │                    ├── Start(): 내부 FBO 생성/바인딩
   │      │                    │   └── RenderFramebuffer (MSAA)
   │      │                    │
   │      │                    ├── Scene 렌더링 (Volume Ray Casting)
   │      │                    │
   │      │                    ├── End(): 렌더링 완료
   │      │                    │
   │      │                    └── Frame(): FBO Resolve + Blit
   │      │                           ├── RenderFBO → DisplayFBO (resolve)
   │      │                           └── DisplayFBO → GLKView FBO (BlitToCurrent)
   │      │
   │      └── 3) GLKView가 CAEAGLLayer에 presentRenderbuffer
   │
   └── 화면에 표시
```

### 2.2 VTK FBO 구조

```
RenderFramebuffer (MSAA 렌더링 타겟)
       │ blit (resolve)
       ▼
DisplayFramebuffer (해상도 해결된 출력, 2개 컬러 어태치먼트 - 스테레오용)
       │ blit (BlitToCurrent 모드)
       ▼
Current FBO (= GLKView의 FBO)
       │ presentRenderbuffer
       ▼
화면 (CAEAGLLayer)
```

### 2.3 핵심 클래스

| 클래스 | 역할 |
|--------|------|
| `vtkIOSRenderWindow` | iOS용 렌더 윈도우. 생성자에서 `SetFrameBlitModeToBlitToCurrent()` 설정 |
| `vtkOpenGLRenderWindow` | FBO 생성/관리, Frame() blit 로직 |
| `vtkOpenGLState` | GL 상태 캐시 (중복 호출 방지). 외부 GL 변경 시 동기화 필요 |
| `vtkOpenGLShaderCache` | GLSL 셰이더 전처리 (ES 3.0 호환성 변환) |
| `vtkOpenGLGPUVolumeRayCastMapper` | GPU 기반 볼륨 레이캐스팅 |
| `vtkVolumeShaderComposer` | 볼륨 렌더링 GLSL 셰이더 동적 생성 |
| `vtkTextureObject` | GL 텍스처 생성/관리 |
| `vtkOpenGLState::InitializeTextureInternalFormats` | 데이터 타입 → GL 텍스처 포맷 매핑 |

---

## 3. 문제 해결 과정 (시간순)

### 3.1 Phase 1: 기본 렌더링 파이프라인 (검은 화면)

#### 시도 1: SetUseOffScreenBuffers(true)

**증상:** 검은 화면 (FBO 픽셀 전부 0)

**원인:** `SetUseOffScreenBuffers(true)`를 설정하면, VTK의 `Render()` 내부에서 `SwapBuffers = 0`으로 임시 변경한다. 이렇게 되면 `Frame()` 함수의 본체가 `if (this->SwapBuffers)` 조건 안에 있으므로, **RenderFBO → DisplayFBO resolve가 완전히 생략**된다.

```cpp
// vtkOpenGLRenderWindow::Frame()
if (this->SwapBuffers)   // SwapBuffers=0이면 여기 전체 스킵!
{
    // resolve render → display
    // blit display → current
}
```

**해결:** `SetUseOffScreenBuffers(true)` 제거. VTK iOS에서는 불필요.

---

#### 시도 2: 커스텀 Blit 셰이더 구현

**접근:** VTK의 BlitToCurrent가 동작하지 않는다고 판단하고, DisplayFBO의 텍스처를 직접 읽어 GLKView에 그리는 커스텀 blit 셰이더를 구현.

**결과:** 추가 복잡도만 증가. VTK의 내부 상태와 커스텀 GL 호출이 충돌.

**교훈:** VTK의 공식 iOS 예제를 분석한 결과, **커스텀 blit는 불필요**하다는 결론. VTK의 `BlitToCurrent` 모드가 정상 동작하며, 핵심은 VTK의 State Tracker를 GLKView의 FBO와 동기화하는 것이었다.

**해결:** 커스텀 blit 코드 전체 삭제. VTK의 네이티브 blit에 의존.

---

#### 시도 3: BackgroundAlpha 기본값 문제

**증상:** DisplayFBO 픽셀 읽기 결과 `R=0 G=0 B=0 A=255`

**원인:** VTK의 `BackgroundAlpha` 기본값이 **0.0**이다. 이 때문에 `Transparent()` 함수가 `true`를 반환하고, VTK가 `glClear(GL_COLOR_BUFFER_BIT)`를 **생략**한다. macOS에서는 gradient background 셰이더가 배경을 따로 그려서 문제가 없지만, iOS ES 3.0에서는 gradient 셰이더가 실패하므로 FBO가 초기화되지 않은 상태로 남는다.

```cpp
// vtkOpenGLRenderer.cxx
if (!this->Transparent())  // BackgroundAlpha=0.0이면 Transparent()=true
{
    glClear(GL_COLOR_BUFFER_BIT);  // 이 줄이 실행 안 됨!
}
```

**해결:**
```objc
_data->renderer->SetBackgroundAlpha(1.0);
```

---

#### 시도 4: Gradient Background 셰이더 실패

**증상:** SetGradientBackground(true) 상태에서 배경이 표시되지 않음

**원인:** VTK의 gradient background는 화면 전체를 덮는 쿼드를 셰이더로 그리는 방식인데, 이 셰이더가 ES 3.0에서 컴파일에 실패한다.

**해결:**
```objc
#if TARGET_OS_IPHONE
    _data->renderer->SetGradientBackground(false);  // 단색 배경 사용
#endif
```

---

#### 시도 5: VTK State Tracker 비동기화

**증상:** VTK 렌더링이 GLKView의 FBO가 아닌 다른 곳에 그려짐

**원인:** GLKView가 `[glkView display]` 시 직접 GL 호출(`glBindFramebuffer`)로 자체 FBO를 바인딩한다. VTK의 `vtkOpenGLState`는 이 외부 변경을 인식하지 못하여 FBO 상태 불일치가 발생.

**해결:**
```objc
- (void)performVTKRender {
    // GLKView가 바인딩한 FBO를 VTK State Tracker에 동기화
    vtkOpenGLRenderWindow *glRenWin = ...;
    GLint glkFBO = 0;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &glkFBO);
    glRenWin->GetState()->vtkglBindFramebuffer(GL_FRAMEBUFFER, (unsigned int)glkFBO);

    _data->renderWindow->Render();
}
```

**결과:** Sphere + 단색 배경 렌더링 성공. iOS VTK 렌더링 파이프라인 정상 동작 확인.

---

### 3.2 Phase 2: Volume Rendering 셰이더 ES 3.0 호환성

기본 렌더링(구, 배경)은 성공했지만, Volume Rendering 전환 시 다시 검은 화면 발생.

#### 문제 1: Float 리터럴 `f` 접미사

**GLSL ES 3.0에서는 float 리터럴에 `f` 접미사가 허용되지 않는다.**

Desktop GLSL:
```glsl
float x = 1.0f;   // OK
float y = 2.f;     // OK
```

GLSL ES 3.0:
```glsl
float x = 1.0f;   // COMPILE ERROR
float y = 2.f;     // COMPILE ERROR
float x = 1.0;    // OK
```

**수정 파일 및 위치:**

`raycasterfs.glsl` (3개소):
```glsl
// Before:
WinCoord.x = (xNDC + 1.f) / (2.f * in_inverseWindowSize.x) + ...
// After:
WinCoord.x = (xNDC + 1.0) / (2.0 * in_inverseWindowSize.x) + ...
```

`vtkVolumeShaderComposer.h` (4개소):
```glsl
// Before:
g_fragColor = (1.0f - g_fragColor.a) * g_srcColor + g_fragColor;
// After:
g_fragColor = (1.0 - g_fragColor.a) * g_srcColor + g_fragColor;
```

---

#### 문제 2: int/float 암시적 비교

ES 3.0 스펙상 int→float 암시적 변환은 허용되지만, 일부 모바일 GPU 드라이버에서 엄격하게 처리할 수 있으므로 명시적 변환으로 수정.

`vtkVolumeShaderComposer.h` 수정 항목:

| 위치 | Before | After |
|------|--------|-------|
| gradient magnitude (2곳) | `range != 0` | `range != 0.0` |
| isosurface | `g_currentT == 0` | `g_currentT == 0.0` |
| mask compositing (3곳) | `g_srcColor.a > 0` | `g_srcColor.a > 0.0` |
| mask blend | `opacity > 0` | `opacity > 0.0` |
| component weight | `in_componentWeight[i] <= 0` | `in_componentWeight[i] <= 0.0` |

---

#### 문제 3: uint/float 혼합 연산

`l_numSamples`는 `uint` 타입이고 `l_avgValue`는 `float` 타입. 나눗셈 시 명시적 캐스트 필요.

```glsl
// Before:
l_avgValue[i] = l_avgValue[i] * in_componentWeight[i] / l_numSamples[i];
// After:
l_avgValue[i] = l_avgValue[i] * in_componentWeight[i] / float(l_numSamples[i]);
```

---

#### 문제 4: int/float 혼합 연산 (Label Map)

```glsl
// Before:
floor(maskValue.r * in_labelMapNumLabels) / in_labelMapNumLabels;
// After:
floor(maskValue.r * float(in_labelMapNumLabels)) / float(in_labelMapNumLabels);
```

---

### 3.3 Phase 3: 3D 텍스처 포맷 비호환 (핵심 문제)

셰이더 수정 후에도 Volume은 **투명**(배경만 보임). `glGetError()`가 첫 렌더링에서 `1282 (GL_INVALID_OPERATION)` 반환.

#### 근본 원인: GL_R16이 ES 3.0에 존재하지 않음

VTK의 텍스처 포맷 매핑 (`vtkOpenGLState::InitializeTextureInternalFormats`):

```cpp
#ifdef GL_R16   // ← ES 3.0에서는 이 매크로가 정의되지 않음!
  TextureInternalFormats[VTK_UNSIGNED_SHORT][0][1] = GL_R16;
#endif
```

**iOS ES 3.0에서 사용 가능한 16-bit 관련 포맷:**

| 포맷 | ES 3.0 | 용도 |
|------|--------|------|
| `GL_R16` (0x822A) | **없음** | normalized unsigned 16-bit (데스크톱 전용) |
| `GL_R16_SNORM` | **없음** | normalized signed 16-bit (데스크톱 전용) |
| `GL_R16F` (0x822D) | **있음** | half-float |
| `GL_R16I` (0x8233) | **있음** | signed integer |
| `GL_R16UI` (0x8234) | **있음** | unsigned integer |
| `GL_R16_EXT` | **없음** | EXT_texture_norm16 (iOS 미지원) |

#### VTK의 Fallback 동작

VTK의 `vtkTextureObject::GetDefaultInternalFormat`는 정규화 포맷 실패 시 float 포맷으로 fallback:

```
1. TextureInternalFormats[VTK_SHORT][0][1] = 0        (GL_R16_SNORM 없음)
2. TextureInternalFormats[VTK_SHORT][1][1] = GL_R32F   (float fallback)
```

**그러나 문제:** Internal format은 `GL_R32F`이지만 데이터 타입은 여전히 `GL_SHORT`. ES 3.0에서 `GL_R32F`는 오직 `GL_FLOAT` 타입 데이터만 허용.

```cpp
// 실제 호출되는 코드:
glTexImage3D(GL_TEXTURE_3D, 0,
    GL_R32F,          // internalFormat (float fallback)
    w, h, d, 0,
    GL_RED,           // format
    GL_SHORT,         // type ← GL_R32F와 비호환!
    data);
// → GL_INVALID_OPERATION (1282)
```

**ES 3.0 유효 조합 (GL_R32F):**
- format=`GL_RED`, type=`GL_FLOAT` **만** 허용

#### 해결: vtkImageCast로 데이터를 float 변환

DICOM 데이터를 GPU에 올리기 전에 CPU에서 float로 변환:

```objc
#if TARGET_OS_IPHONE
    vtkSmartPointer<vtkImageCast> castToFloat = vtkSmartPointer<vtkImageCast>::New();
    castToFloat->SetInputConnection(pipelineOutput);
    castToFloat->SetOutputScalarTypeToFloat();
    castToFloat->Update();
    pipelineOutput = castToFloat->GetOutputPort();
#endif
```

이렇게 하면:
```
VTK_FLOAT → GetDefaultTextureInternalFormat:
  1. TextureInternalFormats[VTK_FLOAT][0][1] = 0 (없음)
  2. TextureInternalFormats[VTK_FLOAT][1][1] = GL_R32F (float fallback)

glTexImage3D(GL_TEXTURE_3D, 0, GL_R32F, ..., GL_RED, GL_FLOAT, data);
→ 유효한 조합! 성공!
```

**트레이드오프:** 메모리 사용량 2배 증가 (short 2바이트 → float 4바이트). 256^3 볼륨 기준 약 32MB → 64MB.

---

## 4. VTK Shader Cache의 ES 3.0 자동 변환

VTK의 `vtkOpenGLShaderCache::ReplaceShaderValues`가 자동으로 처리하는 항목:

| 항목 | Desktop GLSL | ES 3.0 변환 |
|------|-------------|-------------|
| 버전 | `#version 150` | `#version 300 es` |
| texture 호출 | `texture1D()`, `texture2D()`, `texture3D()` | `texture()` (`#define` 매크로) |
| Fragment 출력 | `gl_FragData[N]` | `layout(location=N) out vec4 fragOutputN;` |
| Varying | `varying` | `in` (fragment), `out` (vertex) |
| Attribute | `attribute` | `in` |
| samplerBuffer | `samplerBuffer` | `sampler2D` (2D 에뮬레이션) |
| texelFetch | `texelFetchBuffer(a,b)` | `texelFetch(a, Get2DIndexFrom1DIndex(b, textureSize(a,0)), 0)` |
| Precision | 없음 | `precision highp float;`, `precision highp sampler2D;` 등 |

**자동 변환되지 않는 항목 (수동 수정 필요):**

| 항목 | 문제 | 해결 |
|------|------|------|
| `f` 접미사 | `1.0f`, `2.f` 등이 ES에서 컴파일 에러 | 수동으로 `f` 제거 |
| `sampler1D` | ES 3.0에 1D 텍스처 없음 | 직교 그리드 코드 경로에서만 사용, 일반 DICOM에는 해당 없음 |
| 텍스처 포맷 | `GL_R16` 없음 | 데이터를 float로 변환 |

---

## 5. iOS 전용 설정 체크리스트

### 5.1 Renderer 설정

```objc
#if TARGET_OS_IPHONE
renderer->SetBackgroundAlpha(1.0);        // 필수: 기본값 0.0은 glClear 생략 유발
renderer->SetGradientBackground(false);   // 필수: gradient 셰이더 ES 3.0 비호환
#endif
```

### 5.2 RenderWindow 설정

```objc
renWin->SetMultiSamples(0);  // ES 3.0에서 MSAA FBO 복잡도 회피
// SetUseOffScreenBuffers(true) 사용 금지 — Frame() blit 생략됨
```

### 5.3 State Tracker 동기화

```objc
// GLKView의 FBO를 VTK에 알리기 (매 렌더 프레임마다)
GLint glkFBO = 0;
glGetIntegerv(GL_FRAMEBUFFER_BINDING, &glkFBO);
glRenWin->GetState()->vtkglBindFramebuffer(GL_FRAMEBUFFER, (unsigned int)glkFBO);
```

### 5.4 Volume 데이터 전처리

```objc
#if TARGET_OS_IPHONE
// ES 3.0 GL_R16 없음 → float 변환 필수
vtkSmartPointer<vtkImageCast> castToFloat = vtkSmartPointer<vtkImageCast>::New();
castToFloat->SetInputConnection(pipelineOutput);
castToFloat->SetOutputScalarTypeToFloat();
castToFloat->Update();
pipelineOutput = castToFloat->GetOutputPort();
#endif
```

### 5.5 VTK 에러 출력 활성화

```objc
#if TARGET_OS_IPHONE
vtkOutputWindow::GetInstance()->SetDisplayModeToAlwaysStdErr();
#endif
```

---

## 6. 수정된 VTK 소스 파일

### 6.1 GLSL 셰이더 수정

**`vtk-src/Rendering/VolumeOpenGL2/shaders/raycasterfs.glsl`**
- `1.f` → `1.0` (2곳)
- `2.f` → `2.0` (2곳)
- `/ 2.f` → `/ 2.0` (1곳)

**`vtk-src/Rendering/VolumeOpenGL2/vtkVolumeShaderComposer.h`**
- `1.0f` → `1.0` (4곳: alpha compositing)
- `range != 0` → `range != 0.0` (2곳: gradient magnitude)
- `g_currentT == 0` → `g_currentT == 0.0` (1곳: isosurface)
- `g_srcColor.a > 0` → `g_srcColor.a > 0.0` (3곳: mask compositing)
- `opacity > 0` → `opacity > 0.0` (1곳: mask blend)
- `in_componentWeight[i] <= 0` → `<= 0.0` (1곳: multi-component)
- `/ l_numSamples[i]` → `/ float(l_numSamples[i])` (1곳: average blend)
- `l_avgValue.x /= l_numSamples.x` → `/= float(l_numSamples.x)` (1곳)
- `* in_labelMapNumLabels` → `* float(in_labelMapNumLabels)` (2곳: label map)

**총 19개소 수정**

### 6.2 수정하지 않은 파일 (자동 처리됨)

- `vtkOpenGLShaderCache.cxx` — `#version 300 es`, `texture3D→texture` 등 자동 변환
- `vtkIOSRenderWindow.mm` — `BlitToCurrent` 모드 기본 설정됨
- `vtkOpenGLRenderWindow.cxx` — FBO 생성/관리 로직 (수정 불필요)

---

## 7. VTK iOS 빌드 과정

### 7.1 VTK 소스 수정 후 재빌드

```bash
# 1. Device (arm64) 빌드
cd vtk-build/ios-superbuild/CMakeExternals/Build/vtk-ios-device-arm64
cmake --build . --config Release -j8

# 2. Install
cmake --install . --config Release \
  --prefix vtk-build/ios-superbuild/CMakeExternals/Install/vtk-ios-device-arm64

# 3. Combined static library 생성
cd vtk-install/ios-arm64/lib
libtool -static -o libVTK.a \
  $(ls /path/to/Install/vtk-ios-device-arm64/lib/*.a)
```

### 7.2 라이브러리 구성

- 최종 `libVTK.a`: ~213 MB (57개 정적 라이브러리 결합)
- 주요 구성: `libvtkRenderingOpenGL2`, `libvtkRenderingVolumeOpenGL2`, `libvtkIOImage`, `libvtkCommonCore` 등

---

## 8. 알려진 경고 (무시 가능)

### 8.1 Color Buffer Size 쿼리 실패

```
WARN: Failed to get red color buffer size (1280)
```

**원인:** `vtkOpenGLRenderWindow::GetColorBufferSizes`가 `GL_BACK_LEFT` enum으로 framebuffer attachment를 쿼리하는데, `GL_BACK_LEFT`는 ES 3.0에 존재하지 않음 (데스크톱 GL 전용). `GL_INVALID_ENUM (1280)` 발생.

**영향:** `AlphaBitPlanes`가 0으로 설정됨. Depth Peeling 등 일부 고급 기능에 영향을 줄 수 있으나, 기본 Volume Rendering에는 영향 없음.

### 8.2 OpenGL ES Deprecation 경고

```
'glGenBuffers' is deprecated: first deprecated in iOS 12.0
```

**영향:** 없음. iOS에서 OpenGL ES는 deprecated이지만, Metal 백엔드를 통해 여전히 동작함.

---

## 9. 아키텍처 다이어그램

### 9.1 데이터 파이프라인 (iOS)

```
DICOM Files
    │
    ▼
vtkDICOMImageReader (VTK_SHORT, 512x512x108)
    │
    ▼
vtkImageThreshold (HU < -1000 클램프)
    │
    ▼
vtkImageResample (256^3 이하로 다운샘플, factor=0.84)
    │
    ▼
vtkImageCast → VTK_FLOAT  ★ iOS 전용 (ES 3.0 GL_R16 없음 대응)
    │
    ▼
vtkSmartVolumeMapper (GPU mode)
    │ Create3DFromRaw(VTK_FLOAT)
    │ → glTexImage3D(GL_R32F, GL_RED, GL_FLOAT)  ✓ ES 3.0 호환
    ▼
vtkOpenGLGPUVolumeRayCastMapper
    │ Ray Casting Fragment Shader
    │ (vtkVolumeShaderComposer가 동적 생성)
    ▼
Volume Rendering 출력
```

### 9.2 Bridge 구조 (Swift ↔ VTK)

```
SwiftUI View
    │
    ├── UIViewRepresentable
    │       │
    │       └── VTKContainerView (UIView)
    │               │
    │               ├── GLKView (서브뷰)
    │               │     ├── EAGLContext (ES 3.0)
    │               │     └── GLKViewDelegate
    │               │           └── glkView:drawInRect:
    │               │                 └── [bridge performVTKRender]
    │               │
    │               └── VTKBridge (Obj-C++)
    │                     ├── vtkIOSRenderWindow
    │                     ├── vtkRenderer
    │                     ├── vtkSmartVolumeMapper
    │                     └── Transfer Functions
    │
    └── SwiftUI Controls (프리셋, 슬라이더 등)
          │
          └── [bridge applyVolumePreset:]
```

---

## 10. 문제 해결 타임라인 요약

| 단계 | 문제 | 증상 | 근본 원인 | 해결 |
|------|------|------|-----------|------|
| 1 | OffScreenBuffers | 검은 화면 | Frame()에서 SwapBuffers=0 → blit 생략 | 제거 |
| 2 | 커스텀 Blit | 불안정/복잡 | 불필요한 접근 | VTK 네이티브 blit 사용 |
| 3 | BackgroundAlpha | R=0,G=0,B=0,A=255 | Alpha=0 → glClear 생략 | Alpha=1.0 |
| 4 | Gradient BG | 배경 없음 | ES 3.0 셰이더 비호환 | 비활성화 |
| 5 | State Tracker | 잘못된 FBO에 렌더 | GLKView FBO 비동기 | vtkglBindFramebuffer 동기화 |
| 6 | `f` 접미사 | 셰이더 컴파일 실패 | ES 3.0 문법 위반 | 수동 제거 (19곳) |
| 7 | int/float 비교 | 잠재적 컴파일 실패 | ES 3.0 엄격 타입 | 명시적 float 리터럴 |
| 8 | **3D 텍스처 포맷** | **투명 볼륨** | **GL_R16 없음 → GL_R32F+GL_SHORT 비호환** | **vtkImageCast→float** |

---

## 11. 향후 개선 사항

### 11.1 메모리 최적화
- 현재 float 변환으로 텍스처 메모리 2배 사용
- `EXT_texture_norm16` 런타임 확인 → `GL_R16_EXT` 지원 시 short 직접 업로드 가능
- 또는 VTK 내부에서 unsigned short → half-float(GL_R16F) 변환 구현

### 11.2 Color Buffer Size 경고 해결
- `vtkIOSRenderWindow`에서 `GetColorBufferSizes` 오버라이드
- GLKView FBO 바인딩 시 `GL_COLOR_ATTACHMENT0`으로 쿼리

### 11.3 성능 최적화
- 볼륨 다운샘플링 최적화 (현재 256^3 제한)
- LOD (Level of Detail) 적용
- 인터랙션 중 저해상도 렌더링

### 11.4 Metal 마이그레이션
- OpenGL ES는 iOS 12부터 deprecated
- VTK의 Metal 백엔드 또는 커스텀 Metal 렌더러로 전환 고려
- 장기적으로 Metal이 성능/호환성 모두 우수

---

## 12. 참고 자료

- VTK 공식 iOS 예제: `vtk-src/Examples/iOS/`
- OpenGL ES 3.0 스펙: Khronos Group (Table 3.2 — Valid format/type/internalformat 조합)
- VTK 셰이더 캐시: `vtk-src/Rendering/OpenGL2/vtkOpenGLShaderCache.cxx`
- VTK 볼륨 셰이더 컴포저: `vtk-src/Rendering/VolumeOpenGL2/vtkVolumeShaderComposer.h`
- VTK 텍스처 포맷 매핑: `vtk-src/Rendering/OpenGL2/vtkOpenGLState.cxx` (InitializeTextureInternalFormats)
