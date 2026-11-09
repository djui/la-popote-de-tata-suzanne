import SwiftUI
import WidgetKit

@main
struct PopoteWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayMenuWidget()
    }
}

struct TodayMenuWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayMenu", provider: Provider()) { entry in
            Text(entry.date, style: .time).containerBackground(.fill, for: .widget)
        }
        .configurationDisplayName("Menu du jour")
    }

    struct Entry: TimelineEntry { let date: Date }
    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: .now) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(date: .now)], policy: .atEnd))
        }
    }
}
