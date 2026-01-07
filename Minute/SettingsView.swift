//
//  SettingsView.swift
//  Minute
//
//  Settings panel with data management and configuration options
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allSessions: [Session]
    @Query private var allFocusGroups: [FocusGroup]
    
    @State private var showClearTodayConfirm = false
    @State private var showClearAllConfirm = false
    @State private var clearMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                
                dataManagementSection
                
                statsSection
                
                aboutSection
                
                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Header
    
    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.largeTitle.bold())
            Text("Manage your data and preferences")
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Data Management
    
    var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data Management")
                .font(.headline)
            
            VStack(spacing: 12) {
                // Clear Today
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear Today's Sessions")
                            .font(.body)
                        Text("Remove all sessions from today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Clear Today") {
                        showClearTodayConfirm = true
                    }
                    .buttonStyle(.bordered)
                    .confirmationDialog("Clear Today's Sessions?", isPresented: $showClearTodayConfirm) {
                        Button("Clear Today", role: .destructive) {
                            clearTodaySessions()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will delete all sessions from today. This cannot be undone.")
                    }
                }
                .padding()
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
                
                // Clear All
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear All Data")
                            .font(.body)
                        Text("Remove all sessions and start fresh")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Clear All") {
                        showClearAllConfirm = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .confirmationDialog("Clear All Data?", isPresented: $showClearAllConfirm) {
                        Button("Clear Everything", role: .destructive) {
                            clearAllSessions()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will delete ALL sessions. This cannot be undone.")
                    }
                }
                .padding()
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
            }
            
            if let message = clearMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Stats
    
    var statsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Statistics")
                .font(.headline)
            
            VStack(spacing: 12) {
                statRow("Total Sessions", value: "\(allSessions.count)")
                statRow("Today's Sessions", value: "\(todaySessionCount)")
                statRow("Storage Size", value: storageSize)
            }
            .padding()
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    var todaySessionCount: Int {
        let calendar = Calendar.current
        return allSessions.filter { calendar.isDateInToday($0.startTimestamp) }.count
    }
    
    var storageSize: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let storeURL = appSupport?.appendingPathComponent("default.store") else {
            return "Unknown"
        }
        
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: storeURL.path)
            if let size = attrs[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        } catch {
            return "—"
        }
        return "—"
    }
    
    func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
    
    // MARK: - About
    
    var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About")
                .font(.headline)
            
            VStack(spacing: 12) {
                statRow("Version", value: "0.2")
                statRow("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }
            .padding()
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    // MARK: - Actions
    
    func clearTodaySessions() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todaySessions = allSessions.filter { calendar.isDateInToday($0.startTimestamp) }
        let todayGroups = allFocusGroups.filter { $0.date >= today }
        
        for session in todaySessions {
            modelContext.delete(session)
        }
        
        for group in todayGroups {
            modelContext.delete(group)
        }
        
        try? modelContext.save()
        clearMessage = "Cleared \(todaySessions.count) sessions and \(todayGroups.count) focus groups"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            clearMessage = nil
        }
    }
    
    func clearAllSessions() {
        let sessionCount = allSessions.count
        let groupCount = allFocusGroups.count
        
        for session in allSessions {
            modelContext.delete(session)
        }
        
        for group in allFocusGroups {
            modelContext.delete(group)
        }
        
        try? modelContext.save()
        clearMessage = "Cleared \(sessionCount) sessions and \(groupCount) focus groups"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            clearMessage = nil
        }
    }
}

#Preview {
    SettingsView()
}
