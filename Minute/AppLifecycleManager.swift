//
//  AppLifecycleManager.swift
//  Minute
//
//  Created by Tycho Young on 1/2/26.
//

import SwiftUI
import SwiftData

struct AppLifecycleManager: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var calendarManager: CalendarManager
    @State private var isInitialized = false
    @State private var showSettings = false
    @State private var capturePanelController = CapturePanelController()
    @State private var commandProcessor: MinuteCommandProcessor?
    
    var body: some View {
        OrbitView()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .frame(width: 400, height: 500)
            }
            .environmentObject(calendarManager)
            .task {
                guard !isInitialized else { return }
                isInitialized = true

                let habitService = HabitService(modelContext: modelContext)
                habitService.checkAndResetHabits()

                let processor = MinuteCommandProcessor(modelContext: modelContext)
                processor.start()
                commandProcessor = processor

                ShortcutManager.shared.startMonitoring()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showCaptureMode)) { _ in
                capturePanelController.show(
                    modelContext: modelContext,
                    calendarManager: calendarManager
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleCaptureMode)) { _ in
                capturePanelController.toggle(
                    modelContext: modelContext,
                    calendarManager: calendarManager
                )
            }
    }
}

extension Notification.Name {
    static let showCaptureMode = Notification.Name("showCaptureMode")
    static let toggleCaptureMode = Notification.Name("toggleCaptureMode")
}
