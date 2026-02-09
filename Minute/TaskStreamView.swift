//
//  TaskStreamView.swift
//  Minute
//
//  The "Stream": A unified list of what you need to do next.
//  Aggregates tasks from all active projects.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import EventKit

struct TaskStreamView: View {
    @EnvironmentObject var calendarManager: CalendarManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt) private var allProjects: [Project]
    // Query ALL tasks - filter completion status in code to keep recently completed visible
    @Query(sort: \TaskItem.orderIndex)
    private var allTasks: [TaskItem]

    private var activeProjects: [Project] {
        allProjects.filter { $0.status == .active }
    }

    private var isLargeTaskSet: Bool {
        orderedTasks.count > 60
    }
    
    // Filter for active projects + show incomplete OR completed today (if due today or later)
    var streamTasks: [StreamItem] {
        let activeProjectIDs: Set<UUID> = Set(activeProjects.map { $0.id })
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        
        var visibleTasks: [TaskItem] = []
        for task in allTasks {
            guard let project = task.project else { continue }
            guard activeProjectIDs.contains(project.id) else { continue }
            
            if !task.isCompleted {
                // Show all incomplete tasks
                visibleTasks.append(task)
            } else if let completedAt = task.completedAt, completedAt >= todayStart {
                // Completed today - only show if it was due today or in the future (not overdue)
                let dueDate = task.dueDate ?? Date()
                let dueDayStart = calendar.startOfDay(for: dueDate)
                if dueDayStart >= todayStart {
                    // Was due today or future - keep visible briefly
                    visibleTasks.append(task)
                }
                // Otherwise it was overdue and completed - hide immediately
            }
        }
        
        // Map to StreamItems
        return visibleTasks.compactMap { task -> StreamItem? in
            guard let project = task.project else { return nil }
            return StreamItem(task: task, project: project)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header / Smart Input Area
            InlineTaskComposer(activeProjects: activeProjects)
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom, 8)
                // Removed explicit background to blend with sidebar
            
            // The Stream
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    let streamSections = sections
                    
                    // Calendar / Schedule Section
                    if calendarManager.authorizationStatus == .fullAccess || calendarManager.authorizationStatus == .writeOnly {
                        // Filter out past events
                        let now = Date()
                        let allTodayEvents = calendarManager.events(for: now)
                        let upcomingEvents = allTodayEvents.filter { $0.endDate > now }
                        
                        if !upcomingEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Button(action: { withAnimation { isScheduleExpanded.toggle() } }) {
                                    HStack {
                                        Text("Schedule")
                                            .font(.headline)
                                            .foregroundStyle(.secondary)
                                        
                                        Spacer()
                                        
                                        Text("\(upcomingEvents.count)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.1), in: Capsule())
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .rotationEffect(.degrees(isScheduleExpanded ? 90 : 0))
                                    }
                                    .padding(.horizontal, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                
                                if isScheduleExpanded {
                                    ForEach(upcomingEvents, id: \.eventIdentifier) { event in
                                        CalendarEventRow(event: event)
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                        } 
                    } else if calendarManager.authorizationStatus == .notDetermined {
                        Button("Connect Calendar") {
                            calendarManager.requestAccess()
                        }
                        .buttonStyle(.plain)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    
                    if streamSections.isEmpty {
                        EmptyStreamView()
                    } else {
                        ForEach(streamSections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                // Section Header
                                HStack {
                                    Text(section.title)
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    
                                    // Total hours for section (incomplete tasks only)
                                    let totalHours = section.tasks.filter { !$0.task.isCompleted }.reduce(0.0) { sum, item in
                                        sum + (item.task.estimatedDuration ?? 0)
                                    } / 3600.0
                                    
                                    if totalHours > 0 {
                                        Text(totalHours.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(totalHours))h" : String(format: "%.1fh", totalHours))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.1), in: Capsule())
                                    }
                                    
                                    Text("\(section.tasks.count)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.1), in: Capsule())
                                }
                                .padding(.top, 16)
                                .padding(.horizontal, 4)
                                
                                // Tasks
                                ForEach(section.tasks) { item in
                                    TaskStreamRow(item: item, activeProjects: activeProjects, onEdit: { editingTask = item.task })
                                        .transition(isLargeTaskSet ? .identity : .move(edge: .top).combined(with: .opacity))
                                        .opacity(draggedTask?.id == item.task.id ? 0.0 : 1.0)
                                        .onDrag {
                                            self.draggedTask = item.task
                                            return NSItemProvider(object: item.task.id.uuidString as NSString)
                                        } preview: {
                                            TaskStreamRow(item: item, activeProjects: activeProjects, onEdit: {})
                                                .frame(width: 350)
                                                .background(.regularMaterial)
                                                .cornerRadius(12)
                                                .contentShape(DragPreviewShape())
                                        }
                                        .onDrop(of: [.text], delegate: TaskDropDelegate(item: item.task, items: $orderedTasks, draggedItem: $draggedTask, modelContext: modelContext))
                                }
                            }
                        }
                    }

                    // Completed Section
                    if !recentCompleted.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recently Completed")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 4)
                            
                            ForEach(recentCompleted) { item in
                                CompletedTaskRow(item: item, modelContext: modelContext)
                            }
                        }
                        .padding(.top, 16)
                        .transition(isLargeTaskSet ? .identity : .opacity)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .onAppear {
                syncTasks()
                syncCompleted()
            }
            .onChange(of: allTasks) { _, _ in
                scheduleSyncTasks()
            }
            .onChange(of: allProjects) { _, _ in
                scheduleSyncTasks()
            }
            .onChange(of: allCompletedTasks) { _, _ in
                syncCompleted()
            }
            .onDisappear {
                syncWorkItem?.cancel()
            }
            .sheet(item: $editingTask) { task in
                EditTaskSheet(task: task)
            }
        }
        .background(.regularMaterial) // Unified Sidebar Material
    }
    
    // We keep this for the DropDelegate to have a binding for live reordering
    @State private var orderedTasks: [StreamItem] = []
    @State private var drags: [StreamItem] = [] // Unused but kept for structure if needed
    @State private var draggedTask: TaskItem?
    @State private var isScheduleExpanded = true
    @State private var editingTask: TaskItem?
    
    // Recent Archive
    @Query(filter: #Predicate<TaskItem> { $0.isCompleted }, sort: \TaskItem.completedAt, order: .reverse)
    private var allCompletedTasks: [TaskItem]
    
    @State private var recentCompleted: [StreamItem] = []
    @State private var syncWorkItem: DispatchWorkItem?

    private func scheduleSyncTasks(delay: TimeInterval = 0.05) {
        syncWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            syncTasks()
        }
        syncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    private func syncCompleted() {
        // Filter for "Today" (or recent)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Show tasks completed today; cap scan to avoid unbounded work as history grows.
        let todayCompleted = allCompletedTasks.prefix(250).filter { task in
            guard let date = task.completedAt else { return false }
            return date >= today
        }
        
        let nextCompleted = todayCompleted.compactMap { task -> StreamItem? in
            guard let project = task.project else { return nil }
            return StreamItem(task: task, project: project)
        }
        if nextCompleted.map({ $0.task.id }) != recentCompleted.map({ $0.task.id }) {
            recentCompleted = nextCompleted
        }
    }
    
    private func syncTasks() {
        // Use streamTasks which already filters for active projects + incomplete/recently completed
        let targetTasks = streamTasks.map { $0.task }.sorted { $0.orderIndex < $1.orderIndex }
        let targetItems = targetTasks.compactMap { task -> StreamItem? in
            guard let project = task.project else { return nil }
            return StreamItem(task: task, project: project)
        }
        
        // 2. Intelligence Merge to preserve local drag state if possible? 
        // Actually, if we just overwrite, we lose the "mid-drag" state if an update happens mid-drag.
        // But updates usually happen on drop or on external change.
        // For "Adding a task", we want it to appear immediately.
        
        // Simple Set-based diffing to add missing items and remove stale ones
        // This is robust enough for "Add Task" to work instantly.
        
        var nextOrderedTasks = orderedTasks
        let currentIDs = Set(nextOrderedTasks.map { $0.task.id })
        let targetIDs = Set(targetItems.map { $0.task.id })
        
        // Add new
        let newItems = targetItems.filter { !currentIDs.contains($0.task.id) }
        if !newItems.isEmpty {
            nextOrderedTasks.append(contentsOf: newItems)
            // Re-sort to be safe using persisted order
            nextOrderedTasks.sort { $0.task.orderIndex < $1.task.orderIndex }
        }
        
        // Remove deleted/completed
        if nextOrderedTasks.contains(where: { !targetIDs.contains($0.task.id) }) {
            nextOrderedTasks.removeAll { !targetIDs.contains($0.task.id) }
        }
        
        // If purely reorder happened elsewhere, we might want to respect orderIndex
        // But usually we are the only re-orderer.
        // Let's do a soft sort check.
        nextOrderedTasks.sort { $0.task.orderIndex < $1.task.orderIndex }

        if nextOrderedTasks.map({ $0.task.id }) != orderedTasks.map({ $0.task.id }) {
            orderedTasks = nextOrderedTasks
        }
    }
    
    // MARK: - Sections Logic
    
    struct StreamSection: Identifiable {
        var id: String { title }
        let title: String
        let tasks: [StreamItem]
    }
    
    /// Sort helper: incomplete tasks first, then completed tasks
    private func sortWithCompletedLast(_ items: [StreamItem]) -> [StreamItem] {
        let incomplete = items.filter { !$0.task.isCompleted }
        let completed = items.filter { $0.task.isCompleted }
        return incomplete + completed
    }
    
    var sections: [StreamSection] {
        var today: [StreamItem] = []
        var tomorrow: [StreamItem] = []
        var week: [StreamItem] = []
        var backlog: [StreamItem] = []
        
        let calendar = Calendar.current
        let now = Date()
        let todayEnd = calendar.startOfDay(for: now).addingTimeInterval(86400)
        let tomorrowEnd = calendar.startOfDay(for: now).addingTimeInterval(86400 * 2)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: now)!
        
        for item in orderedTasks {
            if let date = item.task.dueDate {
                if date < todayEnd {
                    today.append(item)
                } else if date < tomorrowEnd {
                    tomorrow.append(item)
                } else if date < weekEnd {
                    week.append(item)
                } else {
                    backlog.append(item)
                }
            } else {
                backlog.append(item)
            }
        }
        
        // Sort "This Week" by due date first
        week.sort { ($0.task.dueDate ?? .distantFuture) < ($1.task.dueDate ?? .distantFuture) }
        
        // Sort completed tasks to bottom within each section
        today = sortWithCompletedLast(today)
        tomorrow = sortWithCompletedLast(tomorrow)
        week = sortWithCompletedLast(week)
        backlog = sortWithCompletedLast(backlog)
        
        var result: [StreamSection] = []
        if !today.isEmpty { result.append(StreamSection(title: "Today", tasks: today)) }
        if !tomorrow.isEmpty { result.append(StreamSection(title: "Tomorrow", tasks: tomorrow)) }
        if !week.isEmpty { result.append(StreamSection(title: "This Week", tasks: week)) }
        if !backlog.isEmpty { result.append(StreamSection(title: "Backlog", tasks: backlog)) }
        
        return result
    }
}

// MARK: - Inline Composer

struct InlineTaskComposer: View {
    let activeProjects: [Project]
    @Environment(\.modelContext) private var modelContext
    
    @State private var text: String = ""
    @State private var detectedProject: Project?
    @State private var detectedDuration: TimeInterval?
    @State private var detectedDate: Date?
    @State private var showDatePicker = false
    @State private var showProjectPicker = false
    @State private var showDurationPicker = false
    @State private var customDurationText: String = ""
    
    // Recurrence State
    @State private var detectedRecurrence: String?
    @State private var selectedRecurrence: String? // "daily", "weekly" or nil
    @State private var showRecurrencePicker = false
    
    // Manual Overrides
    @State private var selectedProject: Project?
    @State private var selectedDate: Date?
    @State private var selectedDuration: TimeInterval?
    @State private var parseTask: Task<Void, Never>?
    
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

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // Input Field
            HStack {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                TextField("Add a task...", text: $text)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit {
                        createTask()
                    }
                    .onChange(of: text) { _, newValue in
                        parseTask?.cancel()
                        if newValue.isEmpty {
                            resetComposer(keepText: true)
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
            .padding(10)
            
            // "Dropdowns Underneath" / Metadata Bar
            if !text.isEmpty || effectiveProject != nil {
                HStack(spacing: 4) {
                    
                    // 1. Project Selector
                    Button {
                        showProjectPicker = true
                    } label: {
                        ComposerMenuLabel {
                            HStack(spacing: 4) {
                                if let project = effectiveProject {
                                    if let icon = project.area?.iconName {
                                        Image(systemName: icon)
                                            .font(.subheadline)
                                    }
                                    Text(project.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                } else {
                                    Text("Select Project")
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showProjectPicker, arrowEdge: .bottom) {
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
                    
                    // 2. Due Date Selector (Popover with Calendar)
                    Button {
                        showDatePicker = true
                    } label: {
                        ComposerMenuLabel {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                if let date = effectiveDate {
                                    Text(formatDate(date))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(isToday(date) ? .green : .primary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                        VStack(spacing: 12) {
                            // Presets
                            HStack {
                                Button("Today") { selectedDate = Date(); showDatePicker = false }
                                Button("Tomorrow") { selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()); showDatePicker = false }
                                Button("Weekend") {
                                    // Calculate next Saturday
                                    let nextSat = Calendar.current.nextDate(after: Date(), matching: DateComponents(weekday: 7), matchingPolicy: .nextTime)
                                    selectedDate = nextSat
                                    showDatePicker = false
                                }
                            }
                            .controlSize(.small)
                            
                            Divider()
                            
                            // Custom Calendar
                            CustomDatePicker(selection: $selectedDate)
                            
                            Divider()
                            
                            // Clear
                            Button("Clear Date") {
                                selectedDate = nil
                                showDatePicker = false
                            }
                            .foregroundStyle(.red)
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .frame(width: 280)
                    }
                    
                    // 3. Duration Selector
                    Button {
                        showDurationPicker = true
                    } label: {
                        ComposerMenuLabel {
                            HStack(spacing: 4) {
                                Image(systemName: "hourglass")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                if let duration = effectiveDuration {
                                    Text(formatDuration(duration))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.blue)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showDurationPicker, arrowEdge: .bottom) {
                        VStack(spacing: 12) {
                            
                            // Custom Input
                            HStack {
                                Image(systemName: "keyboard")
                                    .foregroundStyle(.secondary)
                                TextField("Custom min...", text: $customDurationText)
                                    .textFieldStyle(.plain)
                                    .frame(width: 80)
                                    .onSubmit {
                                        if let mins = Double(customDurationText) {
                                            selectedDuration = mins * 60
                                            showDurationPicker = false
                                            customDurationText = ""
                                        }
                                    }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                            
                            Divider()
                            
                            // Presets
                            VStack(spacing: 4) {
                                ForEach([900, 1800, 2700, 3600, 7200], id: \.self) { seconds in
                                    Button {
                                        selectedDuration = TimeInterval(seconds)
                                        showDurationPicker = false
                                    } label: {
                                        HStack {
                                            Image(systemName: seconds < 3600 ? "hourglass" : "timer")
                                                .foregroundStyle(.secondary)
                                                .font(.caption)
                                            
                                            Text(formatDuration(TimeInterval(seconds)))
                                            Spacer()
                                            
                                            if effectiveDuration == TimeInterval(seconds) {
                                                Image(systemName: "checkmark")
                                                    .font(.caption)
                                            }
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .background(effectiveDuration == TimeInterval(seconds) ? Color.accentColor.opacity(0.1) : Color.clear)
                                    .cornerRadius(6)
                                }
                            }
                        }
                        .padding()
                        .frame(width: 160)
                    }
                    
                    // 4. Recurrence Selector
                    Button {
                        showRecurrencePicker = true
                    } label: {
                        ComposerMenuLabel {
                            HStack(spacing: 4) {
                                Image(systemName: "repeat")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                if let interval = effectiveRecurrence {
                                    Text(interval.capitalized)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.blue)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showRecurrencePicker, arrowEdge: .bottom) {
                        VStack(spacing: 4) {
                            Button { selectedRecurrence = nil; showRecurrencePicker = false } label: {
                                Label("None", systemImage: "xmark.circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                            
                            Button { selectedRecurrence = "daily"; showRecurrencePicker = false } label: {
                                Label("Daily", systemImage: "sun.max")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                            
                            Button { selectedRecurrence = "weekly"; showRecurrencePicker = false } label: {
                                Label("Weekly", systemImage: "calendar")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .frame(width: 140)
                    }
                    
                    Spacer()
                    
                    // Add Button (Visual confirmation)
                    Button(action: createTask) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(text.isEmpty ? .secondary.opacity(0.5) : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(text.isEmpty)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 4)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: text.isEmpty)
        .onDisappear {
            parseTask?.cancel()
        }
    }
    
    private func createTask() {
        guard !text.isEmpty, let project = effectiveProject else { return }
        
        // Final Parsing Logic
        let result = SmartInputParser.parse(text: text, projects: activeProjects)
        let finalTitle = result.cleanTitle.isEmpty ? text : result.cleanTitle
        
        let task = TaskItem(
            title: finalTitle,
            project: project,
            estimatedDuration: effectiveDuration,
            dueDate: effectiveDate
        )
        
        if let recurrence = effectiveRecurrence {
            task.isRecurring = true
            task.recurrenceInterval = recurrence
        }
        
        modelContext.insert(task)
        
        // Reset
        resetComposer()
    }
    
    private func resetComposer(keepText: Bool = false) {
        if !keepText {
            text = ""
        }
        selectedProject = nil
        selectedDate = nil
        selectedDuration = nil
        detectedProject = nil
        detectedDuration = nil
        detectedDate = nil
        detectedRecurrence = nil
        selectedRecurrence = nil
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
    
    private func formatDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return Self.shortDateFormatter.string(from: date)
    }
    
    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
}

// MARK: - Components Helper
struct ComposerMenuLabel<Content: View>: View {
    let content: Content
    @State private var isHovering = false
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .glassEffect(.regular)
                    .opacity(isHovering ? 0.6 : 0.0)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(isHovering ? 0.3 : 0.0), lineWidth: 1)
            )
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hover
                }
            }
    }
}

// ... rest of file (DropDelegate, StreamItem, Rows, EmptyView, Shape)

struct TaskDropDelegate: DropDelegate {
    let item: TaskItem
    @Binding var items: [StreamItem]
    @Binding var draggedItem: TaskItem?
    let modelContext: ModelContext
    
    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem else { return }
        
        if draggedItem.id != item.id {
            if let from = items.firstIndex(where: { $0.task.id == draggedItem.id }),
               let to = items.firstIndex(where: { $0.task.id == item.id }) {
                withAnimation(.default) {
                items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        for (index, item) in items.enumerated() {
            item.task.orderIndex = index
        }
        try? modelContext.save()
        self.draggedItem = nil
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - Models

struct StreamItem: Identifiable {
    var id: UUID { task.id }
    let task: TaskItem
    let project: Project
}

// MARK: - Components

struct TaskStreamRow: View {
    let item: StreamItem
    let activeProjects: [Project]
    let onEdit: () -> Void
    @Environment(\.modelContext) private var modelContext
    
    @State private var isHovering = false
    
    // Inline Editing State
    @State private var isEditingTitle = false
    @State private var editedTitle: String = ""
    @State private var showProjectPicker = false
    @State private var showDatePicker = false
    @State private var showDurationPicker = false
    @State private var showRecurrencePicker = false
    
    @FocusState private var titleFieldFocused: Bool
    
    var projectColor: Color {
        Color(hex: item.project.area?.themeColor ?? "8E8E93") ?? .gray
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
    
    // Helpers
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
    
    private func formatDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return Self.shortDateFormatter.string(from: date)
    }
    
    private func isOverdue(_ date: Date) -> Bool {
        date < Date() && !Calendar.current.isDateInToday(date)
    }
    
    @State private var isCompleting = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox (Completion)
            Button(action: {
                withAnimation(.snappy) {
                    isCompleting = true
                }
                // Capture task reference before async delay
                let taskToComplete = item.task
                let context = modelContext
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation {
                        taskToComplete.isCompleted = true
                        taskToComplete.completedAt = Date()
                    }
                    // Explicit save to ensure persistence
                    do {
                        try context.save()
                    } catch {
                        print("Failed to save task completion: \(error)")
                    }
                }
            }) {
                let isChecked = isCompleting || item.task.isCompleted
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                   .font(.system(size: 18))
                   .foregroundStyle(isChecked ? .green : .secondary)
            }
            .buttonStyle(.plain)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Editable Title
                if isEditingTitle {
                    TextField("Task name", text: $editedTitle)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .fontWeight(.medium)
                        .focused($titleFieldFocused)
                        .onSubmit {
                            saveTitle()
                        }
                        .onExitCommand {
                            cancelTitleEdit()
                        }
                } else {
                    Text(item.task.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .strikethrough(isCompleting || item.task.isCompleted)
                        .foregroundStyle((isCompleting || item.task.isCompleted) ? .secondary : .primary)
                        .onTapGesture {
                            startTitleEdit()
                        }
                }
                
                // Editable Metadata Row
                HStack(spacing: 6) {
                    // Project Badge (Editable)
                    EditableBadge(showPopover: $showProjectPicker) {
                        HStack(spacing: 4) {
                            if let icon = item.project.area?.iconName {
                                Image(systemName: icon)
                                    .font(.caption2)
                            }
                            Text(item.project.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundStyle(projectColor)
                    } popover: {
                        ProjectPickerPopover(
                            projects: activeProjects,
                            selection: .constant(item.task.project)
                        ) { project in
                            item.task.project = project
                            showProjectPicker = false
                        }
                    }
                    
                    // Duration Badge (Editable)
                    EditableBadge(showPopover: $showDurationPicker) {
                        HStack(spacing: 2) {
                            Image(systemName: "hourglass")
                            if let duration = item.task.estimatedDuration {
                                Text(formatDuration(duration))
                            } else {
                                Text("—")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .opacity(item.task.estimatedDuration != nil ? 1.0 : 0.5)
                    } popover: {
                        DurationPickerPopover(
                            selection: Binding(
                                get: { item.task.estimatedDuration },
                                set: { item.task.estimatedDuration = $0 }
                            ),
                            isPresented: $showDurationPicker
                        )
                    }
                    
                    // Date Badge (Editable)
                    EditableBadge(showPopover: $showDatePicker) {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar")
                            if let date = item.task.dueDate {
                                Text(formatDate(date))
                                    .foregroundStyle(isOverdue(date) ? .red : .secondary)
                            } else {
                                Text("—")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .opacity(item.task.dueDate != nil ? 1.0 : 0.5)
                    } popover: {
                        DatePickerPopover(
                            selection: Binding(
                                get: { item.task.dueDate },
                                set: { item.task.dueDate = $0 }
                            ),
                            isPresented: $showDatePicker
                        )
                    }
                    
                    // Recurrence Badge (Editable)
                    EditableBadge(showPopover: $showRecurrencePicker) {
                        HStack(spacing: 2) {
                            Image(systemName: "repeat")
                            if item.task.isRecurring, let interval = item.task.recurrenceInterval {
                                Text(interval.capitalized)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(item.task.isRecurring ? AnyShapeStyle(.blue) : AnyShapeStyle(.tertiary))
                    } popover: {
                        RecurrencePickerPopover(
                            isRecurring: Binding(
                                get: { item.task.isRecurring },
                                set: { item.task.isRecurring = $0 }
                            ),
                            recurrenceInterval: Binding(
                                get: { item.task.recurrenceInterval },
                                set: { item.task.recurrenceInterval = $0 }
                            ),
                            isPresented: $showRecurrencePicker
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.white.opacity(0.05)),
            alignment: .bottom
        )
        .background(isHovering ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onHover { hover in
            isHovering = hover
        }
        .onChange(of: titleFieldFocused) { _, focused in
            if !focused && isEditingTitle {
                saveTitle()
            }
        }
        .onTapGesture(count: 2) {
            onEdit()
        }
        .contextMenu {
            Button("Edit Task...") { onEdit() }
            Button("Rename") { startTitleEdit() }
            Divider()
            Button("Delete", role: .destructive) {
                withAnimation {
                    modelContext.delete(item.task)
                }
            }
        }
    }
    
    // MARK: - Title Editing
    
    private func startTitleEdit() {
        editedTitle = item.task.title
        isEditingTitle = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            titleFieldFocused = true
        }
    }
    
    private func saveTitle() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            item.task.title = trimmed
        }
        isEditingTitle = false
    }
    
    private func cancelTitleEdit() {
        isEditingTitle = false
    }
}

struct EmptyStreamView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            Text("No tasks in the stream")
                .font(.headline)
            
            Text("Use the input above to add tasks to your active projects.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

struct DragPreviewShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: 12)
    }
}

struct CalendarEventRow: View {
    let event: EKEvent
    
    var body: some View {
        HStack(spacing: 12) {
            // Time Column
            VStack(alignment: .trailing, spacing: 0) {
                Text(event.startDate, style: .time)
                    .font(.caption2)
                    .fontWeight(.bold)
                Text(event.endDate, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, alignment: .trailing)
            
            // Marker
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: event.calendar.color))
                .frame(width: 4)
                .padding(.vertical, 2)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(6)
    }
}
