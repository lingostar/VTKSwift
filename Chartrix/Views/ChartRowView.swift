import SwiftUI

/// 차트 목록의 한 행 — 썸네일 + 환자 이름 + Study 목록
struct ChartRowView: View {
    let chart: Chart

    @State private var thumbnailImage: CGImage?
    @State private var didLoad = false

    var body: some View {
        HStack(spacing: 14) {
            // 썸네일 (최신 Study의 중간 슬라이스)
            thumbnail
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // 정보
            VStack(alignment: .leading, spacing: 6) {
                Text(chart.alias)
                    .font(.headline)
                    .lineLimit(1)

                // Study 목록
                if (chart.studies ?? []).isEmpty {
                    Text("No studies")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(chart.sortedStudies.prefix(3)) { study in
                            studyRow(study)
                        }
                        if (chart.studies ?? []).count > 3 {
                            Text("+\((chart.studies ?? []).count - 3) more")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .task {
            guard !didLoad else { return }
            didLoad = true
            loadThumbnail()
        }
    }

    // MARK: - Study Row

    private func studyRow(_ study: Study) -> some View {
        HStack(spacing: 6) {
            // iCloud 다운로드 상태 아이콘
            let status = ChartStorage.downloadStatus(for: study)
            if status == .notDownloaded {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if status == .downloading {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                    .symbolEffect(.pulse)
            }

            Text(study.modality)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(study.modalityColor)

            Text("\(study.imageCount) images")
                .font(.caption)
                .foregroundColor(.secondary)

            if !study.studyDate.isEmpty {
                Text(study.formattedStudyDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnail: some View {
        if let cgImage = thumbnailImage {
            ZStack(alignment: .bottomTrailing) {
                Color.black

                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .scaledToFill()

                // iCloud 배지 오버레이
                if hasCloudOnlyStudies {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(3)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .padding(4)
                }
            }
        } else if hasCloudOnlyStudies {
            // 썸네일 로드 불가 + iCloud 미다운로드
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.12))

                VStack(spacing: 4) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("iCloud")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.12))

                Image(systemName: "person.crop.rectangle.stack")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
    }

    /// Study 중 하나라도 iCloud에서 다운로드되지 않은 것이 있는지
    private var hasCloudOnlyStudies: Bool {
        guard ChartStorage.isICloudAvailable else { return false }
        return (chart.studies ?? []).contains { study in
            let s = ChartStorage.downloadStatus(for: study)
            return s == .notDownloaded || s == .downloading
        }
    }

    private func loadThumbnail() {
        guard let study = chart.latestStudy,
              let dirURL = ChartStorage.dicomDirectoryURL(for: study) else { return }

        // iCloud 파일이 아직 없으면 다운로드 트리거
        let status = ChartStorage.directoryDownloadStatus(dirURL)
        if status == .notDownloaded || status == .downloading {
            ChartStorage.startDownloadingDirectory(dirURL)
            return // 다운로드 완료 후 다시 로드되도록
        }

        DispatchQueue.global(qos: .utility).async {
            let image = DICOMSliceRenderer.renderMiddleSlice(directoryURL: dirURL)
            DispatchQueue.main.async {
                thumbnailImage = image
            }
        }
    }
}
