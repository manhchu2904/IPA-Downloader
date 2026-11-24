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

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(logText.isEmpty ? "(Trống)" : logText)
                                    .font(.system(.caption2, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .textSelection(.enabled)
                                Color.clear
                                    .frame(height: 1)
                                    .id("LOG_BOTTOM")
                            }
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
                        .onAppear {
                            proxy.scrollTo("LOG_BOTTOM", anchor: .bottom)
                        }
                        .onChange(of: logText) { _ in
                            proxy.scrollTo("LOG_BOTTOM", anchor: .bottom)
                        }
                    }
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

private struct LogShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
