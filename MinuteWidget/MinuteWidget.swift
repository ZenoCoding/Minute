import SwiftUI
import WidgetKit

struct MinuteWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: MinuteWidgetSnapshot
}

struct MinuteWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MinuteWidgetEntry {
        MinuteWidgetEntry(date: MinuteWidgetSampleData.referenceDate, snapshot: MinuteWidgetSampleData.snapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (MinuteWidgetEntry) -> Void) {
        let snapshot = MinuteWidgetSnapshotStore().read() ?? MinuteWidgetSampleData.snapshot
        completion(MinuteWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MinuteWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = MinuteWidgetSnapshotStore().read() ?? MinuteWidgetSampleData.snapshot
        let entry = MinuteWidgetEntry(date: now, snapshot: snapshot)
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: now)
            ?? now.addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct MinuteWidgetEntryView: View {
    @Environment(\.widgetFamily) private var widgetFamily

    let entry: MinuteWidgetEntry

    private var visibleTasks: ArraySlice<MinuteWidgetTask> {
        let count = widgetFamily == .systemSmall ? 3 : 5
        return entry.snapshot.tasks.prefix(count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.indigo)
                Text("Minute")
                    .font(.headline)
                Spacer()
                Text("Next")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if visibleTasks.isEmpty {
                Spacer(minLength: 0)
                Text("All clear")
                    .font(.subheadline.weight(.medium))
                Text("Add a task from Minute.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(visibleTasks) { task in
                    Link(destination: URL(string: "minute://task/\(task.id.uuidString)")!) {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "circle")
                                .font(.caption)
                                .foregroundStyle(task.isOverdue ? .orange : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(widgetFamily == .systemSmall ? 2 : 1)
                                if let projectName = task.projectName {
                                    Text(projectName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(4)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "minute://today"))
    }
}

struct MinuteWidget: Widget {
    let kind = "MinuteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MinuteWidgetProvider()) { entry in
            MinuteWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next tasks")
        .description("See the next actionable tasks from Minute.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct MinuteWidgetBundle: WidgetBundle {
    var body: some Widget {
        MinuteWidget()
    }
}

#Preview("Small", as: .systemSmall) {
    MinuteWidget()
} timeline: {
    MinuteWidgetEntry(
        date: MinuteWidgetSampleData.referenceDate,
        snapshot: MinuteWidgetSampleData.snapshot
    )
}

#Preview("Medium", as: .systemMedium) {
    MinuteWidget()
} timeline: {
    MinuteWidgetEntry(
        date: MinuteWidgetSampleData.referenceDate,
        snapshot: MinuteWidgetSampleData.snapshot
    )
}
