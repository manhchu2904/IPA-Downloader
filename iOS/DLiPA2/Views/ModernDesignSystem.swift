import SwiftUI
import UIKit

enum AppTheme {
    static let primaryGradient = LinearGradient(
        colors: [
            Color(red: 0.04, green: 0.48, blue: 1.0),
            Color(red: 0.34, green: 0.36, blue: 0.96)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let emeraldGradient = LinearGradient(
        colors: [
            Color(red: 0.12, green: 0.78, blue: 0.45),
            Color(red: 0.06, green: 0.62, blue: 0.48)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let amberGradient = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.62, blue: 0.12),
            Color(red: 0.96, green: 0.44, blue: 0.16)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let coralGradient = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.32, blue: 0.36),
            Color(red: 0.86, green: 0.18, blue: 0.32)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let purpleGradient = LinearGradient(
        colors: [
            Color(red: 0.56, green: 0.32, blue: 0.96),
            Color(red: 0.36, green: 0.28, blue: 0.92)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let slateGradient = LinearGradient(
        colors: [
            Color(red: 0.38, green: 0.43, blue: 0.52),
            Color(red: 0.26, green: 0.30, blue: 0.38)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let groupedBackground = Color(UIColor.systemGroupedBackground)
    static let cardBackground = Color(UIColor.secondarySystemGroupedBackground)
    static let subtleSurface = Color(UIColor.tertiarySystemGroupedBackground)
}

struct ModernCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 18
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}

struct ModernIconBadge: View {
    let systemName: String
    let gradient: LinearGradient
    var size: CGFloat = 32
    var cornerRadius: CGFloat = 9

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(gradient)
            Image(systemName: systemName)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

struct ModernStatusPill: View {
    let text: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(.caption2)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.14))
        .foregroundColor(color)
        .clipShape(Capsule())
    }
}

struct ModernPrimaryButtonStyle: ButtonStyle {
    var gradient: LinearGradient = AppTheme.primaryGradient
    var isDisabled: Bool = false
    var fullWidth: Bool = true
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, fullWidth ? 13 : 12)
            .padding(.horizontal, fullWidth ? 16 : 24)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(gradient)
                    .opacity(isDisabled ? 0.45 : (configuration.isPressed ? 0.85 : 1.0))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct ModernSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.2 : 0.12))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct ModernEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var gradient: LinearGradient = AppTheme.primaryGradient
    var compact: Bool = false
    var actionTitle: String? = nil
    var actionIcon: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: compact ? 12 : 16) {
            ZStack {
                Circle()
                    .fill(gradient)
                    .opacity(0.12)
                    .frame(width: compact ? 68 : 80, height: compact ? 68 : 80)
                Circle()
                    .fill(gradient)
                    .frame(width: compact ? 48 : 58, height: compact ? 48 : 58)
                    .shadow(color: Color.accentColor.opacity(0.25), radius: 10, x: 0, y: 5)
                Image(systemName: icon)
                    .font(.system(size: compact ? 21 : 25, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 5) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 7) {
                        if let actionIcon {
                            Image(systemName: actionIcon)
                                .font(.subheadline.weight(.semibold))
                        }
                        Text(actionTitle)
                    }
                }
                .buttonStyle(ModernPrimaryButtonStyle(gradient: gradient, fullWidth: false, cornerRadius: 24))
                .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, compact ? 12 : 22)
    }
}

struct ModernSectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct ModernFloatingToast: View {
    let icon: String
    let title: String
    let subtitle: String?
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            ModernIconBadge(systemName: icon, gradient: AppTheme.emeraldGradient, size: 34, cornerRadius: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 14, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
