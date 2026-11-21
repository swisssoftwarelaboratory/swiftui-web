import SwiftUI
import WidgetKit

@main
struct WidgetCounterWidgets: WidgetBundle {
    var body: some Widget {
        CountWidget()
    }
}

struct CountEntry: TimelineEntry {
    let date: Date
    let count: Int
}

/// The count as the app last wrote it, with one entry a minute for the next hour.
struct CountProvider: TimelineProvider {
    private var count: Int { UserDefaults(suiteName: "group.widgetcounter")?.integer(forKey: "count") ?? 0 }

    func placeholder(in context: Context) -> CountEntry {
        CountEntry(date: .now, count: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (CountEntry) -> Void) {
        completion(CountEntry(date: .now, count: count))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountEntry>) -> Void) {
        let now = Date.now
        let entries = (0..<60).map { CountEntry(date: now.addingTimeInterval(Double($0) * 60), count: count) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct CountWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CountEntry

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Count")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("\(entry.count)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                Text(entry.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if family != .systemSmall {
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.white, for: .widget)
    }
}

struct CountWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Count", provider: CountProvider()) { entry in
            CountWidgetView(entry: entry)
        }
        .configurationDisplayName("Count")
        .description("The count from the app.")
        .supportedFamilies([.systemMedium, .systemSmall])
    }
}
