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
    @State private var trackerService: TrackerService?
    @State private var selectedTab = 0
    @State private var isInitialized = false
    
    var body: some View {
        Group {
            if let tracker = trackerService {
                TabView(selection: $selectedTab) {
                    OrbitView() // The new "Goals" Dashboard
                        .tabItem {
                            Label("Dashboard", systemImage: "circle.hexagongrid.fill")
                        }
                        .tag(0)
                    
                    ScreenTimeView()
                        .tabItem {
                            Label("Screen Time", systemImage: "chart.bar.fill")
                        }
                        .tag(1)
                    
                    ClusterReviewView()
                        .tabItem {
                            Label("Focus Threads", systemImage: "arrow.triangle.branch")
                        }
                        .tag(2)
                    
                    TimerView()
                        .tabItem {
                            Label("Timer", systemImage: "timer")
                        }
                        .tag(3)
                    
                    SessionDebugView()
                        .tabItem {
                            Label("Debug", systemImage: "ant.fill")
                        }
                        .tag(5)
                    
                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .tag(4)
                }
                .environmentObject(tracker)
                .environmentObject(calendarManager)
            } else {
                ProgressView("Starting Minute...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard !isInitialized else { return }
            isInitialized = true
            
            let service = TrackerService(modelContext: modelContext)
            self.trackerService = service
            service.startTracking()
            
            // Check Habits
            let habitService = HabitService(modelContext: modelContext)
            habitService.checkAndResetHabits()
        }
    }
}
