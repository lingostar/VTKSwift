# VTKSwift

VTK (Visualization Toolkit) C++ 라이브러리를 사용하는 Swift/SwiftUI 멀티플랫폼 앱.
iPad와 Mac에서 3D 구(Sphere)를 렌더링합니다.

## 프로젝트 구조

```
VTKSwift/
├── scripts/build_vtk.sh       # VTK 자동 빌드 스크립트
├── VTKSwiftApp/
│   ├── VTKSwiftApp.swift      # App 엔트리포인트
│   ├── ContentView.swift      # 메인 뷰
│   ├── VTKView.swift          # SwiftUI ViewRepresentable 래퍼
│   └── Bridge/
│       ├── VTKBridge.h        # ObjC 헤더
│       ├── VTKBridge.mm       # ObjC++ 구현 (VTK 파이프라인)
│       └── *-Bridging-Header.h
├── project.yml                # xcodegen 프로젝트 설정
└── VTKSwift.xcodeproj/        # 생성된 Xcode 프로젝트
```

## 빌드 방법

### 1. 사전 요구사항

```bash
brew install cmake ninja
xcode-select --install   # Xcode CLI tools
```

### 2. VTK 빌드

VTK C++ 라이브러리를 소스에서 빌드합니다 (최초 1회, 약 10~30분 소요):

```bash
cd /path/to/VTKSwift
./scripts/build_vtk.sh
```

이 스크립트가 수행하는 작업:
- VTK 9.4.2 소스 클론
- macOS arm64, iOS arm64, iOS Simulator arm64 빌드
- 개별 .a 파일들을 플랫폼별 `libVTK.a`로 합침
- `vtk-install/` 디렉토리에 헤더 및 라이브러리 설치

### 3. Xcode 프로젝트 생성/갱신

```bash
# xcodegen이 없다면 설치
brew install xcodegen

# 프로젝트 생성
xcodegen generate
```

### 4. 빌드 및 실행

1. `VTKSwift.xcodeproj` 을 Xcode에서 엽니다
2. **VTKSwift-iOS** 스킴을 선택하여 iPad Simulator에서 실행
3. **VTKSwift-macOS** 스킴을 선택하여 Mac에서 실행

## 아키텍처

```
SwiftUI (VTKView)
    ↓ UIViewRepresentable / NSViewRepresentable
Objective-C++ (VTKBridge)
    ↓ vtkSphereSource → vtkPolyDataMapper → vtkActor → vtkRenderer
VTK C++ Static Libraries
```

## 트러블슈팅

### VTK 빌드 실패
- CMake 3.20+ 필요: `cmake --version`으로 확인
- Xcode CLI 도구가 설치되어 있는지 확인: `xcode-select -p`

### 링커 에러 (undefined symbols)
- VTK가 빌드되었는지 확인: `ls vtk-install/macos-arm64/lib/libVTK.a`
- Header search path가 올바른지 확인 (project.yml의 vtk-9.4 부분)

### OpenGL deprecated 경고
- Apple이 OpenGL을 deprecated 했으나 여전히 동작합니다
- VTK는 Apple의 Metal 번역 레이어를 통해 OpenGL을 사용합니다
