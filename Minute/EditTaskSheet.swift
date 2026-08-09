//
//  EditTaskSheet.swift
//  Minute
//
//  Created by Tycho Young on 1/6/26.
//

import SwiftUI
import SwiftData

struct EditTaskSheet: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Project.createdAt) private var allProjects: [Project]
    var activeProjects: [Project] {
        allProjects.filter { $0.status == .active }
    }

    private struct ChecklistDraftRow: Identifiable, Equatable {
        let id: UUID
        var title: String
        var isCompleted: Bool
    }

    // Keep every editable value local until Save succeeds.
    @State private var title: String
    @State private var selectedProject: Project?
    @State private var dueDate: Date?
    @State private var estimatedDuration: TimeInterval?
    @State private var isRecurring: Bool
    @State private var recurrenceInterval: String?
    @State private var notes: String
    @State private var checklistRows: [ChecklistDraftRow]
    @State private var newChecklistTitle = ""
    @State private var isNotesExpanded: Bool
    @State private var isChecklistExpanded: Bool

    // UI state
    @State private var showDatePicker = false
    @State private var saveError: String?
    @State private var isSaving = false

    init(task: TaskItem) {
        self.task = task
        _title = State(initialValue: task.title)
        _selectedProject = State(initialValue: task.project)
        _dueDate = State(initialValue: task.dueDate)
        _estimatedDuration = State(initialValue: task.estimatedDuration)
        _isRecurring = State(initialValue: task.isRecurring)
        _recurrenceInterval = State(initialValue: task.recurrenceInterval)
        _notes = State(initialValue: task.notes ?? "")
        _checklistRows = State(initialValue: task.checklist.map {
            ChecklistDraftRow(id: $0.id, title: $0.title, isCompleted: $0.isCompleted)
        })
        _isNotesExpanded = State(initialValue: !(task.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
        _isChecklistExpanded = State(initialValue: !task.checklist.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Task")
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    compactTaskDetails
                    Divider()
                        .opacity(0.45)
                    notesSection
                    checklistSection
                }
                .padding(.horizontal, 1)
                .padding(.bottom, 8)
            }

            Divider()
                .padding(.top, 8)

            if let saveError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(saveError)
                        .multilineTextAlignment(.leading)
                }
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Save failed: \(saveError)")
            }

            HStack(spacing: 10) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Save Changes") {
                    saveChanges()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!canSave)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 10)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(width: 520, height: editorHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var editorHeight: CGFloat {
        let collapsedHeight: CGFloat = 340
        let contentBaseHeight: CGFloat = 326
        let notesHeight: CGFloat = isNotesExpanded ? 112 : 0
        let checklistHeight: CGFloat = isChecklistExpanded
            ? (checklistRows.isEmpty ? 48 : min(CGFloat(checklistRows.count * 34 + 42), 180))
            : 0
        return min(max(collapsedHeight, contentBaseHeight + notesHeight + checklistHeight), 620)
    }

    private var compactTaskDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Task name", text: $title)
                .textFieldStyle(.plain)
                .font(.title3.weight(.medium))
                .padding(.bottom, 7)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.28))
                        .frame(height: 1)
                }
                .accessibilityLabel("Task name")

            Menu {
                ForEach(activeProjects) { project in
                    Button {
                        selectedProject = project
                    } label: {
                        HStack {
                            if let icon = project.area?.iconName {
                                Image(systemName: icon)
                            }
                            Text(project.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: selectedProject?.area?.themeColor ?? "") ?? .secondary)
                        .frame(width: 7, height: 7)
                    Text(selectedProject?.name ?? "Select Project")
                        .foregroundStyle(selectedProject == nil ? .secondary : .primary)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Project")
            .accessibilityValue(selectedProject?.name ?? "Select Project")

            HStack(spacing: 0) {
                detailPicker(title: "Due") {
                    Button {
                        showDatePicker = true
                    } label: {
                        HStack {
                            if let dueDate {
                                Text(formatDate(dueDate))
                            } else {
                                Text("None")
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                        VStack(spacing: 12) {
                            HStack {
                                Button("Today") {
                                    dueDate = DueDateSupport.presetToday()
                                    showDatePicker = false
                                }
                                Button("Tomorrow") {
                                    dueDate = DueDateSupport.presetTomorrow()
                                    showDatePicker = false
                                }
                                Button("Clear") {
                                    dueDate = nil
                                    showDatePicker = false
                                }
                                .foregroundStyle(.red)
                            }
                            .controlSize(.small)

                            Divider()
                            CustomDatePicker(selection: $dueDate)
                        }
                        .padding()
                        .frame(width: 280)
                    }
                }

                Divider()
                    .frame(height: 30)
                    .padding(.horizontal, 12)
                    .opacity(0.45)

                detailPicker(title: "Duration") {
                    Menu {
                        Button("None") { estimatedDuration = nil }
                        Button("15m") { estimatedDuration = 900 }
                        Button("30m") { estimatedDuration = 1800 }
                        Button("45m") { estimatedDuration = 2700 }
                        Button("1h") { estimatedDuration = 3600 }
                        Button("2h") { estimatedDuration = 7200 }
                    } label: {
                        HStack {
                            Text(estimatedDuration.map(formatDuration) ?? "None")
                                .foregroundStyle(estimatedDuration == nil ? .secondary : .primary)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                }

                Divider()
                    .frame(height: 30)
                    .padding(.horizontal, 12)
                    .opacity(0.45)

                detailPicker(title: "Repeat") {
                    Menu {
                        Button("Never") {
                            isRecurring = false
                            recurrenceInterval = nil
                        }
                        Button("Daily") {
                            isRecurring = true
                            recurrenceInterval = "daily"
                        }
                        Button("Weekly") {
                            isRecurring = true
                            recurrenceInterval = "weekly"
                        }
                    } label: {
                        HStack {
                            Text(recurrenceLabel)
                                .foregroundStyle(isRecurring ? .blue : .secondary)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
    }

    private func detailPicker<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            content()
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notesSection: some View {
        DisclosureGroup(isExpanded: $isNotesExpanded) {
            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Add a note…")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $notes)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(3)
            }
            .frame(height: 82)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
            .padding(.top, 8)
        } label: {
            Text("Notes")
                .font(.callout.weight(.medium))
        }
        .tint(.secondary)
    }

    private var checklistSection: some View {
        DisclosureGroup(isExpanded: $isChecklistExpanded) {
            HStack(spacing: 6) {
                TextField("Add checklist item", text: $newChecklistTitle)
                    .textFieldStyle(.plain)
                    .onSubmit(addChecklistItem)
                Button(action: addChecklistItem) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Add checklist item")
                .accessibilityLabel("Add checklist item")
                .disabled(newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
            }
            .padding(.top, 6)

            if checklistRows.isEmpty {
                EmptyView()
            } else {
                VStack(spacing: 0) {
                    ForEach($checklistRows) { $row in
                        checklistRow($row)
                    }
                }
                .padding(.top, 4)
                .accessibilityLabel("Checklist items")
            }
        } label: {
            HStack(spacing: 6) {
                Text("Checklist")
                    .font(.callout.weight(.medium))
                if !checklistRows.isEmpty {
                    Text("\(checklistRows.filter(\.isCompleted).count)/\(checklistRows.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(.secondary)
    }

    @ViewBuilder
    private func checklistRow(_ row: Binding<ChecklistDraftRow>) -> some View {
        HStack(spacing: 8) {
            Button {
                row.wrappedValue.isCompleted.toggle()
            } label: {
                Image(systemName: row.wrappedValue.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(row.wrappedValue.isCompleted ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(row.wrappedValue.isCompleted ? "Mark incomplete" : "Mark complete")
            .accessibilityLabel(row.wrappedValue.isCompleted ? "Mark incomplete" : "Mark complete")

            TextField("Checklist item", text: row.title)
                .textFieldStyle(.plain)
                .strikethrough(row.wrappedValue.isCompleted)
                .accessibilityLabel("Checklist item")

            Menu {
                let index = checklistRows.firstIndex { $0.id == row.wrappedValue.id } ?? 0
                Button("Move Up") {
                    moveChecklistItem(id: row.wrappedValue.id, by: -1)
                }
                .disabled(index == 0)
                Button("Move Down") {
                    moveChecklistItem(id: row.wrappedValue.id, by: 1)
                }
                .disabled(index == checklistRows.count - 1)
                Divider()
                Button("Remove", role: .destructive) {
                    removeChecklistItem(id: row.wrappedValue.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Checklist item actions")
            .accessibilityLabel("Checklist item actions")
        }
        .padding(.vertical, 4)
    }

    private var recurrenceLabel: String {
        guard isRecurring else { return "Never" }
        return recurrenceInterval?.capitalized ?? "Recurring"
    }

    private var canSave: Bool {
        !isSaving &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedProject != nil
    }

    private func addChecklistItem() {
        let cleanTitle = newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        checklistRows.append(ChecklistDraftRow(id: UUID(), title: cleanTitle, isCompleted: false))
        newChecklistTitle = ""
    }

    private func removeChecklistItem(id: UUID) {
        checklistRows.removeAll { $0.id == id }
    }

    private func moveChecklistItem(id: UUID, by offset: Int) {
        guard let index = checklistRows.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard checklistRows.indices.contains(destination) else { return }
        checklistRows.swapAt(index, destination)
    }

    private func saveChanges() {
        guard canSave else { return }

        isSaving = true
        saveError = nil

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousProjectID = task.project?.id
        let checklistDrafts = checklistRows.compactMap { row -> TaskChecklistDraft? in
            let cleanChecklistTitle = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanChecklistTitle.isEmpty else { return nil }
            return TaskChecklistDraft(title: cleanChecklistTitle, isCompleted: row.isCompleted)
        }

        do {
            let service = MinuteDataService(modelContext: modelContext)
            try service.updateTask(
                task,
                title: cleanTitle,
                projectName: selectedProject?.name,
                dueDate: dueDate,
                clearDueDate: dueDate == nil,
                estimatedDuration: estimatedDuration,
                clearDuration: estimatedDuration == nil,
                recurrenceInterval: isRecurring ? recurrenceInterval : nil,
                clearRecurrence: !isRecurring || recurrenceInterval == nil,
                notes: cleanNotes.isEmpty ? nil : cleanNotes,
                clearNotes: cleanNotes.isEmpty,
                checklist: checklistDrafts
            )
            try service.save()

            if previousProjectID != selectedProject?.id, let selectedProject {
                ProjectInferenceMemory.record(text: cleanTitle, projectName: selectedProject.name)
            }

            dismiss()
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
            isSaving = false
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}
