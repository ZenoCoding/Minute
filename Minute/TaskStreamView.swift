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

struct TaskStreamView: View {
    @EnvironmentObject var tracker: TrackerService
    @EnvironmentObject var calendarManager: CalendarManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt) private var allProjects: [Project]
    // 1. Query Tasks directly for reactivity (Active "To Do" items)
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted }, sort: \TaskItem.orderIndex)
    private var allIncompleteTasks: [TaskItem]
    
    // 2. Filter for only active projects
    var streamTasks: [StreamItem] {
        let activeProjectIDs = Set(allProjects.filter { $0.status == .active }.map { $0.id })
        
        // Filter tasks that belong to active projects
        let visibleTasks = allIncompleteTasks.filter { task in
            guard let project = task.project else { return false }
            return activeProjectIDs.contains(project.id)
        }
        
        return visibleTasks.map { StreamItem(task: $0, project: $0.project!) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header / Smart Input Area
            InlineTaskComposer(activeProjects: allProjects.filter { $0.status == .active })
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom, 8)
                // Removed explicit background to blend with sidebar
            
            // The Stream
            ScrollView {
                VStack(spacing: 8) {
                    
                    // Calendar / Schedule Section
                    if calendarManager.authorizationStatus == .authorized {
                        let todayEvents = calendarManager.events(for: Date())
                        if !todayEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Schedule")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                                
                                ForEach(todayEvents, id: \.eventIdentifier) { event in
                                    CalendarEventRow(event: event)
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
                    
                    // Header Status
                    HStack {
                        Text("Today's Stream")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(streamTasks.count)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.1), in: Capsule()) // Darker for contrast on glass
                    }
                    .padding(.top, 4)
                    .padding(.horizontal, 4)
                    
                    if streamTasks.isEmpty {
                        EmptyStreamView()
                    } else {
                        ForEach(streamTasks) { item in
                            TaskStreamRow(item: item)
                                .opacity(draggedTask?.id == item.task.id ? 0.0 : 1.0)
                                .onDrag {
                                    self.draggedTask = item.task
                                    return NSItemProvider(object: item.task.id.uuidString as NSString)
                                } preview: {
                                    TaskStreamRow(item: item)
                                        .frame(width: 350)
                                        .background(.regularMaterial)
                                        .cornerRadius(12)
                                        .contentShape(DragPreviewShape())
                                }
                                .onDrop(of: [.text], delegate: TaskDropDelegate(item: item.task, items: $orderedTasks, draggedItem: $draggedTask, modelContext: modelContext))
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                
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
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                    .transition(.opacity)
                }
            }
            .onAppear(perform: syncTasks)
            .onChange(of: allIncompleteTasks) { _, _ in syncTasks() }
            .onChange(of: allProjects) { _, _ in syncTasks() }
            .onChange(of: allCompletedTasks) { _, _ in syncCompleted() }
        }
        .background(.regularMaterial) // Unified Sidebar Material
    }
    
    // We keep this for the DropDelegate to have a binding for live reordering
    @State private var orderedTasks: [StreamItem] = []
    @State private var drags: [StreamItem] = [] // Unused but kept for structure if needed
    @State private var draggedTask: TaskItem?
    
    // Recent Archive
    @Query(filter: #Predicate<TaskItem> { $0.isCompleted }, sort: \TaskItem.completedAt, order: .reverse)
    private var allCompletedTasks: [TaskItem]
    
    @State private var recentCompleted: [StreamItem] = []
    
    private func syncCompleted() {
        // Filter for "Today" (or recent)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Show tasks completed today
        let todayCompleted = allCompletedTasks.filter { task in
            guard let date = task.completedAt else { return false }
            return date >= today
        }
        
        recentCompleted = todayCompleted.map { StreamItem(task: $0, project: $0.project!) }
    }
    
    private func syncTasks() {
        // 1. Calculate the target set of tasks based on active projects query
        let activeProjectIDs = Set(allProjects.filter { $0.status == .active }.map { $0.id })
        
        let targetTasks = allIncompleteTasks.filter { task in
            guard let project = task.project else { return false }
            return activeProjectIDs.contains(project.id)
        }
        .sorted { $0.orderIndex < $1.orderIndex }
        
        let targetItems = targetTasks.map { StreamItem(task: $0, project: $0.project!) }
        
        // 2. Intelligence Merge to preserve local drag state if possible? 
        // Actually, if we just overwrite, we lose the "mid-drag" state if an update happens mid-drag.
        // But updates usually happen on drop or on external change.
        // For "Adding a task", we want it to appear immediately.
        
        // Simple Set-based diffing to add missing items and remove stale ones
        // This is robust enough for "Add Task" to work instantly.
        
        let currentIDs = Set(orderedTasks.map { $0.task.id })
        let targetIDs = Set(targetItems.map { $0.task.id })
        
        // Add new
        let newItems = targetItems.filter { !currentIDs.contains($0.task.id) }
        if !newItems.isEmpty {
            orderedTasks.append(contentsOf: newItems)
            // Re-sort to be safe using persisted order
            orderedTasks.sort { $0.task.orderIndex < $1.task.orderIndex }
        }
        
        // Remove deleted/completed
        if orderedTasks.contains(where: { !targetIDs.contains($0.task.id) }) {
             orderedTasks.removeAll { !targetIDs.contains($0.task.id) }
        }
        
        // If purely reorder happened elsewhere, we might want to respect orderIndex
        // But usually we are the only re-orderer.
        // Let's do a soft sort check.
        orderedTasks.sort { $0.task.orderIndex < $1.task.orderIndex }
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
    
    // Manual Overrides
    @State private var selectedProject: Project?
    @State private var selectedDate: Date?
    @State private var selectedDuration: TimeInterval?
    
    // Effective Values
    var effectiveProject: Project? {
        selectedProject ?? detectedProject ?? activeProjects.first
    }
    
    var effectiveDuration: TimeInterval? {
        selectedDuration ?? detectedDuration
    }
    
    var effectiveDate: Date? {
        selectedDate ?? detectedDate
    }
    
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
                        if newValue.isEmpty {
                            resetComposer(keepText: true)
                        } else {
                            parseInput(newValue)
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
                                            .font(.caption)
                                    }
                                    Text(project.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                } else {
                                    Text("Select Project")
                                        .font(.caption)
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
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                
                                if let date = effectiveDate {
                                    Text(formatDate(date))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(isToday(date) ? .green : .primary)
                                } else {
                                    Text("No Date")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                
                                if let duration = effectiveDuration {
                                    Text(formatDuration(duration))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                // Removed "Est. Time" text for compact icon-only look
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
                .padding(.top, 4) // Reduced top padding since divider is gone
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 4) // Reduced internal padding
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: text.isEmpty)
    }
    
    private func parseInput(_ input: String) {
        let result = SmartInputParser.parse(text: input, projects: activeProjects)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            self.detectedProject = result.project
            self.detectedDuration = result.duration
            self.detectedDate = result.date
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
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
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
                Capsule()
                    .glassEffect(.regular)
                    .opacity(isHovering ? 1.0 : 0.0)
            }
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(isHovering ? 0.3 : 0.0), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
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
                _ = items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
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
    let id = UUID()
    let task: TaskItem
    let project: Project
}

// MARK: - Components

struct TaskStreamRow: View {
    let item: StreamItem
    @EnvironmentObject var tracker: TrackerService
    @Environment(\.modelContext) private var modelContext
    @State private var isHovering = false
    
    var projectColor: Color {
        Color(hex: item.project.area?.themeColor ?? "8E8E93") ?? .gray
    }
    
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
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func isOverdue(_ date: Date) -> Bool {
        date < Date() && !Calendar.current.isDateInToday(date)
    }
    
    var isActive: Bool {
        tracker.activeTask?.id == item.task.id
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause Button
            Button(action: {
                if isActive {
                    tracker.stopCurrentTask()
                } else {
                    tracker.startTask(item.task)
                }
            }) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.accentColor : Color.clear)
                        .stroke(isActive ? Color.accentColor : .secondary.opacity(0.3), lineWidth: 1)
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: isActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(isActive ? .white : .secondary)
                        .offset(x: isActive ? 0 : 1) // Optical center active
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            
            // Checkbox (Completion)
            Button(action: {
                // If completing active task, stop first
                if isActive { tracker.stopCurrentTask() }
                
                withAnimation {
                    item.task.isCompleted = true
                    item.task.completedAt = Date()
                }
            }) {
                Image(systemName: "circle")
                   .font(.system(size: 18))
                   .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(item.task.title)
                    .font(.body)
                    .fontWeight(.medium)
                
                
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        if let icon = item.project.area?.iconName {
                            Image(systemName: icon)
                                .font(.caption2)
                        }
                        Text(item.project.name)
                            .font(.caption)
                    }
                    .foregroundStyle(projectColor)
                    
                    // Metadata Badges
                    if let duration = item.task.estimatedDuration {
                        HStack(spacing: 2) {
                            Image(systemName: "hourglass")
                            Text(formatDuration(duration))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    
                    if let date = item.task.dueDate {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar")
                            Text(formatDate(date))
                        }
                        .font(.caption2)
                        .foregroundStyle(isOverdue(date) ? .red : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle()) // Clickable area for drag
            // We expose drag here so the checkbox remains clickable without conflict
            .onDrag {
                // We need a way to bubble this up or handle it. 
                // Since TaskStreamRow is inside ForEach with onDrag, 
                // we can't easily move onDrag INSIDE without changing the ForEach logic.
                // Reverting approach: Use ButtonStyle Primitive.
                return NSItemProvider()
            }
            
            Spacer()
            
            // Hover Actions
            if isHovering {
                HStack(spacing: 0) {

                    
                    Menu {
                        Button("Edit Task...") { /* TODO */ }
                        Divider()
                        Button("Delete", role: .destructive) {
                            withAnimation {
                                modelContext.delete(item.task)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 8) // List-style padding
        .padding(.horizontal, 12)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.white.opacity(0.05)),
            alignment: .bottom
        )
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .onHover { hover in
            isHovering = hover
        }
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
