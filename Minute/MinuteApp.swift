//
//  MinuteApp.swift
//  Minute
//
//  Created by Tycho Young on 1/2/26.
//

import SwiftUI
import SwiftData

@main
struct MinuteApp: App {
    var body: some Scene {
        WindowGroup {
            AppLifecycleManager()
        }
        .modelContainer(for: [Segment.self, Session.self, ActivityLabel.self, AppCategoryRule.self, Cluster.self, DomainRule.self, BrowserVisit.self, FocusGroup.self, Area.self, Project.self, TaskItem.self])
        
        MenuBarExtra("Minute", systemImage: "clock") {
            Button("Open Review") {
                NSApp.activate(ignoringOtherApps: true)
                // In a real agent app, we'd open the window here manually
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
