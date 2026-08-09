import SwiftData
import SwiftUI

struct QuickCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appModel: MinuteIOSAppModel
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var title = ""
    @State private var selectedProjectID: UUID?
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var errorMessage: String?
    @FocusState private var isTitleFocused: Bool

    private var activeProjects: [Project] {
        projects.filter { $0.status == .active }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What needs doing?", text: $title, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($isTitleFocused)

                    Picker("Project", selection: $selectedProjectID) {
                        Text("Inbox").tag(UUID?.none)
                        ForEach(activeProjects) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                }

                Section {
                    Toggle("Add a due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addTask() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Could not add task", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Try again.")
            }
            .onAppear {
                isTitleFocused = true
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented { errorMessage = nil }
            }
        )
    }

    private func addTask() {
        let selectedProject = activeProjects.first { $0.id == selectedProjectID }
        do {
            let service = MinuteDataService(modelContext: modelContext)
            _ = try service.createTask(
                title: title,
                project: selectedProject,
                dueDate: hasDueDate ? dueDate : nil
            )
            try service.save()
            appModel.refreshWidgetSnapshot()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
