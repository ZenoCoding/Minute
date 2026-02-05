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
    @State private var showCaptureMode = false
    @State private var showSettings = false
    
    var body: some View {
        ZStack {
            // Main app content
            Group {
                if let tracker = trackerService {
                    TabView(selection: $selectedTab) {
                        OrbitView()
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
                    }
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
                    .environmentObject(tracker)
                    .environmentObject(calendarManager)
                } else {
                    ProgressView("Starting Minute...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            
            // Full-screen capture overlay
            if showCaptureMode {
                FullScreenCaptureView(isPresented: $showCaptureMode)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showCaptureMode)
        .task {
            guard !isInitialized else { return }
            isInitialized = true
            
            let service = TrackerService(modelContext: modelContext)
            self.trackerService = service
            service.startTracking()
            
            let habitService = HabitService(modelContext: modelContext)
            habitService.checkAndResetHabits()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCaptureMode)) { _ in
            showCaptureMode = true
        }
    }
}

extension Notification.Name {
    static let showCaptureMode = Notification.Name("showCaptureMode")
}
