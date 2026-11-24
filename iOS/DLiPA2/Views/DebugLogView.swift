import SwiftUI
import UIKit

struct DebugLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logText = DebugLogger.readLog()
    @State private var copied = false
    @State private var showShare = false

    private var lineCount: Int {
        logText.isEmpty ? 0 : logText.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.groupedBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    LiquidGlassGroup(spacing: 8) {
                        HStack(spacing: 8) {
                            ModernStatusPill(text: "\(lineCount) dòng", color: .accentColor, icon: "terminal.fill")
                            Spacer()
                            Button {
                                UIPasteboard.general.string = logText
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    copied = false
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    Text(copied ? "Đã copy" : "Copy toàn bộ")
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .foregroundColor(copied ? .green : .accentColor)
                                .liquidGlassCapsule(
                                    tint: copied ? Color.green.opacity(0.22) : Color.accentColor.opacity(0.18),
                                    interactive: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    SelectableLogTextView(text: logText.isEmpty ? "(Trống)" : logText)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppTheme.cardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.75)
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }
            .navigationTitle("Debug Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        logText = DebugLogger.readLog()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        DebugLogger.clearLog()
                        logText = DebugLogger.readLog()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                LogShareSheet(items: [DebugLogger.logURL])
            }
        }
    }
}

private struct SelectableLogTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = true
        tv.backgroundColor = .clear
        tv.textColor = .label
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        tv.autocorrectionType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.dataDetectorTypes = []
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard uiView.text != text else { return }
        uiView.text = text
        DispatchQueue.main.async {
            let length = (uiView.text as NSString).length
            if length > 0 {
                uiView.scrollRangeToVisible(NSRange(location: max(0, length - 1), length: 1))
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
