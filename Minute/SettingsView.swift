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
    @Query private var allTasks: [TaskItem]
    @Query private var allProjects: [Project]
    @Query private var allAreas: [Area]
    
    @State private var showClearCompletedConfirm = false
    @State private var showClearAllConfirm = false
    @State private var clearMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                
                dataManagementSection
                
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
                // Clear Completed
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear Completed Tasks")
                            .font(.body)
                        Text("Remove all completed tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Clear Completed") {
                        showClearCompletedConfirm = true
                    }
                    .buttonStyle(.bordered)
                    .confirmationDialog("Clear completed tasks?", isPresented: $showClearCompletedConfirm) {
                        Button("Clear Completed", role: .destructive) {
                            clearCompletedTasks()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will delete all completed tasks. This cannot be undone.")
                    }
                }
                .padding()
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
                
                // Clear All
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear All Data")
                            .font(.body)
                        Text("Remove all areas, projects, and tasks")
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
                            clearAllData()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will delete ALL areas, projects, and tasks. This cannot be undone.")
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
                statRow("Storage Size", value: storageSize)
                statRow("Areas", value: "\(allAreas.count)")
                statRow("Projects", value: "\(allProjects.count)")
                statRow("Tasks", value: "\(allTasks.count)")
            }
            .padding()
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    // MARK: - Actions
    
    func clearCompletedTasks() {
        let completed = allTasks.filter { $0.isCompleted }
        for task in completed {
            modelContext.delete(task)
        }
        try? modelContext.save()
        clearMessage = "Cleared \(completed.count) completed tasks"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            clearMessage = nil
        }
    }
    
    func clearAllData() {
        let areaCount = allAreas.count
        let projectCount = allProjects.count
        let taskCount = allTasks.count
        
        for task in allTasks {
            modelContext.delete(task)
        }
        for project in allProjects {
            modelContext.delete(project)
        }
        for area in allAreas {
            modelContext.delete(area)
        }
        
        try? modelContext.save()
        clearMessage = "Cleared \(areaCount) areas, \(projectCount) projects, \(taskCount) tasks"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            clearMessage = nil
        }
    }
}

#Preview {
    SettingsView()
}
