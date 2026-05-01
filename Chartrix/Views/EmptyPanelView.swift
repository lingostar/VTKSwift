import SwiftUI

// MARK: - Empty Panel View

/// Shown when a viewer panel has no study assigned.
/// Lists the chart's studies so the user can quickly load one.
struct EmptyPanelView: View {
    let studies: [Study]
    let onSelect: (Study) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)

            VStack(spacing: 12) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.5))

                Text("Select a study")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))

                if studies.isEmpty {
                    Text("No studies available in this chart")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(studies) { study in
                                Button {
                                    onSelect(study)
                                } label: {
                                    studyRow(study)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(maxHeight: 200)
                }
            }
            .padding(20)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .foregroundStyle(.white.opacity(0.25))
        )
    }

    private func studyRow(_ study: Study) -> some View {
        HStack(spacing: 8) {
            Text(study.modality)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(study.modalityColor.opacity(0.7), in: Capsule())
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                if !study.studyDescription.isEmpty {
                    Text(study.studyDescription)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if !study.studyDate.isEmpty {
                        Text(study.formattedStudyDate)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text("\(study.imageCount) images")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer()

            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}
