//
//  CaptureView.swift
//  Minute
//
//  Full-screen "Welcome Home" capture mode for rapid task brain dump.
//

import SwiftUI
import SwiftData

struct FullScreenCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    
    @Query(sort: \Project.createdAt)
    private var allProjects: [Project]
    
    private var activeProjects: [Project] {
        allProjects.filter { $0.status == .active }
    }
    
    // Input state
    @State private var text: String = ""
    @State private var detectedProject: Project?
    @State private var detectedDuration: TimeInterval?
    @State private var detectedDate: Date?
    @State private var detectedRecurrence: String?
    
    // Manual overrides
    @State private var selectedProject: Project?
    @State private var selectedDate: Date?
    @State private var selectedDuration: TimeInterval?
    @State private var selectedRecurrence: String?
    @State private var parseTask: Task<Void, Never>?
    
    // Pickers
    @State private var showDatePicker = false
    @State private var showProjectPicker = false
    @State private var showDurationPicker = false
    @State private var customDurationText: String = ""
    
    // Added tasks
    @State private var addedTasks: [AddedTask] = []
    
    @FocusState private var isInputFocused: Bool
    
    struct AddedTask: Identifiable {
        let id = UUID()
        let title: String
        let projectName: String?
    }
    
    // Effective Values
    var effectiveProject: Project? {
        selectedProject ?? detectedProject ?? activeProjects.first
    }
    
    var effectiveDuration: TimeInterval? {
        selectedDuration ?? detectedDuration
    }
    
    var effectiveRecurrence: String? {
        selectedRecurrence ?? detectedRecurrence
    }
    
    var effectiveDate: Date? {
        selectedDate ?? detectedDate
    }

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()
    
    var body: some View {
        ZStack {
            // Dark background
            Color(.windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Spacer()
                    
                    Button {
                        isPresented = false
                    } label: {
                        Text("Done")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.accentColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(20)
                
                Spacer()
                
                // Center content
                VStack(spacing: 32) {
                    // Welcome message
                    VStack(spacing: 8) {
                        Text("Welcome Back")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text("What's on your mind?")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Large composer
                    VStack(spacing: 12) {
                        // Input field
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            
                            TextField("Add a task...", text: $text)
                                .textFieldStyle(.plain)
                                .font(.title3)
                                .focused($isInputFocused)
                                .onSubmit {
                                    createTask()
                                }
                                .onChange(of: text) { _, newValue in
                                    parseTask?.cancel()
                                    if newValue.isEmpty {
                                        resetComposer()
                                    } else {
                                        let inputSnapshot = newValue
                                        let projectNames = activeProjects.map(\.name)
                                        parseTask = Task {
                                            try? await Task.sleep(for: .milliseconds(120))
                                            guard !Task.isCancelled else { return }

                                            let result = await Task.detached(priority: .userInitiated) {
                                                SmartInputParser.parseForComposer(text: inputSnapshot, projectNames: projectNames)
                                            }.value
                                            guard !Task.isCancelled else { return }

                                            await MainActor.run {
                                                guard text == inputSnapshot else { return }
                                                detectedProject = result.projectName.flatMap { matchedName in
                                                    activeProjects.first {
                                                        $0.name.caseInsensitiveCompare(matchedName) == .orderedSame
                                                    }
                                                }
                                                detectedDuration = result.duration
                                                detectedDate = result.date
                                                detectedRecurrence = result.recurrenceInterval
                                            }
                                        }
                                    }
                                }
                        }
                        .padding(16)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(isInputFocused ? 0.2 : 0.1), lineWidth: 1)
                                )
                        }
                        
                        // Metadata bar
                        if !text.isEmpty {
                            metadataBar
                        }
                    }
                    .frame(maxWidth: 500)
                    
                    // Added tasks list
                    if !addedTasks.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(addedTasks) { task in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(task.title)
                                        .font(.subheadline)
                                    if let project = task.projectName {
                                        Text("• \(project)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .frame(maxWidth: 500)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Hint
                Text("Type a task and press Enter • ESC to close")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 30)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
        .onDisappear {
            parseTask?.cancel()
        }
    }
    
    // MARK: - Metadata Bar
    
    var metadataBar: some View {
        HStack(spacing: 8) {
            // Project
            Button { showProjectPicker = true } label: {
                HStack(spacing: 4) {
                    if let icon = effectiveProject?.area?.iconName {
                        Image(systemName: icon)
                    } else {
                        Image(systemName: "folder")
                    }
                    if let project = effectiveProject {
                        Text(project.name)
                    }
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.2), in: Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showProjectPicker, arrowEdge: .bottom) {
                projectPicker
            }
            
            // Date
            Button { showDatePicker = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(effectiveDate.map { formatDate($0) } ?? "Today")
                }
                .font(.caption)
                .foregroundStyle(effectiveDate.map { isToday($0) ? Color.green : Color.primary } ?? Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.2), in: Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                datePicker
            }
            
            // Duration
            if let duration = effectiveDuration {
                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                    Text(formatDuration(duration))
                }
                .font(.caption)
                .foregroundStyle(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.2), in: Capsule())
            }
            
            // Recurrence
            if let recurrence = effectiveRecurrence {
                HStack(spacing: 4) {
                    Image(systemName: "repeat")
                    Text(recurrence.capitalized)
                }
                .font(.caption)
                .foregroundStyle(.purple)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.2), in: Capsule())
            }
            
            Spacer()
        }
    }
    
    // MARK: - Pickers
    
    var projectPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(activeProjects) { project in
                    Button {
                        selectedProject = project
                        showProjectPicker = false
                    } label: {
                        HStack {
                            if let icon = project.area?.iconName {
                                Image(systemName: icon)
                                    .foregroundStyle(Color(hex: project.area?.themeColor ?? "") ?? .secondary)
                            }
                            Text(project.name)
                            Spacer()
                            if effectiveProject?.id == project.id {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .frame(width: 200, height: 200)
    }
    
    var datePicker: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Today") { selectedDate = Date(); showDatePicker = false }
                Button("Tomorrow") { 
                    selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
                    showDatePicker = false 
                }
            }
            .controlSize(.small)
            
            Divider()
            
            CustomDatePicker(selection: $selectedDate)
        }
        .padding()
        .frame(width: 280)
    }
    
    // MARK: - Actions
    
    private func createTask() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let parsed = SmartInputParser.parse(text: trimmed, projects: activeProjects)
        let cleanTitle = parsed.cleanTitle.isEmpty ? trimmed : parsed.cleanTitle
        
        let task = TaskItem(
            title: cleanTitle,
            project: effectiveProject,
            estimatedDuration: effectiveDuration,
            dueDate: effectiveDate ?? Date()
        )
        task.isRecurring = effectiveRecurrence != nil
        task.recurrenceInterval = effectiveRecurrence
        
        modelContext.insert(task)
        
        // Track for UI
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            addedTasks.insert(AddedTask(title: cleanTitle, projectName: effectiveProject?.name), at: 0)
        }
        
        // Reset for next task
        resetComposer()
        text = ""
    }
    
    private func resetComposer() {
        detectedProject = nil
        detectedDuration = nil
        detectedDate = nil
        detectedRecurrence = nil
        selectedProject = nil
        selectedDate = nil
        selectedDuration = nil
        selectedRecurrence = nil
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return Self.fullDateFormatter.string(from: date)
    }
    
    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }
}
