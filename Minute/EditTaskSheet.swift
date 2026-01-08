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
    
    // Local state for editing to support "Cancel"
    @State private var title: String
    @State private var selectedProject: Project?
    @State private var dueDate: Date?
    @State private var estimatedDuration: TimeInterval?
    
    // UI States
    @State private var showDatePicker = false
    @State private var customDurationText: String = ""
    
    init(task: TaskItem) {
        self.task = task
        _title = State(initialValue: task.title)
        _selectedProject = State(initialValue: task.project)
        _dueDate = State(initialValue: task.dueDate)
        _estimatedDuration = State(initialValue: task.estimatedDuration)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Edit Task")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.top)
            
            // Title
            VStack(alignment: .leading, spacing: 8) {
                Text("Task Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("Task Name", text: $title)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
            
            // Project
            VStack(alignment: .leading, spacing: 8) {
                Text("Project")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
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
                    HStack {
                        if let project = selectedProject {
                            if let icon = project.area?.iconName {
                                Image(systemName: icon)
                                    .foregroundStyle(Color(hex: project.area?.themeColor ?? "") ?? .secondary)
                            }
                            Text(project.name)
                        } else {
                            Text("Select Project")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }
                .menuStyle(.borderlessButton)
            }
            
            HStack(spacing: 20) {
                // Due Date
                VStack(alignment: .leading, spacing: 8) {
                    Text("Due Date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        showDatePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(.secondary)
                            if let date = dueDate {
                                Text(formatDate(date))
                            } else {
                                Text("No Date")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                        VStack(spacing: 12) {
                            HStack {
                                Button("Today") { dueDate = Date(); showDatePicker = false }
                                Button("Tomorrow") { dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()); showDatePicker = false }
                                Button("Clear") { dueDate = nil; showDatePicker = false }.foregroundStyle(.red)
                            }
                            .controlSize(.small)
                            
                            Divider()
                            
                            CustomDatePicker(selection: $dueDate)
                        }
                        .padding()
                        .frame(width: 280)
                    }
                }
                
                // Duration
                VStack(alignment: .leading, spacing: 8) {
                    Text("Est. Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Menu {
                        Button("None") { estimatedDuration = nil }
                        Button("15m") { estimatedDuration = 900 }
                        Button("30m") { estimatedDuration = 1800 }
                        Button("45m") { estimatedDuration = 2700 }
                        Button("1h") { estimatedDuration = 3600 }
                        Button("2h") { estimatedDuration = 7200 }
                    } label: {
                        HStack {
                            Image(systemName: "hourglass")
                                .foregroundStyle(.secondary)
                            
                            if let duration = estimatedDuration {
                                Text(formatDuration(duration))
                            } else {
                                Text("None")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .menuStyle(.borderlessButton)
                }
                
                // Recurrence
                VStack(alignment: .leading, spacing: 8) {
                    Text("Repeat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Menu {
                        Button("Never") { task.isRecurring = false; task.recurrenceInterval = nil }
                        Button("Daily") { task.isRecurring = true; task.recurrenceInterval = "daily" }
                        Button("Weekly") { task.isRecurring = true; task.recurrenceInterval = "weekly" }
                    } label: {
                        HStack {
                            Image(systemName: "repeat")
                                .foregroundStyle(task.isRecurring ? .blue : .secondary)
                            
                            if task.isRecurring {
                                Text(task.recurrenceInterval?.capitalized ?? "Recurring")
                                    .foregroundStyle(.blue)
                            } else {
                                Text("Never")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                
                Button("Save Changes") {
                    saveChanges()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                .disabled(title.isEmpty || selectedProject == nil)
            }
        }
        .padding(24)
        .frame(width: 400, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func saveChanges() {
        task.title = title
        task.project = selectedProject
        task.dueDate = dueDate
        task.estimatedDuration = estimatedDuration
        // SwiftData autosaves on change, but if we wanted explicit save:
        // try? modelContext.save()
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
