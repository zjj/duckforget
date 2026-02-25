import SwiftUI

// MARK: - ThemeColors

/// 主题语义颜色集合，所有视图通过这组 token 引用颜色，永不硬编码系统色
struct ThemeColors {
    /// 页面底色（ScrollView/List 底面）
    let background: Color
    /// 导航栏 / 工具栏底色
    let surface: Color
    /// 卡片 / Widget 底色
    let card: Color
    /// 次级卡片底色（嵌套卡片、副信息区域）
    let cardSecondary: Color
    /// 强调色（图标高亮、按钮、链接）
    let accent: Color
    /// 强调色低透明叠加（chip 背景、选中态等）
    var accentSoft: Color { accent.opacity(0.15) }
    /// 主文字色
    let primaryText: Color
    /// 次要文字色
    let secondaryText: Color
    /// 三级文字色（时间戳等）
    var tertiaryText: Color { secondaryText.opacity(0.6) }
    /// 分割线 / 边框
    let border: Color
    /// 阴影叠加色
    let shadow: Color
    /// Markdown 语法关键字（标题前缀 #、** 等）
    let syntaxKeyword: Color
    /// 行内代码高亮
    let syntaxCode: Color
    /// 是否为深色主题（影响 UIKit 层颜色传递）
    let isDark: Bool
}

// MARK: - AppTheme

enum AppTheme: String, CaseIterable, Identifiable {
    case system     = "system"
    case warmSun    = "warmSun"
    case sakura     = "sakura"
    case oceanMist  = "oceanMist"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:    return "跟随系统"
        case .warmSun:   return "暖阳"
        case .sakura:    return "樱花"
        case .oceanMist: return "海雾"
        }
    }

    var description: String {
        switch self {
        case .system:    return "跟随 iOS 深色/浅色模式"
        case .warmSun:   return "奶油橙黄，激发灵感"
        case .sakura:    return "浅粉玫瑰，柔和浪漫"
        case .oceanMist: return "蓝灰薄雾，清爽宁静"
        }
    }

    var symbolName: String {
        switch self {
        case .system:    return "circle.lefthalf.filled"
        case .warmSun:   return "sun.max.fill"
        case .sakura:    return "sparkles"
        case .oceanMist: return "cloud.fill"
        }
    }

    var colors: ThemeColors {
        switch self {

        // ── 跟随系统：透传 UIKit / SwiftUI 系统语义色 ──────────────────────
        case .system:
            return ThemeColors(
                background:    Color(.systemBackground),
                surface:       Color(.systemBackground),
                card:          Color(.systemGray6),
                cardSecondary: Color(.secondarySystemBackground),
                accent:        Color.accentColor,
                primaryText:   Color.primary,
                secondaryText: Color.secondary,
                border:        Color(.systemGray4),
                shadow:        Color.black.opacity(0.06),
                syntaxKeyword: Color(.systemOrange),
                syntaxCode:    Color(.systemOrange).opacity(0.7),
                isDark:        false
            )

        // ── 暖阳：奶油橙黄 + 橘强调 ─────────────────────────────────────
        case .warmSun:
            return ThemeColors(
                background:    Color(hex: "FFF8ED"),
                surface:       Color(hex: "FFFBF3"),
                card:          Color(hex: "FFF3D6"),
                cardSecondary: Color(hex: "FFEAD0"),
                accent:        Color(hex: "E07A20"),
                primaryText:   Color(hex: "2D1F0E"),
                secondaryText: Color(hex: "7A5C3A"),
                border:        Color(hex: "EDD9B0"),
                shadow:        Color(hex: "B85C00").opacity(0.10),
                syntaxKeyword: Color(hex: "E07A20"),
                syntaxCode:    Color(hex: "C0733E"),
                isDark:        false
            )

        // ── 樱花：浅粉玫瑰 + 玫红强调 ───────────────────────────────────
        case .sakura:
            return ThemeColors(
                background:    Color(hex: "FFF0F3"),
                surface:       Color(hex: "FFF5F7"),
                card:          Color(hex: "FFE4EC"),
                cardSecondary: Color(hex: "FFD6E7"),
                accent:        Color(hex: "D64F7A"),
                primaryText:   Color(hex: "2D0F1A"),
                secondaryText: Color(hex: "8B4F6A"),
                border:        Color(hex: "F0C0D0"),
                shadow:        Color(hex: "D64F7A").opacity(0.08),
                syntaxKeyword: Color(hex: "D64F7A"),
                syntaxCode:    Color(hex: "E87AA0"),
                isDark:        false
            )

        // ── 海雾：蓝灰薄雾 + 深蓝强调 ───────────────────────────────────
        case .oceanMist:
            return ThemeColors(
                background:    Color(hex: "EDF2F7"),
                surface:       Color(hex: "F7FAFC"),
                card:          Color(hex: "DDEAF5"),
                cardSecondary: Color(hex: "C9DDEF"),
                accent:        Color(hex: "2B6CB0"),
                primaryText:   Color(hex: "1A2A3A"),
                secondaryText: Color(hex: "4A6A8A"),
                border:        Color(hex: "B0C8E0"),
                shadow:        Color(hex: "2B6CB0").opacity(0.08),
                syntaxKeyword: Color(hex: "2B6CB0"),
                syntaxCode:    Color(hex: "4A90C4"),
                isDark:        false
            )
        }
    }
}

// MARK: - Color Hex Init

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red:   Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
