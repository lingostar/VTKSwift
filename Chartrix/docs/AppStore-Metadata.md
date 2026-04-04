# Chartrix — App Store Connect Metadata

> Copy-paste ready text for App Store Connect (https://appstoreconnect.apple.com)

---

## 1. App Information

| Field | Value |
|-------|-------|
| **App Name** | Chartrix |
| **Subtitle** | Medical Imaging 3D Viewer |
| **Bundle ID** | `com.codershigh.Chartrix` |
| **SKU** | `chartrix-001` |
| **Primary Language** | English (en-US) |
| **Primary Category** | Medical |
| **Secondary Category** | Education |
| **Content Rating** | 4+ (Medical/Treatment Information) |
| **Price** | Free |
| **Version** | 1.0.0 |
| **Build Number** | 1 |

---

## 2. App Description — English (Primary)

> 4,000 characters max. App Store Connect → App Information → Description

```
Chartrix is a medical DICOM imaging viewer that lets you browse CT and MRI scans and visualize them in 3D — right on your iPhone, iPad, or Mac.

DICOM 2D Slice Viewer
Browse through every slice of a CT/MRI study with an intuitive slider. Use built-in distance and angle measurement tools, and save results per slice for future reference.

Real-Time 3D Volume Rendering
VTK-powered 3D rendering lets you explore patient anatomy in full 3D. Rotate, zoom, and pan with touch gestures. Switch instantly between five visualization presets: Soft Tissue, Bone, Lung, Brain, and Abdomen.

USDZ 3D Model Export
Automatically generate 3D surface models for Bone, Skin, and Soft Tissue from CT data. Preview in augmented reality with AR Quick Look, share with colleagues, or use for 3D printing.

Patient Chart Management
Organize multiple CT/MRI studies per patient, sorted by date. Alias-based registration protects patient privacy. Attach notes and measurements to each chart. Everything syncs across your devices via iCloud.

Cross-Device iCloud Sync
Your charts, studies, measurements, and notes sync seamlessly between iPhone, iPad, and Mac. DICOM files are stored in iCloud Documents and download on demand.

Reference Only
Chartrix is a reference-only medical imaging viewer designed for education, surgical planning references, patient communication, and research visualization. It is not intended for clinical diagnosis.

Requires iOS 17 / macOS 14 or later.
```

---

## 3. App Description — Korean (Localization)

```
Chartrix는 CT, MRI 등 의료 DICOM 영상을 iPhone, iPad, Mac에서 쉽게 열람하고 3D로 시각화하는 앱입니다.

DICOM 2D 슬라이스 뷰어
CT/MRI 영상의 전체 슬라이스를 슬라이더로 자유롭게 탐색합니다. 거리와 각도 측정 도구를 제공하며, 슬라이스별로 측정 결과를 저장할 수 있습니다.

실시간 3D 볼륨 렌더링
VTK 기반 3D 렌더링으로 환자의 해부학적 구조를 입체적으로 확인합니다. 손가락으로 회전, 확대, 이동하여 다양한 각도에서 살펴보세요. Soft Tissue, Bone, Lung, Brain, Abdomen 등 프리셋을 원터치로 전환할 수 있습니다.

USDZ 3D 모델 내보내기
CT 데이터에서 Bone, Skin, Soft Tissue 등 조직별 3D 모델을 자동 생성합니다. AR Quick Look으로 실제 공간에 3D 모델을 띄워보거나, 3D 프린팅용으로 활용할 수 있습니다.

환자 차트 관리
한 환자에 여러 CT/MRI 세트를 날짜별로 관리합니다. 별칭(Alias) 기반 등록으로 개인정보를 보호합니다. 메모와 측정 기록을 차트에 함께 저장합니다. iCloud를 통해 모든 기기 간 동기화됩니다.

참조/열람 전용 (Reference Only)
Chartrix는 교육, 수술 계획 참고, 환자 설명, 연구 시각화 등 참조 목적의 의료영상 뷰어입니다. 임상 진단용이 아닙니다.

iOS 17 / macOS 14 이상 필요.
```

---

## 4. Keywords (100 characters max, comma-separated)

### English
```
DICOM,medical,imaging,CT,MRI,3D,volume,rendering,viewer,anatomy,USDZ,AR
```

### Korean
```
DICOM,의료영상,CT,MRI,3D,볼륨렌더링,의료,뷰어,해부학,USDZ,AR
```

---

## 5. Promotional Text (170 characters max, editable without review)

### English
```
View CT/MRI DICOM scans in 3D. Real-time volume rendering, AR 3D model export, 5 visualization presets, and iCloud sync across all your devices.
```

### Korean
```
CT/MRI DICOM 영상을 3D로 보세요. 실시간 볼륨 렌더링, AR 3D 모델 내보내기, 5종 프리셋, iCloud 동기화 지원.
```

---

## 6. What's New (Version 1.0)

### English
```
Chartrix 1.0 — Initial Release

- DICOM 2D slice viewer with distance and angle measurement
- Real-time 3D volume rendering with 5 CT presets
- USDZ 3D model export with AR Quick Look
- Multi-patient chart management with notes
- iCloud sync across iPhone, iPad, and Mac
```

### Korean
```
Chartrix 1.0 — 첫 번째 릴리즈

- DICOM 2D 슬라이스 뷰어 (거리/각도 측정)
- 실시간 3D 볼륨 렌더링 (5종 CT 프리셋)
- USDZ 3D 모델 AR 내보내기
- 다중 환자 차트 관리 및 메모
- iPhone, iPad, Mac 간 iCloud 동기화
```

---

## 7. App Review Information

### Contact
| Field | Value |
|-------|-------|
| **Name** | Sungkwan Yoon |
| **Email** | skyoon@g.postech.edu |
| **Phone** | (Use Apple Developer account phone number) |

### Review Notes

```
Chartrix is a reference-only DICOM medical imaging viewer. It does NOT provide clinical diagnosis.

To test the app, you will need DICOM image files (CT/MRI). You can obtain free sample DICOM datasets from:
- https://www.dicomlibrary.com
- https://wiki.cancerimagingarchive.net

Steps to test:
1. Open the app and tap "+" to create a new patient chart.
2. Enter an alias (e.g., "Test Patient") and select a DICOM folder.
3. Browse 2D slices using the slider.
4. Switch to "Volume" tab to see 3D rendering. Rotate with one finger.
5. Switch to "USDZ" tab to generate and preview the 3D model in AR.

No login is required. No personal health data is collected or transmitted.
All data processing happens locally on-device. iCloud sync only stores user-created charts and imported DICOM files in the user's private iCloud container.
```

### Demo Account
```
No login required
```

---

## 8. Age Rating Questionnaire

| Question | Answer |
|----------|--------|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Sexual Content or Nudity | None |
| Medical/Treatment Information | **Yes (Infrequent/Mild)** |
| Gambling | None |
| Horror/Fear Themes | None |
| Drug Use or References | None |
| Profanity or Crude Humor | None |
| Unrestricted Web Access | None |

> Result: **4+** rating

---

## 9. Export Compliance

| Question | Answer |
|----------|--------|
| Does the app use encryption? | **No** |
| Uses only standard Apple encryption (HTTPS) | Yes |
| Contains custom encryption algorithms | No |

> `ITSAppUsesNonExemptEncryption = false` (already configured in project.yml)

---

## 10. URLs

| Field | URL |
|-------|-----|
| **Privacy Policy** | `https://lingostar.github.io/Chartrix/privacy` |
| **Support URL** | `https://lingostar.github.io/Chartrix/support` |
| **Marketing URL** | `https://lingostar.github.io/Chartrix/` |

---

## 11. Screenshot Guide

### Required Sizes

| Device | Resolution (px) | Required |
|--------|-----------------|----------|
| iPhone 6.9" (16 Pro Max) | 1320 x 2868 | Required |
| iPhone 6.7" (15 Pro Max) | 1290 x 2796 | Required |
| iPhone 6.5" (14 Plus) | 1284 x 2778 | Optional |
| iPad Pro 13" (M4) | 2064 x 2752 | Required (iPad) |
| iPad Pro 12.9" (6th) | 2048 x 2732 | Required (iPad) |
| Mac | 2880 x 1800 or 1280 x 800 | Required (macOS) |

### Recommended Screenshots (5 scenes)

1. **Chart List** — "All your patients at a glance" / Patient list with search
2. **DICOM Slice Viewer** — "Browse CT/MRI slices freely" / Measurement tools in use
3. **3D Volume Rendering** — "Real-time 3D anatomy" / Bone preset applied
4. **Preset Switching** — "5 one-touch visualization presets" / Preset carousel shown
5. **USDZ AR Model** — "3D models in your hands with AR" / Quick Look preview

---

## 12. Submission Checklist

### Apple Developer Portal
- [ ] Active Apple Developer Program subscription
- [ ] App ID registered: `com.codershigh.Chartrix`
- [ ] iCloud container registered: `iCloud.codershigh.Chartrix`
- [ ] iOS Distribution provisioning profile created
- [ ] macOS Distribution provisioning profile created

### App Store Connect
- [ ] New app created (Bundle ID: com.codershigh.Chartrix)
- [ ] Primary language set to English
- [ ] App description entered (English)
- [ ] Korean localization added
- [ ] Keywords entered
- [ ] Promotional text entered
- [ ] Privacy Policy URL set
- [ ] Support URL set
- [ ] Marketing URL set

### Screenshots
- [ ] iPhone screenshots (6.9" + 6.7") — 5 images
- [ ] iPad screenshots (13" Pro) — 5 images
- [ ] Mac screenshots — 5 images

### Build & Upload
- [ ] Xcode: Archive Chartrix-iOS → Upload to App Store Connect
- [ ] Xcode: Archive Chartrix-macOS → Upload to App Store Connect
- [ ] Select builds in App Store Connect

### Review Submission
- [ ] App Review contact information entered
- [ ] Review notes entered (testing instructions)
- [ ] Age rating questionnaire completed
- [ ] Export compliance answered
- [ ] Price set to Free
- [ ] Click "Submit for Review"
