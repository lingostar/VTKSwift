# Chartrix — App Store Connect 등록 메타데이터

> App Store Connect (https://appstoreconnect.apple.com) 에 복사·붙여넣기할 텍스트 모음

---

## 1. 앱 기본 정보

| 항목 | 값 |
|------|-----|
| **앱 이름** | Chartrix |
| **부제 (Subtitle)** | 의료영상 3D 뷰어 |
| **번들 ID** | `com.codershigh.Chartrix` |
| **SKU** | `chartrix-ios-001` |
| **기본 언어** | 한국어 (ko) |
| **카테고리 (Primary)** | Medical |
| **카테고리 (Secondary)** | Education |
| **콘텐츠 등급** | 4+ (의료/치료 정보) |
| **가격** | 무료 (Free) |
| **버전** | 1.0.0 |
| **빌드 번호** | 1 |

---

## 2. 앱 설명 (Description) — 한국어

> 4,000자 이내. App Store Connect → 앱 정보 → 설명

```
Chartrix는 CT, MRI 등 의료 DICOM 영상을 iPhone과 iPad에서 쉽게 열람하고 3D로 시각화하는 앱입니다.

◆ DICOM 2D 슬라이스 뷰어
CT/MRI 영상의 전체 슬라이스를 슬라이더로 자유롭게 탐색합니다. 거리와 각도 측정 도구를 제공하며, 슬라이스별로 측정 결과를 저장할 수 있습니다.

◆ 실시간 3D 볼륨 렌더링
VTK 기반 3D 렌더링으로 환자의 해부학적 구조를 입체적으로 확인합니다. 손가락으로 회전, 확대, 이동하여 다양한 각도에서 살펴보세요. Soft Tissue, Bone, Lung, Brain, Abdomen 등 프리셋을 원터치로 전환할 수 있습니다.

◆ USDZ 3D 모델 내보내기
CT 데이터에서 Bone, Skin, Soft Tissue 등 조직별 3D 모델을 자동 생성합니다. AR Quick Look으로 실제 공간에 3D 모델을 띄워보거나, 3D 프린팅용으로 활용할 수 있습니다.

◆ 환자 차트 관리
한 환자에 여러 CT/MRI 세트를 날짜별로 관리합니다. 별칭(Alias) 기반 등록으로 개인정보를 보호합니다. 메모와 측정 기록을 차트에 함께 저장합니다.

◆ 참조/열람 전용 (Reference Only)
Chartrix는 교육, 수술 계획 참고, 환자 설명, 연구 시각화 등 참조 목적의 의료영상 뷰어입니다. 임상 진단용이 아닙니다.

지원 기기: iPhone, iPad (iOS 17 이상)
```

---

## 3. 앱 설명 (Description) — English

```
Chartrix is a medical DICOM imaging viewer that lets you browse CT and MRI scans and visualize them in 3D — right on your iPhone or iPad.

◆ DICOM 2D Slice Viewer
Browse through every slice of a CT/MRI study with an intuitive slider. Use distance and angle measurement tools, and save results per slice.

◆ Real-Time 3D Volume Rendering
VTK-powered 3D rendering lets you explore patient anatomy in full 3D. Rotate, zoom, and pan with touch gestures. Switch instantly between presets: Soft Tissue, Bone, Lung, Brain, and Abdomen.

◆ USDZ 3D Model Export
Automatically generate 3D models for Bone, Skin, and Soft Tissue from CT data. View in AR with Quick Look or use for 3D printing.

◆ Patient Chart Management
Organize multiple CT/MRI studies per patient by date. Alias-based registration protects patient privacy. Attach notes and measurements to each chart.

◆ Reference Only
Chartrix is a reference-only medical imaging viewer for education, surgical planning references, patient communication, and research visualization. It is not intended for clinical diagnosis.

Requires: iPhone or iPad running iOS 17 or later.
```

---

## 4. 키워드 (Keywords)

> 100자 이내, 쉼표로 구분

### 한국어
```
DICOM,의료영상,CT,MRI,3D,볼륨렌더링,의료,뷰어,해부학,USDZ,AR
```

### English
```
DICOM,medical,imaging,CT,MRI,3D,volume,rendering,viewer,anatomy,USDZ,AR
```

---

## 5. 홍보 텍스트 (Promotional Text)

> 170자 이내. 앱 심사 없이 수시 변경 가능

### 한국어
```
CT/MRI DICOM 영상을 3D로 보세요. 실시간 볼륨 렌더링, AR 3D 모델 내보내기, 5종 프리셋 지원.
```

### English
```
View CT/MRI DICOM scans in 3D. Real-time volume rendering, AR 3D model export, and 5 visualization presets.
```

---

## 6. 새로운 기능 (What's New)

```
Chartrix 1.0 — 첫 번째 릴리즈

• DICOM 2D 슬라이스 뷰어 (거리/각도 측정)
• 실시간 3D 볼륨 렌더링 (5종 CT 프리셋)
• USDZ 3D 모델 AR 내보내기
• 다중 환자 차트 관리
• iPhone + iPad 지원
```

---

## 7. 앱 심사 정보 (App Review Information)

### 연락처
| 항목 | 값 |
|------|-----|
| **이름** | 윤성관 |
| **이메일** | skyoon@g.postech.edu |
| **전화번호** | (Apple Developer 계정의 번호 사용) |

### 심사 메모 (Review Notes)

```
Chartrix is a reference-only DICOM medical imaging viewer. It does NOT provide clinical diagnosis.

To test the app, you will need DICOM image files (CT/MRI). You can obtain free sample DICOM datasets from:
- https://www.dicomlibrary.com
- https://wiki.cancerimagingarchive.net

Steps to test:
1. Open the app and tap "+" to create a new patient chart.
2. Enter an alias (e.g., "Test Patient") and select a DICOM folder.
3. Browse 2D slices using the slider.
4. Switch to "Volume" tab to see 3D rendering. Use one finger to rotate.
5. Switch to "USDZ" tab to export and preview the 3D model.

No login is required. No personal health data is collected or transmitted.
The app processes all data locally on-device.
```

### 데모 계정
```
로그인 필요 없음 (No login required)
```

---

## 8. 연령 등급 (Age Rating) 답변 가이드

| 질문 | 답변 |
|------|------|
| 만화 또는 판타지 폭력 | 없음 |
| 현실적 폭력 | 없음 |
| 성적/선정적 콘텐츠 | 없음 |
| 의료/치료 정보 | **있음 (선택)** |
| 도박 | 없음 |
| 공포/두려움 테마 | 없음 |
| 약물 사용 또는 언급 | 없음 |
| 욕설 | 없음 |
| 무제한 웹 액세스 | 없음 |

> 결과: **4+** 등급

---

## 9. 수출 규정 준수 (Export Compliance)

| 질문 | 답변 |
|------|------|
| 앱이 암호화를 사용하는가? | **아니오** |
| 표준 Apple 암호화(HTTPS)만 사용 | 예 |
| 사용자 지정 암호화 알고리즘 포함 | 아니오 |

> `ITSAppUsesNonExemptEncryption = false` (이미 설정됨)

---

## 10. 개인정보 처리방침 URL

```
https://lingostar.github.io/Chartrix/privacy
```

> ⬆ GitHub Pages에 호스팅. 아래 privacy.html 파일 참조.

---

## 11. 지원 URL

```
https://github.com/lingostar/Chartrix/issues
```

---

## 12. 스크린샷 가이드

App Store Connect에 업로드할 스크린샷 크기:

| 디바이스 | 해상도 (px) | 필수 |
|----------|-------------|------|
| iPhone 6.9" (16 Pro Max) | 1320 × 2868 | ✅ 필수 |
| iPhone 6.7" (15 Pro Max) | 1290 × 2796 | ✅ 필수 |
| iPhone 6.5" (14 Plus) | 1284 × 2778 | 선택 |
| iPad Pro 13" (M4) | 2064 × 2752 | ✅ iPad 지원 시 필수 |
| iPad Pro 12.9" (6th) | 2048 × 2732 | ✅ iPad 지원 시 필수 |

### 권장 스크린샷 구성 (5장)

1. **차트 목록** — "나의 환자를 한눈에" / 환자 목록 + 검색
2. **DICOM 슬라이스 뷰어** — "CT/MRI 슬라이스를 자유롭게 탐색" / 측정 도구 사용 중
3. **3D 볼륨 렌더링** — "실시간 3D로 보는 해부학" / Bone 프리셋 적용
4. **프리셋 전환** — "원터치 프리셋 5종" / 프리셋 캐러셀 표시
5. **USDZ AR 모델** — "AR로 3D 모델을 내 손에" / Quick Look 프리뷰

> 💡 스크린샷은 실제 앱을 실행하여 캡처하세요.
> Xcode → Window → Devices and Simulators → 시뮬레이터에서 캡처하면 정확한 해상도를 얻을 수 있습니다.

---

## 13. 제출 전 체크리스트

- [ ] Apple Developer Program 활성 구독 확인
- [ ] App Store Connect에서 앱 등록 (번들 ID: com.codershigh.Chartrix)
- [ ] 인증서 및 프로비저닝 프로파일 생성 (Distribution)
- [ ] Xcode → Archive → Upload to App Store Connect
- [ ] 스크린샷 5장 업로드 (iPhone 6.9" + 6.7" 필수)
- [ ] iPad 스크린샷 업로드 (iPad Pro 13" 필수)
- [ ] 앱 설명 (한국어) 입력
- [ ] 키워드 입력
- [ ] 개인정보 처리방침 URL 설정
- [ ] 지원 URL 설정
- [ ] 앱 심사 정보 입력 (연락처 + 심사 메모)
- [ ] 수출 규정 준수 답변
- [ ] 연령 등급 설정
- [ ] 가격 설정 (무료)
- [ ] "심사를 위해 제출" 클릭
