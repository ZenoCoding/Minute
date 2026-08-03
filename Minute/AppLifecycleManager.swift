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
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject var calendarManager: CalendarManager
    @EnvironmentObject var quickComposerCoordinator: QuickComposerCoordinator
    @State private var isInitialized = false
    @State private var commandProcessor: MinuteCommandProcessor?
    
    var body: some View {
        OrbitView()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                }
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

                quickComposerCoordinator.start()
            }
    }
}
