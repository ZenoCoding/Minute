//
//  CaptureView.swift
//  Minute
//
//  Full-screen quick capture mode for rapid task brain dump.
//

import SwiftUI
import SwiftData

struct FullScreenCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var calendarManager: CalendarManager
    @Binding var isPresented: Bool
    let onAuxiliaryPresentationChanged: (Bool) -> Void
    
    @Query(sort: \Project.createdAt)
    private var allProjects: [Project]

    @Query(sort: \TaskItem.createdAt)
    private var allTasks: [TaskItem]
    
    private var activeProjects: [Project] {
        allProjects.filter { $0.status == .active }
    }
    
    // Input state
    @State private var text: String = ""
    @State private var detectedProject: Project?
    @State private var detectedDuration: TimeInterval?
    @State private var detectedDate: Date?
    @State private var detectedRecurrence: String?
    @State private var detectedIsEvent = false
    
    // Manual overrides
    @State private var selectedProject: Project?
    @State private var selectedDate: Date?
    @State private var selectedDuration: TimeInterval?
    @State private var selectedRecurrence: String?
    @State private var parseTask: Task<Void, Never>?
    @State private var inferenceTask: Task<Void, Never>?
    @State private var isInferringProject = false
    @AppStorage(CodexProjectInferenceSettings.enabledKey) private var experimentalCodexInferenceEnabled = false
    
    // Pickers
    @State private var showDatePicker = false
    @State private var showProjectPicker = false
    @State private var showDurationPicker = false
    @State private var showDetails = false
    @State private var customDurationText: String = ""
    @State private var newProjectName: String = ""
    @State private var launchingTask: TaskItem?
    @State private var launchAnimationTask: Task<Void, Never>?
    @State private var editingTask: TaskItem?
    
    @FocusState private var isInputFocused: Bool
    @Namespace private var taskGlassNamespace
    @Namespace private var taskMotionNamespace
    
    // Effective Values
    var effectiveProject: Project? {
        selectedProject ?? detectedProject
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

    var effectiveIsEvent: Bool {
        detectedIsEvent
    }

    private var projectCandidates: [SmartInputParser.ProjectCandidate] {
        activeProjects.map { project in
            let recentTitles = allTasks
                .filter { $0.project?.id == project.id }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(12)
                .map(\.title)
            let hints = [project.area?.name].compactMap { $0 } + recentTitles
            return SmartInputParser.ProjectCandidate(name: project.name, hints: hints)
        }
    }

    private var topTasks: [TaskItem] {
        let sortedTasks = allTasks
            .filter { task in
                guard !task.isCompleted else { return false }
                guard let project = task.project else { return false }
                return project.status == .active
            }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (left?, right?):
                    if left != right { return left < right }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }

                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }

                return lhs.createdAt < rhs.createdAt
            }

        return Array(
            sortedTasks
                .filter { $0.id != launchingTask?.id }
                .prefix(5)
        )
    }

    private var isPresentingAuxiliaryUI: Bool {
        showDatePicker || showProjectPicker || showDurationPicker || editingTask != nil
    }

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()
    
    var body: some View {
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 18) {
                composerBlock

                if !topTasks.isEmpty {
                    topTaskList
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 800, alignment: .center)
        .frame(maxWidth: .infinity, maxHeight: 580, alignment: .center)
        .background(Color.black.opacity(0.001))
        .onExitCommand {
            isPresented = false
        }
        .task {
            // The controller installs a fresh root view for every presentation,
            // so this task runs (and is cancelled) once per panel session.
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            isInputFocused = true
        }
        .onDisappear {
            parseTask?.cancel()
            inferenceTask?.cancel()
            launchAnimationTask?.cancel()
            isInputFocused = false
            onAuxiliaryPresentationChanged(false)
        }
        .onChange(of: isPresentingAuxiliaryUI) { _, isPresented in
            onAuxiliaryPresentationChanged(isPresented)
        }
        .sheet(item: $editingTask) { task in
            EditTaskSheet(task: task)
        }
    }

    private var topTaskList: some View {
        VStack(spacing: 10) {
            ForEach(topTasks) { task in
                quickTaskCard(task)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 720)
        .animation(.spring(response: 0.55, dampingFraction: 0.78), value: topTasks.map(\.id))
    }

    private var composerBlock: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                TextField("Add a task or event...", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .regular))
                    .focused($isInputFocused)
                    .onSubmit {
                        createTask()
                    }
                    .onChange(of: text) { _, newValue in
                        parseTask?.cancel()
                        inferenceTask?.cancel()
                        inferenceTask = nil
                        isInferringProject = false
                        if newValue.isEmpty {
                            resetComposer()
                        } else {
                            let inputSnapshot = newValue
                            let candidateSnapshot = projectCandidates
                            parseTask = Task {
                                try? await Task.sleep(for: .milliseconds(120))
                                guard !Task.isCancelled else { return }

                                let result = SmartInputParser.parseForComposer(
                                    text: inputSnapshot,
                                    projectCandidates: candidateSnapshot
                                )
                                guard !Task.isCancelled else { return }

                                await MainActor.run {
                                    guard text == inputSnapshot else { return }
                                    let locallyDetectedProject = result.projectName.flatMap { matchedName in
                                        activeProjects.first {
                                            $0.name.caseInsensitiveCompare(matchedName) == .orderedSame
                                        }
                                    }
                                    if let locallyDetectedProject {
                                        detectedProject = locallyDetectedProject
                                    }
                                    detectedDuration = result.duration
                                    detectedDate = result.date
                                    detectedRecurrence = result.recurrenceInterval
                                    detectedIsEvent = result.isEvent

                                    if locallyDetectedProject == nil, !result.isEvent {
                                        scheduleLiveProjectInference(
                                            text: inputSnapshot,
                                            candidates: candidateSnapshot
                                        )
                                    }
                                }
                            }
                        }
                    }

                if isInferringProject {
                    ProjectInferenceSpinner()
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(16)

            if !text.isEmpty {
                metadataBar
                    .transition(
                        .move(edge: .top)
                            .combined(with: .opacity)
                    )

                if showDetails {
                    detailPanel
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

            }
        }
        .padding(6)
        .frame(maxWidth: 720)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            if isInferringProject {
                ProjectInferenceGlow(cornerRadius: 20)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isInferringProject)
        .animation(
            .spring(response: 0.38, dampingFraction: 0.86),
            value: text.isEmpty
        )
        .overlay {
            if let launchingTask {
                quickTaskCard(launchingTask)
                    .zIndex(1)
            }
        }
    }
    
    // MARK: - Metadata Bar
    
    var metadataBar: some View {
        HStack(spacing: 12) {
            if effectiveIsEvent {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.plus")
                    Text("Event")
                }
                .font(.caption)
                .foregroundStyle(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.clear.interactive(), in: Capsule())
                .overlay {
                    Capsule().stroke(.primary.opacity(0.18), lineWidth: 1)
                }
            } else {
                // Project
                Button { showProjectPicker = true } label: {
                    HStack(spacing: 6) {
                        if let icon = effectiveProject?.area?.iconName {
                            Image(systemName: icon)
                        } else if effectiveProject != nil {
                            Image(systemName: "folder")
                        } else {
                            Image(systemName: "tray")
                        }
                        if let project = effectiveProject {
                            Text(project.name)
                        } else {
                            Text("Inbox")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(effectiveProject == nil ? .secondary : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.clear.interactive(), in: Capsule())
                    .overlay {
                        Capsule().stroke(.primary.opacity(0.18), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showProjectPicker, arrowEdge: .bottom) {
                    projectPicker
                }
            }
            
            // Date
            Button { showDatePicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(effectiveDate.map { formatDate($0) } ?? "No date")
                }
                .font(.caption)
                .foregroundStyle(effectiveDate.map { isToday($0) ? Color.green : Color.primary } ?? Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.clear.interactive(), in: Capsule())
                .overlay {
                    Capsule().stroke(.primary.opacity(0.18), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                datePicker
            }
            
            // Duration
            if let duration = effectiveDuration {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass")
                    Text(formatDuration(duration))
                }
                .font(.caption)
                .foregroundStyle(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.clear.interactive(), in: Capsule())
                .overlay {
                    Capsule().stroke(.primary.opacity(0.18), lineWidth: 1)
                }
            }
            
            // Recurrence
            if !effectiveIsEvent, let recurrence = effectiveRecurrence {
                HStack(spacing: 6) {
                    Image(systemName: "repeat")
                    Text(recurrence.capitalized)
                }
                .font(.caption)
                .foregroundStyle(.purple)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.clear.interactive(), in: Capsule())
                .overlay {
                    Capsule().stroke(.primary.opacity(0.18), lineWidth: 1)
                }
            }
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    showDetails.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showDetails ? "chevron.up" : "slider.horizontal.3")
                    Text("Details")
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.clear.interactive(), in: Capsule())
                .overlay {
                    Capsule().stroke(.primary.opacity(0.18), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .offset(y: -6)
    }

    @ViewBuilder
    private func quickTaskCard(_ task: TaskItem) -> some View {
        if let project = task.project {
            TaskStreamRow(
                item: StreamItem(task: task, project: project),
                activeProjects: activeProjects,
                onEdit: { editingTask = task }
            )
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .glassEffectID(task.id, in: taskGlassNamespace)
            .glassEffectTransition(.matchedGeometry)
            .matchedGeometryEffect(id: task.id, in: taskMotionNamespace)
        }
    }

    var detailPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if !effectiveIsEvent {
                    Button { showProjectPicker = true } label: {
                        detailControl(
                            icon: effectiveProject?.area?.iconName ?? (effectiveProject == nil ? "tray" : "folder"),
                            title: "Project",
                            value: effectiveProject?.name ?? "Inbox"
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button { showDatePicker = true } label: {
                    detailControl(
                        icon: "calendar",
                        title: effectiveIsEvent ? "When" : "Due",
                        value: effectiveDate.map { formatDate($0) } ?? "No date"
                    )
                }
                .buttonStyle(.plain)

                Button { showDurationPicker = true } label: {
                    detailControl(
                        icon: "hourglass",
                        title: "Estimate",
                        value: effectiveDuration.map { formatDuration($0) } ?? "Add"
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDurationPicker, arrowEdge: .bottom) {
                    durationPicker
                }

                if !effectiveIsEvent {
                    Menu {
                        Button("None") { selectedRecurrence = nil }
                        Button("Daily") { selectedRecurrence = "daily" }
                        Button("Weekly") { selectedRecurrence = "weekly" }
                    } label: {
                        detailControl(
                            icon: "repeat",
                            title: "Repeat",
                            value: effectiveRecurrence?.capitalized ?? "None"
                        )
                    }
                    .buttonStyle(.plain)
                    .menuStyle(.borderlessButton)
                }
            }
        }
        .padding(12)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func detailControl(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    // MARK: - Pickers
    
    var projectPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("New project", text: $newProjectName)
                    .textFieldStyle(.plain)
                    .onSubmit(createProjectFromPicker)

                Button(action: createProjectFromPicker) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(activeProjects) { project in
                        Button {
                            selectedProject = project
                            ProjectInferenceMemory.record(text: text, projectName: project.name)
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
            }
        }
        .padding()
        .frame(width: 230, height: 250)
    }
    
    var datePicker: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Today") { selectedDate = DueDateSupport.presetToday(); showDatePicker = false }
                Button("Tomorrow") { 
                    selectedDate = DueDateSupport.presetTomorrow()
                    showDatePicker = false 
                }
                Button("No Date") {
                    selectedDate = nil
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

    var durationPicker: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                TextField("Minutes", text: $customDurationText)
                    .textFieldStyle(.plain)
                    .frame(width: 80)
                    .onSubmit {
                        if let minutes = Double(customDurationText) {
                            selectedDuration = minutes * 60
                            customDurationText = ""
                            showDurationPicker = false
                        }
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            Divider()

            ForEach([900, 1800, 2700, 3600, 7200], id: \.self) { seconds in
                Button {
                    selectedDuration = TimeInterval(seconds)
                    showDurationPicker = false
                } label: {
                    HStack {
                        Text(formatDuration(TimeInterval(seconds)))
                        Spacer()
                        if effectiveDuration == TimeInterval(seconds) {
                            Image(systemName: "checkmark")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 180)
    }
    
    // MARK: - Actions

    private func deleteTask(_ task: TaskItem) {
        withAnimation(.snappy) {
            modelContext.delete(task)
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to delete task: \(error)")
        }
    }

    private func createProjectFromPicker() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        do {
            let service = MinuteDataService(modelContext: modelContext)
            if let existingProject = try service.findProject(named: name) {
                selectedProject = existingProject
            } else {
                selectedProject = try service.createProject(name: name)
                try service.save()
            }
        } catch {
            print("Failed to create project: \(error)")
            return
        }

        newProjectName = ""
        showProjectPicker = false
    }
    
    private func createTask() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let parsed = SmartInputParser.parseForComposer(
            text: trimmed,
            projectCandidates: projectCandidates
        )
        let cleanTitle = parsed.cleanTitle.isEmpty ? trimmed : parsed.cleanTitle

        if parsed.isEvent {
            let createdEvent = calendarManager.createQuickEvent(
                title: cleanTitle,
                date: effectiveDate ?? parsed.date,
                duration: effectiveDuration ?? parsed.duration,
                hasExplicitTime: parsed.dateHasExplicitTime
            )

            if createdEvent {
                resetComposer()
                text = ""
                return
            }

            return
        }

        let parsedProject = parsed.projectName.flatMap { matchedName in
            activeProjects.first {
                $0.name.caseInsensitiveCompare(matchedName) == .orderedSame
            }
        }

        let resolvedProject = selectedProject ?? detectedProject ?? parsedProject
        if let selectedProject {
            ProjectInferenceMemory.record(text: trimmed, projectName: selectedProject.name)
        }

        let createdTask = finishTask(
            title: cleanTitle,
            project: resolvedProject,
            duration: selectedDuration ?? parsed.duration,
            date: selectedDate ?? parsed.date,
            recurrence: selectedRecurrence ?? parsed.recurrenceInterval
        )

        if let createdTask,
           experimentalCodexInferenceEnabled,
           resolvedProject == nil,
           !projectCandidates.isEmpty {
            improveProjectAfterCapture(
                task: createdTask,
                text: trimmed,
                candidates: projectCandidates
            )
        }
    }

    private func scheduleLiveProjectInference(
        text input: String,
        candidates: [SmartInputParser.ProjectCandidate]
    ) {
        guard experimentalCodexInferenceEnabled, !candidates.isEmpty else { return }
        inferenceTask?.cancel()

        inferenceTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard text == input, selectedProject == nil else { return }
                isInferringProject = true
            }
            let inferredName = try? await CodexProjectInferenceService.inferProjectName(
                text: input,
                candidates: candidates
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard text == input, selectedProject == nil else { return }
                isInferringProject = false
                inferenceTask = nil
                let inferredProject = inferredName.flatMap { name in
                    activeProjects.first {
                        $0.name.caseInsensitiveCompare(name) == .orderedSame
                    }
                }
                if let inferredProject {
                    detectedProject = inferredProject
                }
            }
        }
    }

    private func improveProjectAfterCapture(
        task: TaskItem,
        text: String,
        candidates: [SmartInputParser.ProjectCandidate]
    ) {
        Task {
            let inferredName = try? await CodexProjectInferenceService.inferProjectName(
                text: text,
                candidates: candidates
            )
            guard let inferredName,
                  let project = activeProjects.first(where: {
                      $0.name.caseInsensitiveCompare(inferredName) == .orderedSame
                  }) else { return }

            await MainActor.run {
                guard task.modelContext != nil else { return }
                task.project = project
                try? modelContext.save()
            }
        }
    }

    @discardableResult
    private func finishTask(
        title: String,
        project: Project?,
        duration: TimeInterval?,
        date: Date?,
        recurrence: String?
    ) -> TaskItem? {
        let service = MinuteDataService(modelContext: modelContext)
        let task: TaskItem

        do {
            task = try service.createTask(
                title: title,
                project: project,
                estimatedDuration: duration,
                dueDate: date,
                recurrenceInterval: recurrence
            )
            try service.save()
        } catch {
            print("Failed to create task: \(error)")
            return nil
        }
        
        launchAnimationTask?.cancel()
        launchingTask = task

        launchAnimationTask = Task {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
                    launchingTask = nil
                }
            }
        }
        
        // Reset for next task
        resetComposer()
        text = ""
        return task
    }
    
    private func resetComposer() {
        detectedProject = nil
        detectedDuration = nil
        detectedDate = nil
        detectedRecurrence = nil
        detectedIsEvent = false
        selectedProject = nil
        selectedDate = nil
        selectedDuration = nil
        selectedRecurrence = nil
        showDetails = false
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
