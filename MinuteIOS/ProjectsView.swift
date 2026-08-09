import SwiftData
import SwiftUI

struct ProjectsView: View {
    @Binding var isShowingCapture: Bool

    @Query(sort: \Project.createdAt) private var projects: [Project]

    private var visibleProjects: [Project] {
        projects.filter { $0.status == .active }.sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            if visibleProjects.isEmpty {
                EmptyTaskState(
                    title: "No projects yet",
                    message: "New tasks will start in Inbox until you add a project."
                )
            } else {
                Section("Active projects") {
                    ForEach(visibleProjects) { project in
                        NavigationLink {
                            ProjectTaskListView(project: project)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: project.area?.iconName ?? "folder")
                                    .foregroundStyle(.indigo)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(project.name)
                                        .font(.headline)
                                    Text(project.area?.name ?? "Unsorted")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(project.tasks.filter { !$0.isCompleted }.count)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Projects")
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
}

private struct ProjectTaskListView: View {
    let project: Project

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appModel: MinuteIOSAppModel

    private var activeTasks: [TaskItem] {
        project.tasks
            .filter { !$0.isCompleted }
            .sorted { lhs, rhs in
                (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
            }
    }

    var body: some View {
        List {
            if activeTasks.isEmpty {
                EmptyTaskState(
                    title: "Project is clear",
                    message: "Completed tasks stay out of the way here."
                )
            } else {
                ForEach(activeTasks) { task in
                    IOSTaskRow(task: task, onToggle: { toggle(task) })
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(project.name)
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
            // The model remains the source of truth if the snapshot update fails.
        }
    }
}
