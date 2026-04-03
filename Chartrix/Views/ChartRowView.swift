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
                if chart.studies.isEmpty {
                    Text("No studies")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(chart.sortedStudies.prefix(3)) { study in
                            studyRow(study)
                        }
                        if chart.studies.count > 3 {
                            Text("+\(chart.studies.count - 3) more")
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
            ZStack {
                Color.black

                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .scaledToFill()
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

    private func loadThumbnail() {
        guard let study = chart.latestStudy,
              let dirURL = ChartStorage.dicomDirectoryURL(for: study) else { return }
        DispatchQueue.global(qos: .utility).async {
            let image = DICOMSliceRenderer.renderMiddleSlice(directoryURL: dirURL)
            DispatchQueue.main.async {
                thumbnailImage = image
            }
        }
    }
}
