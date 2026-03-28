import SwiftUI
import QuickLook

// MARK: - USDZ Preview View

/// A cross-platform view that presents a USDZ file preview.
/// On iOS: Uses QLPreviewController for AR Quick Look support.
/// On macOS: Uses QuickLook preview panel for 3D preview.
struct USDZPreviewView: View {
    let fileURL: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                #if os(iOS)
                QLPreviewRepresentable(fileURL: fileURL)
                #elseif os(macOS)
                QuickLookPreviewRepresentable(fileURL: fileURL)
                #endif

                // Bottom info bar
                usdzInfoBar
            }
            .navigationTitle(fileURL.lastPathComponent)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    ShareLink(item: fileURL) {
                        Label("공유", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }

    private var usdzInfoBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "arkit")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("AR Quick Look 지원")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("iPhone/iPad에서 AR로 보거나, Vision Pro에서 공간에 배치할 수 있습니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(fileSizeString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var fileSizeString: String {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

// MARK: - iOS: QLPreviewController Wrapper

#if os(iOS)
import UIKit

private struct QLPreviewRepresentable: UIViewControllerRepresentable {
    let fileURL: URL

    func makeCoordinator() -> QLCoordinator {
        QLCoordinator(fileURL: fileURL)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        // Wrap in a nav controller to avoid presentation issues
        let nav = UINavigationController(rootViewController: controller)
        nav.setNavigationBarHidden(true, animated: false)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // No dynamic updates needed
    }

    class QLCoordinator: NSObject, QLPreviewControllerDataSource {
        let fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            fileURL as QLPreviewItem
        }
    }
}
#endif

// MARK: - macOS: QuickLook Preview

#if os(macOS)
import AppKit
import Quartz

private struct QuickLookPreviewRepresentable: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.previewItem = fileURL as QLPreviewItem
        view.autostarts = true
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = fileURL as QLPreviewItem
    }
}
#endif
