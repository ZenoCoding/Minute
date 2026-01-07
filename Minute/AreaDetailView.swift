//
//  AreaDetailView.swift
//  Minute
//
//  Created by Tycho Young on 1/5/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AreaDetailView: View {
    let area: Area
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingNewProject = false
    @State private var showingEditArea = false
    
    var themeColor: Color {
        Color(hex: area.themeColor) ?? .blue
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // Header
                HStack(spacing: 16) {
                    // Back Button
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .background(Color.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Image(systemName: area.iconName)
                        .font(.system(size: 48))
                        .foregroundStyle(themeColor)
                        .frame(width: 80, height: 80)
                        .background(themeColor.opacity(0.1), in: Circle())
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(area.name)
                            .font(.system(size: 32, weight: .bold))
                        
                        Text("\(area.projects.count) Projects")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    
                    Spacer()
                    
                    Button("Edit Area") {
                        showingEditArea = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(.bottom, 8)
                
                // Projects Grid
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Active Projects")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Button(action: { showingNewProject = true }) {
                            Label("New Project", systemImage: "plus")
                        }
                    }
                    



                    let activeProjects = area.projects.filter { $0.status == .active }
                    
                    if activeProjects.isEmpty {
                        ContentUnavailableView {
                            Label("No Active Projects", systemImage: "tray")
                        } description: {
                            Text("Create a project to start tracking your progress.")
                        } actions: {
                            Button("Create Project") { showingNewProject = true }
                        }
                        .frame(height: 200)
                        .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                            ForEach(orderedProjects) { project in
                                ProjectDetailCard(project: project, themeColor: themeColor)
                                    .opacity(draggedProject?.id == project.id ? 0.0 : 1.0)
                                    .onDrag {
                                        self.draggedProject = project
                                        return NSItemProvider(object: project.id.uuidString as NSString)
                                    } preview: {
                                        ProjectDetailCard(project: project, themeColor: themeColor)
                                            .frame(width: 300)
                                            .background(Color(nsColor: .windowBackgroundColor))
                                            .cornerRadius(12)
                                    }
                                    .onDrop(of: [.text], delegate: ProjectDropDelegate(item: project, items: $orderedProjects, draggedItem: $draggedProject, modelContext: modelContext))
                            }
                        }
                        .onAppear {
                            // Sync orderedProjects with area projects
                            if orderedProjects.isEmpty {
                                orderedProjects = area.projects.filter { $0.status == .active }.sorted { $0.orderIndex < $1.orderIndex }
                            } else {
                                // Basic sync logic - refactor to shared extension later
                                let active = area.projects.filter { $0.status == .active }
                                let currentIDs = Set(orderedProjects.map { $0.id })
                                let newItems = active.filter { !currentIDs.contains($0.id) }
                                if !newItems.isEmpty {
                                    orderedProjects.append(contentsOf: newItems)
                                }
                                let existIDs = Set(active.map { $0.id })
                                orderedProjects.removeAll { !existIDs.contains($0.id) }
                            }
                        }
                        .onChange(of: area.projects) { _, _ in
                            // Re-sync
                             let active = area.projects.filter { $0.status == .active }
                             let currentIDs = Set(orderedProjects.map { $0.id })
                             let newItems = active.filter { !currentIDs.contains($0.id) }
                             if !newItems.isEmpty {
                                 orderedProjects.append(contentsOf: newItems)
                             }
                             let existIDs = Set(active.map { $0.id })
                             orderedProjects.removeAll { !existIDs.contains($0.id) }
                        }
                    }
                    
                    // Completed / Archived could go here
                    let archivedProjects = area.projects.filter { $0.status != .active }
                    if !archivedProjects.isEmpty {
                         Text("Archived")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top, 24)
                        
                        ForEach(archivedProjects) { project in
                            HStack {
                                Text(project.name)
                                    .strikethrough()
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(project.status.rawValue.capitalized)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.1), in: Capsule())
                            }
                            .padding()
                            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .padding(32)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(area.name)
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet(area: area)
        }
        .sheet(isPresented: $showingEditArea) {
            EditAreaSheet(area: area)
        }
    }
    
    @State private var orderedProjects: [Project] = []
    @State private var draggedProject: Project?

    // ... existing body ...
}

struct ProjectDropDelegate: DropDelegate {
    let item: Project
    @Binding var items: [Project]
    @Binding var draggedItem: Project?
    let modelContext: ModelContext
    
    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem else { return }
        
        if draggedItem != item {
            if let from = items.firstIndex(of: draggedItem),
               let to = items.firstIndex(of: item) {
                withAnimation(.default) {
                    items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        for (index, project) in items.enumerated() {
            project.orderIndex = index
        }
        try? modelContext.save()
        self.draggedItem = nil
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

struct ProjectDetailCard: View {
    let project: Project
    let themeColor: Color
    
    // Computed property for progress simulation
    // Real implementation would calculate this from project.sessions
    var timeTracked: TimeInterval {
        project.sessions.reduce(0) { $0 + $1.duration }
    }
    
    var goal: TimeInterval? {
        project.weeklyGoalSeconds
    }
    
    var progress: Double {
        guard let goal = goal, goal > 0 else { return 0 }
        return min(timeTracked / goal, 1.0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal") // Or 6 dots custom symbol if available
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle()) // Make it easier to grab
                        
                        Text(project.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    
                    Text("\(project.tasks.filter { !$0.isCompleted }.count) active · \(project.tasks.filter { $0.isCompleted }.count) completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Menu {
                    Button("Edit Project") { } // Placeholder
                    Button("Archive", role: .destructive) {
                        project.status = .archived
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .foregroundStyle(.secondary)
            }
            
            if let goal = goal {
                 VStack(spacing: 6) {
                    ProgressView(value: progress)
                        .tint(themeColor)
                    
                    HStack {
                        Text(formatDuration(timeTracked))
                        Spacer()
                        Text("Goal: \(formatDuration(goal))")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            } else {
                HStack {
                    Image(systemName: "clock")
                    Text(formatDuration(timeTracked))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
