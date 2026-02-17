import WidgetKit
import SwiftUI
import AppIntents

/// 快速记账 Widget
struct QuickEntryWidget: Widget {
    let kind: String = "QuickEntryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickEntryProvider()) { entry in
            QuickEntryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("快速记账")
        .description("一键打开 FlashCount 记账")
        .supportedFamilies([
            .accessoryCircular,   // 锁屏圆形
            .accessoryRectangular, // 锁屏矩形
            .systemSmall          // 桌面小组件
        ])
    }
}

// MARK: - Timeline

struct QuickEntryProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickEntryTimelineEntry {
        QuickEntryTimelineEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickEntryTimelineEntry) -> Void) {
        completion(QuickEntryTimelineEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntryTimelineEntry>) -> Void) {
        let entry = QuickEntryTimelineEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct QuickEntryTimelineEntry: TimelineEntry {
    let date: Date
}

// MARK: - Widget Views

struct QuickEntryWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: QuickEntryTimelineEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            lockScreenCircular
        case .accessoryRectangular:
            lockScreenRectangular
        case .systemSmall:
            homeScreenSmall
        default:
            homeScreenSmall
        }
    }

    // 锁屏 - 圆形 Widget
    private var lockScreenCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "plus.circle.fill")
                .font(.title)
                .foregroundStyle(.white)
        }
    }

    // 锁屏 - 矩形 Widget
    private var lockScreenRectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.title2)
            VStack(alignment: .leading) {
                Text("FlashCount")
                    .font(.headline)
                Text("点击快速记账")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // 桌面 - 小组件
    private var homeScreenSmall: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.4, green: 0.49, blue: 0.92),
                                 Color(red: 0.46, green: 0.29, blue: 0.64)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )

            Text("记一笔")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("点击快速记账")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Widget Bundle

@main
struct FlashCountWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickEntryWidget()
    }
}
