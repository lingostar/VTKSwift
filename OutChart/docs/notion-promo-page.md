# OutChart

### CT/MRI 영상을 3D로, 당신의 손 안에

---

## 소개

**OutChart**는 DICOM 의료 영상을 쉽게 열람하고 3D로 시각화하는 Apple 네이티브 앱입니다.
CT, MRI, 초음파 영상을 2D 슬라이스로 탐색하고, 실시간 3D 볼륨 렌더링으로 입체적으로 확인하며, AR 지원 USDZ 모델로 내보낼 수 있습니다.

> "참조/열람용(Reference Only)" — 교육, 수술 계획 참고, 환자 설명, 3D 프린팅 모형 제작 용도

---

## 주요 기능

### DICOM 2D 슬라이스 뷰어
CT/MRI 영상의 전체 슬라이스를 슬라이더로 탐색합니다.
거리(mm)와 각도 측정 도구를 제공하며, 슬라이스별로 측정 결과를 저장합니다.

### 3D 볼륨 렌더링
VTK 기반 실시간 3D 렌더링으로 환자의 해부학적 구조를 입체적으로 확인합니다.
Soft Tissue, Bone, Lung, Brain, Abdomen 등 프리셋을 원클릭으로 전환할 수 있습니다.

### USDZ AR 모델 내보내기
CT 데이터에서 Bone, Skin, Soft Tissue 등 조직별 3D 모델을 자동 생성합니다.
iPhone/iPad에서 AR로 바로 확인하거나, 3D 프린팅용으로 활용할 수 있습니다.

### 다중 Study 관리
한 환자에 여러 CT/MRI 세트를 날짜별로 관리합니다.
캐러셀 UI로 빠르게 전환하고, 별칭(Alias) 기반 등록으로 개인정보를 보호합니다.

---

## 지원 플랫폼

| 플랫폼 | 지원 |
|--------|------|
| macOS 14+ | Split View, 파일 관리 |
| iPad (iPadOS 17+) | Split View, 터치 제스처 |
| iPhone (iOS 17+) | 풀스크린 내비게이션 |
| visionOS | 향후 지원 예정 |

---

## 기술 스택

| 영역 | 기술 |
|------|------|
| UI 프레임워크 | SwiftUI |
| 데이터 저장 | SwiftData |
| 3D 렌더링 엔진 | VTK 9.4 (C++) + Metal |
| 3D 모델 생성 | SceneKit |
| DICOM 파싱 | 순수 Swift 구현 |
| C++ 브릿지 | Objective-C++ |

---

## 스크린샷

> 이 섹션에 앱 스크린샷을 추가하세요:
> 1. DICOM 슬라이스 뷰어 (측정 도구 사용 중)
> 2. 3D 볼륨 렌더링 (Bone 프리셋)
> 3. USDZ 3D 프리뷰
> 4. 환자 목록 + Study 캐러셀

---

## 사용 시나리오

### 의사 / 외과의
수술 전 환자의 CT 영상을 3D로 확인하고, USDZ 모델을 AR로 환자에게 직접 보여줍니다.

### 의대생 / 레지던트
해부학 교육 자료로 활용하며, 다양한 조직 프리셋으로 인체 구조를 학습합니다.

### 연구원
의료 영상 데이터를 시각화하고, 3D 모델을 내보내 논문이나 발표 자료에 활용합니다.

---

## 로드맵

### 완료
- DICOM 2D 뷰어 + 측정 도구
- 3D 볼륨 렌더링 (5종 CT 프리셋)
- USDZ AR 모델 자동 생성
- 다중 Study 관리
- macOS + iOS 동시 지원

### 진행 중
- 실제 Pixel Spacing 기반 정확한 mm 측정
- UI/UX 개선

### 계획
- visionOS 지원 (Apple Vision Pro)
- iCloud 동기화
- STL/OBJ 내보내기
- AI 자동 세그먼테이션

---

## 규제 전략

OutChart는 **참조/열람용(Reference Only)** 의료 영상 뷰어입니다.

- FDA Class I / 식약처 저등급 분류 대상
- 임상 진단 기능 완전 배제
- 모든 측정값에 "Reference Only" 면책 표시
- 개인정보 보호: 별칭(Alias) 기반 환자 등록

---

## 연락처

- **개발자:** 윤성관 (skyoon@g.postech.edu)
- **팀:** AcademyLingo
- **저장소:** GitHub — VTKSwift

---

*OutChart는 AcademyLingo에서 개발하는 오픈소스 프로젝트입니다.*
