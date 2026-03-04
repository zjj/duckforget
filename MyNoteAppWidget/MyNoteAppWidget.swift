import WidgetKit
import SwiftUI

// MARK: - Shared constants (mirror of SharedDefaults.swift in main target)

private let appGroupSuite  = "group.com.duckforget.MyNoteApp"
private let appThemeKey    = "AppTheme"

// MARK: - Minimal theme color resolver (widget-local, no dependency on main target)

private struct WidgetThemeColors {
    let accent:     Color
    let background: Color
    let card:       Color
    let primaryText: Color
}

private func resolveTheme(rawValue: String?) -> WidgetThemeColors {
    switch rawValue ?? "" {
    case "midnight":
        return WidgetThemeColors(
            accent:      Color(hex: "818CF8"),
            background:  Color(hex: "111827"),
            card:        Color(hex: "252D3D"),
            primaryText: Color(hex: "F1F5F9")
        )
    case "warmSun":
        return WidgetThemeColors(
            accent:      Color(hex: "E07A20"),
            background:  Color(hex: "FFF8ED"),
            card:        Color(hex: "FFF3D6"),
            primaryText: Color(hex: "2D1F0E")
        )
    case "sakura":
        return WidgetThemeColors(
            accent:      Color(hex: "D64F7A"),
            background:  Color(hex: "FFF0F3"),
            card:        Color(hex: "FFE4EC"),
            primaryText: Color(hex: "2D0F1A")
        )
    case "oceanMist":
        return WidgetThemeColors(
            accent:      Color(hex: "2B6CB0"),
            background:  Color(hex: "EDF2F7"),
            card:        Color(hex: "DDEAF5"),
            primaryText: Color(hex: "1A2A3A")
        )
    default: // "system" 或未知值
        return WidgetThemeColors(
            accent:      Color.accentColor,
            background:  Color(UIColor.systemBackground),
            card:        Color(UIColor.secondarySystemBackground),
            primaryText: Color.primary
        )
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - Timeline Entry

struct SimpleEntry: TimelineEntry {
    let date: Date
    let themeRawValue: String?
}

// MARK: - Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), themeRawValue: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        completion(SimpleEntry(date: Date(), themeRawValue: readTheme()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = SimpleEntry(date: Date(), themeRawValue: readTheme())
        // 无需定时刷新；主 App 在主题变更时会调用 WidgetCenter.reloadAllTimelines()
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func readTheme() -> String? {
        UserDefaults(suiteName: appGroupSuite)?.string(forKey: appThemeKey)
    }
}

// MARK: - Widget View

struct MyNoteAppWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    private var theme: WidgetThemeColors { resolveTheme(rawValue: entry.themeRawValue) }

    var body: some View {
        Link(destination: URL(string: "mynoteapp://create-note")!) {
            ZStack {
                VStack {
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 50, weight: .light))
                        .foregroundColor(theme.accent)

                    Text("快速记录")
                        .font(.caption)
                        .foregroundColor(theme.primaryText.opacity(0.6))
                }

                // 右下角 Logo
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .opacity(0.8)
                    }
                }
                .padding(12)
            }
        }
    }
}

// MARK: - Widget Configuration

struct MyNoteAppWidget: Widget {
    let kind: String = "MyNoteAppWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            let bg = resolveTheme(rawValue: entry.themeRawValue).background
            if #available(iOS 17.0, *) {
                MyNoteAppWidgetEntryView(entry: entry)
                    .containerBackground(bg, for: .widget)
            } else {
                MyNoteAppWidgetEntryView(entry: entry)
                    .padding()
                    .background(bg)
            }
        }
        .configurationDisplayName("快速记录")
        .description("一键创建新记录。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
