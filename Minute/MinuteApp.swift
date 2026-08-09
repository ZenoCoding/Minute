import SwiftUI
import SwiftData
import EventKit
import Combine

enum MinuteStoreLocation {
    static func resolvedURL(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        // An explicit absolute store path is reserved for migration and UI
        // verification against disposable copies. Normal launches never set it
        // and continue to use the canonical sandbox store below.
        if let overridePath = environment["MINUTE_STORE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           overridePath.hasPrefix("/") {
            return URL(fileURLWithPath: overridePath, isDirectory: false)
        }

        let defaultURL = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("default.store")

        // Sandboxed builds already resolve Application Support inside Minute's
        // container. Local iteration builds intentionally disable App Sandbox
        // so they can launch the Codex CLI; point those builds back at the same
        // store instead of silently creating an empty database in ~/Library.
        guard environment["APP_SANDBOX_CONTAINER_ID"] == nil else {
            return defaultURL
        }

        let sandboxStoreURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.tychoyoung.Minute/Data/Library/Application Support")
            .appendingPathComponent("default.store")

        return fileManager.fileExists(atPath: sandboxStoreURL.path)
            ? sandboxStoreURL
            : defaultURL
    }
}

@main
struct MinuteApp: App {
    @StateObject private var calendarManager: CalendarManager
    @StateObject private var quickComposerCoordinator: QuickComposerCoordinator
    
    let sharedModelContainer: ModelContainer

    init() {
        let environment = ProcessInfo.processInfo.environment
        let isRunningTests = environment["XCTestConfigurationFilePath"] != nil
        let isSandboxed = environment["APP_SANDBOX_CONTAINER_ID"] != nil
        let isCloudKitDisabled = environment["MINUTE_DISABLE_CLOUDKIT"] == "1"
        let modelConfiguration: MinuteModelContainerConfiguration
        if isRunningTests {
            modelConfiguration = .inMemory
        } else if !isSandboxed || isCloudKitDisabled {
            // Unsandboxed local/CLI builds cannot carry the production iCloud
            // entitlement. Keep them on the same explicit local store URL.
            modelConfiguration = .local(url: MinuteStoreLocation.resolvedURL())
        } else {
            modelConfiguration = .privateCloudKit(
                containerIdentifier: MinuteCloudKit.containerIdentifier,
                storeURL: MinuteStoreLocation.resolvedURL()
            )
        }

        do {
            let modelContainer = try MinuteModelContainerFactory.makeContainer(
                configuration: modelConfiguration
            )
            let calendarManager = CalendarManager()

            sharedModelContainer = modelContainer
            _calendarManager = StateObject(wrappedValue: calendarManager)
            _quickComposerCoordinator = StateObject(
                wrappedValue: QuickComposerCoordinator(
                    modelContext: modelContainer.mainContext,
                    calendarManager: calendarManager
                )
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppLifecycleManager()
                .environmentObject(calendarManager)
                .environmentObject(quickComposerCoordinator)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            // Add Capture Mode command to File menu
            CommandGroup(after: .newItem) {
                Button("Capture Mode") {
                    quickComposerCoordinator.show()
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            }
        }

        // Declaring a Settings scene gives the app its standard Settings menu
        // item and Command-comma shortcut on macOS.
        Settings {
            SettingsView()
                .environmentObject(calendarManager)
                .modelContainer(sharedModelContainer)
        }
        
        MenuBarExtra {
            MenubarView()
                .environmentObject(calendarManager)
                .environmentObject(quickComposerCoordinator)
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
