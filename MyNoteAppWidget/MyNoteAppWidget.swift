import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = SimpleEntry(date: Date())
        // 生成一个永不过期的时间线（因为是静态按钮）
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct MyNoteAppWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        // Link wraps the entire content to make it tappable
        Link(destination: URL(string: "mynoteapp://create-note")!) {
            ZStack {
                ContainerRelativeShape()
                    .fill(Color(UIColor.systemBackground)) // 使用系统背景色
                
                // 主要内容：SF Symbol
                VStack {
                    // 使用 note.text.badge.plus 作为接近 "text.pad.header.badge.plus" 的图标
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 50, weight: .light))
                        .foregroundColor(.accentColor)
                    
                    Text("快速记录")
                        .font(.caption)
                        .foregroundColor(.secondary)
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

@main
struct MyNoteAppWidget: Widget {
    let kind: String = "MyNoteAppWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                MyNoteAppWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                MyNoteAppWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("快速记录")
        .description("一键创建新记录。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

