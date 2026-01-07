//
//  GoalService.swift
//  Minute
//
//  Manages lifecycle of Life Areas, Projects, and Tasks
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
class GoalService {
    
    // Create Default Areas if none exist
    func seedDefaultAreas(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Area>()
        if (try? modelContext.fetch(descriptor).count) == 0 {
            let defaults: [(String, String, String)] = [
                ("Work", "007AFF", "briefcase.fill"),
                ("Personal", "34C759", "person.fill"),
                ("Learning", "AF52DE", "book.fill"),
                ("Life Admin", "8E8E93", "house.fill")
            ]
            
            for (name, color, icon) in defaults {
                let area = Area(name: name, themeColor: color, iconName: icon)
                modelContext.insert(area)
            }
            try? modelContext.save()
        }
    }
    
    // Create a new project
    func createProject(name: String, area: Area, modelContext: ModelContext) -> Project {
        let project = Project(name: name, area: area)
        modelContext.insert(project)
        try? modelContext.save()
        return project
    }
    
    // Archive a project
    func archiveProject(_ project: Project, modelContext: ModelContext) {
        project.status = .archived
        try? modelContext.save()
    }
    
    // Get active projects for AI Context
    func getActiveProjects(modelContext: ModelContext) -> [Project] {
        let active = ProjectStatus.active
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.status == active }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
