import Foundation

enum MinuteWidgetSnapshotBuilder {
    static func makeSnapshot(
        from tasks: [TaskItem],
        now: Date = Date(),
        maximumTaskCount: Int = 8
    ) -> MinuteWidgetSnapshot {
        let actionableTasks = tasks
            .filter { !$0.isCompleted }
            .sorted { lhs, rhs in
                let lhsDueDate = lhs.dueDate ?? .distantFuture
                let rhsDueDate = rhs.dueDate ?? .distantFuture
                if lhsDueDate != rhsDueDate {
                    return lhsDueDate < rhsDueDate
                }
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.createdAt < rhs.createdAt
            }
            .prefix(max(0, maximumTaskCount))

        return MinuteWidgetSnapshot(
            generatedAt: now,
            tasks: actionableTasks.map { task in
                MinuteWidgetTask(
                    id: task.id,
                    title: task.title,
                    projectName: task.project?.name,
                    dueDate: task.dueDate,
                    isOverdue: task.dueDate.map { $0 < now } ?? false
                )
            }
        )
    }
}
