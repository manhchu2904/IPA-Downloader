import SwiftUI
import UIKit

struct DebugLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logText = DebugLogger.readLog()
    @State private var copied = false
    @State private var showShare = false

    var body: some View {
        NavigationView {
            ScrollView {
                Text(logText.isEmpty ? "(Trống)" : logText)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle("Debug Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        UIPasteboard.general.string = logText
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Đã copy" : "Copy log", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }

                    Spacer()

                    Button {
                        showShare = true
                    } label: {
                        Label("Chia sẻ", systemImage: "square.and.arrow.up")
                    }

                    Spacer()

                    Button {
                        logText = DebugLogger.readLog()
                    } label: {
                        Label("Tải lại", systemImage: "arrow.clockwise")
                    }

                    Spacer()

                    Button(role: .destructive) {
                        DebugLogger.clearLog()
                        logText = DebugLogger.readLog()
                    } label: {
                        Label("Xóa", systemImage: "trash")
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                LogShareSheet(items: [DebugLogger.logURL])
            }
        }
    }
}

private struct LogShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
