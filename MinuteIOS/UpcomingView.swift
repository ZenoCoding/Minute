import SwiftData
import SwiftUI

struct UpcomingView: View {
    @Binding var isShowingCapture: Bool

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appModel: MinuteIOSAppModel
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]

    private var upcomingTasks: [TaskItem] {
        let startOfTomorrow = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()

        return tasks
            .filter { !$0.isCompleted && ($0.dueDate ?? .distantPast) >= startOfTomorrow }
            .sorted { lhs, rhs in
                (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
            }
    }

    var body: some View {
        List {
            if upcomingTasks.isEmpty {
                EmptyTaskState(
                    title: "No upcoming tasks",
                    message: "Tasks with a future due date will appear here."
                )
            } else {
                Section("Next up") {
                    ForEach(upcomingTasks) { task in
                        IOSTaskRow(task: task, onToggle: { toggle(task) })
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Upcoming")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingCapture = true
                } label: {
                    Label("New task", systemImage: "plus")
                }
            }
        }
    }

    private func toggle(_ task: TaskItem) {
        do {
            try MinuteDataService(modelContext: modelContext).updateTask(
                task,
                completed: !task.isCompleted
            )
            try MinuteDataService(modelContext: modelContext).save()
            appModel.refreshWidgetSnapshot()
        } catch {
            // Keep the interaction lightweight; a future store refresh can retry the snapshot.
        }
    }
}
