import SwiftUI

// MARK: - 色彩

extension Color {
    init(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b, a: Double
        if cleaned.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255.0
            g = Double((value >> 16) & 0xFF) / 255.0
            b = Double((value >> 8) & 0xFF) / 255.0
            a = Double(value & 0xFF) / 255.0
        } else {
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >> 8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
            a = 1.0
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - 主题

enum Theme {
    static let accent = Color(hex: "E8C57A")
    static let accentDeep = Color(hex: "C9A25A")

    static let expense = Color(hex: "E8734A")
    static let income = Color(hex: "3FA96A")

    static let cardRadius: CGFloat = 20
    static let softShadow = Color.black.opacity(0.06)

    /// 深墨绿渐变，用于主视觉卡片
    static let heroGradient = LinearGradient(
        colors: [Color(hex: "1F2B33"), Color(hex: "2D4A3E")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradientLight = LinearGradient(
        colors: [Color(hex: "2D4A3E"), Color(hex: "3C6353")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - 卡片容器

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }

    /// 主按钮样式
    func primaryButtonStyle() -> some View {
        self
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color(hex: "1F2B33"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.accent)
            )
    }
}

// MARK: - 分类图标

struct CategoryBadge: View {
    let category: Category
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(category.color.opacity(0.16))
            Image(systemName: category.icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(category.color)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }
}
