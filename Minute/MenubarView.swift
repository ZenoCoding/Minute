
import SwiftUI
import SwiftData

struct MenubarView: View {
    @EnvironmentObject var calendarManager: CalendarManager
    @Environment(\.modelContext) private var modelContext
    
    // Query for active tasks
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted }, sort: \TaskItem.orderIndex)
    private var allTasks: [TaskItem]
    
    var highlightedEvents: [CalendarHighlight] {
        let now = Date()
        return calendarManager.highlights(for: now, now: now)
    }
    
    var nextEvent: CalendarHighlight? {
        highlightedEvents.first
    }
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 0) { // Tighter global spacing, controlled locally
            // 1. Next Up (Hero)
            if let event = nextEvent {
                HStack(alignment: .firstTextBaseline) {
                    Text("Next")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.headline)
                            .fontWeight(.medium)
                            .lineLimit(2)
                        
                        Text(event.isAllDay ? "All Day" : timeFormatter.string(from: event.startDate))
                            .font(.caption)
                            .foregroundStyle(Color(nsColor: event.calendarColor))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5)) // Subtle highlight for active
            } else {
                Text("No key events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
            
            Divider()
                .opacity(0.3)
            
            // 2. Schedule List
            ScrollView {
                VStack(spacing: 6) {
                    Spacer().frame(height: 8)
                    
                    if highlightedEvents.count > 1 {
                        ForEach(highlightedEvents.dropFirst()) { event in
                            HStack(alignment: .firstTextBaseline) {
                                Text(event.isAllDay ? "All Day" : timeFormatter.string(from: event.startDate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                    .monospacedDigit()
                                
                                Text(event.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    
                    // 3. Top Tasks
                    let topTasks = Array(allTasks.prefix(3))
                    if !topTasks.isEmpty {
                        if highlightedEvents.count > 1 {
                             Divider()
                                .opacity(0.3)
                                .padding(.vertical, 4)
                        }
                        
                        ForEach(topTasks) { task in
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: "circle")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 60, alignment: .leading) // Align with time
                                
                                Text(task.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()

                                Menu {
                                    Button("Delete Task", role: .destructive) {
                                        deleteTask(task)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20, height: 20)
                                        .contentShape(Rectangle())
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .fixedSize()
                            }
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Delete Task", role: .destructive) {
                                    deleteTask(task)
                                }
                            }
                        }
                    }
                    
                    Spacer().frame(height: 12)
                }
            }
            .frame(maxHeight: 300) // Limit height if list is long
            
            // Footer
            Divider().opacity(0.3)
            HStack {
                Button {
                    NotificationCenter.default.post(name: .showCaptureMode, object: nil)
                } label: {
                    Label("Capture", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 280) // Slightly wider for comfort
    }

    private func deleteTask(_ task: TaskItem) {
        withAnimation {
            modelContext.delete(task)
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to delete task: \(error)")
        }
    }
}

// Remove NextEventHero struct as it is inlined now
