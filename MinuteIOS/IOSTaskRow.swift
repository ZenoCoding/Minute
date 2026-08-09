import SwiftUI

struct IOSTaskRow: View {
    let task: TaskItem
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                HStack(spacing: 6) {
                    if let projectName = task.project?.name {
                        Label(projectName, systemImage: "folder")
                    }
                    if let dueDate = task.dueDate {
                        Label(
                            dueDate.formatted(date: .abbreviated, time: .omitted),
                            systemImage: "calendar"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct EmptyTaskState: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "checkmark.circle")
        } description: {
            Text(message)
        }
        .listRowBackground(Color.clear)
    }
}
