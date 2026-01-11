import SwiftUI
import SwiftData
import EventKit
import Combine

@main
struct MinuteApp: App {
    @StateObject private var calendarManager = CalendarManager()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Segment.self, Session.self, ActivityLabel.self, AppCategoryRule.self, Cluster.self, DomainRule.self, BrowserVisit.self, FocusGroup.self, Area.self, Project.self, TaskItem.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppLifecycleManager()
                .environmentObject(calendarManager)
        }
        .modelContainer(sharedModelContainer)
        
        MenuBarExtra {
            MenubarView()
                .environmentObject(calendarManager)
                .modelContainer(sharedModelContainer)
        } label: {
            MenubarLabel()
                .environmentObject(calendarManager)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenubarLabel: View {
    @EnvironmentObject var calendarManager: CalendarManager
    @State private var now = Date()
    
    // Timer to update every minute
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack {
            let next = calendarManager.events.first { $0.endDate > now }
            
            if let event = next {
                let isCurrent = event.startDate <= now
                // If active, count down to end. If upcoming, count down to start.
                let diff = isCurrent ? event.endDate.timeIntervalSince(now) : event.startDate.timeIntervalSince(now)
                
                let timeStr: String = {
                    let mins = Int(diff / 60)
                    if isCurrent {
                        return "\(mins)m left"
                    } else {
                        if mins < 60 { return "in \(mins)m" }
                        return "in \(mins / 60)h \(mins % 60)m"
                    }
                }()
                
                Text("\((event.title as String?) ?? "Event") • \(timeStr)")
            } else {
                Image(systemName: "clock")
            }
        }
        .onReceive(timer) { date in
            self.now = date
        }
        .onAppear {
            self.now = Date() // Initial sync
        }
    }
}
