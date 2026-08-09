import SwiftData
import SwiftUI

struct TodayView: View {
    @Binding var isShowingCapture: Bool

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appModel: MinuteIOSAppModel
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]

    private var todayTasks: [TaskItem] {
        let calendar = Calendar.current
        let startOfTomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: Date())
        ) ?? Date()

        return tasks
            .filter { task in
                guard !task.isCompleted else { return false }
                guard let dueDate = task.dueDate else { return true }
                return dueDate < startOfTomorrow
            }
            .sorted(by: taskOrdering)
    }

    var body: some View {
        List {
            if todayTasks.isEmpty {
                EmptyTaskState(
                    title: "Nothing due today",
                    message: "Capture a task or enjoy the clear space."
                )
            } else {
                Section("Today") {
                    ForEach(todayTasks) { task in
                        IOSTaskRow(task: task, onToggle: { toggle(task) })
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Today")
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
            // SwiftData will keep the current row state; the next refresh retries the snapshot.
        }
    }

    private func taskOrdering(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        let lhsDueDate = lhs.dueDate ?? .distantFuture
        let rhsDueDate = rhs.dueDate ?? .distantFuture
        if lhsDueDate != rhsDueDate {
            return lhsDueDate < rhsDueDate
        }
        return lhs.createdAt < rhs.createdAt
    }
}
