//
//  FocusGroupService.swift
//  Minute
//
//  Real-time AI classification of sessions into focus groups
//

import Foundation
import SwiftData
import Combine

@MainActor
class FocusGroupService: ObservableObject {
    
    // Configuration
    private let apiKey: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    
    // State
    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: String?
    
    // Dependencies
    private let goalService = GoalService()
    
    init() {
        self.apiKey = UserDefaults.standard.string(forKey: "GeminiAPIKey") ?? ""
    }
    
    var hasAPIKey: Bool { !apiKey.isEmpty }
    
    /// Classify a session and assign to a project or focus group
    func classifySession(_ session: Session, modelContext: ModelContext) async {
        guard !session.isDeleted else { return }
        guard hasAPIKey else { return }
        
        // Skip if already assigned
        guard session.project == nil && session.focusGroup == nil else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            // Get active projects for context
            let activeProjects = goalService.getActiveProjects(modelContext: modelContext)
            
            // Build context for AI
            let context = buildSessionContext(session)
            
            // Call AI for classification
            let result = try await callAI(
                sessionContext: context, 
                projects: activeProjects, 
                activeTask: session.task
            )
            
            // Apply result
            if let projectIndex = result.projectIndex, projectIndex < activeProjects.count {
                // Matches an active project
                let project = activeProjects[projectIndex]
                session.project = project
                session.isGroupDistraction = result.isDistraction
                session.inferredTask = result.taskName
            } else {
                // Creates a new "Focus Group" (Fallback / Unsorted)
                // For now, we still create a FocusGroup for items that don't match a project
                let newGroup = FocusGroup(name: result.taskName, icon: result.icon)
                modelContext.insert(newGroup)
                session.focusGroup = newGroup
                session.isGroupDistraction = result.isDistraction
            }
            
            try? modelContext.save()
            
        } catch {
            lastError = error.localizedDescription
            // print("FocusGroupService: Error - \(error)")
        }
    }
    
    /// Build context string for AI classification
    private func buildSessionContext(_ session: Session) -> String {
        // Obscure browser app names to prevent bias (e.g. Dia -> Diagramming)
        let appName = session.activityType == .browser ? "Web Browser" : session.appName
        var context = "App: \(appName)"
        
        if let domain = session.browserDomain {
            context += "\nDomain: \(domain)"
        }
        
        if let title = session.browserTitle {
            context += "\nTitle: \(title)"
        }
        
        // Add Category hint (helps disambiguate misleading app names)
        // e.g. "Antigravity" (Category: Focused Work) -> Coding
        if session.activityType != .unknown && session.activityType != .meta {
            context += "\nCategory: \(session.activityType.rawValue)"
        }
        
        // Include rich context from browser visits
        if !session.browserVisits.isEmpty {
            let visits = session.browserVisits.prefix(3)
            for visit in visits {
                context += "\n- \(visit.domain)\(visit.path ?? "")"
                if let title = visit.title {
                    context += " \"\(title.prefix(50))\""
                }
                if let snippet = visit.contentSnippet {
                    context += " [\(snippet.prefix(100))...]"
                }
            }
        }
        
        return context
    }
    
    /// Call Gemini API for classification
    private func callAI(sessionContext: String, projects: [Project], activeTask: TaskItem?) async throws -> ClassificationResult {
        // Build project list for prompt
        var projectList = "None"
        if !projects.isEmpty {
            projectList = projects.enumerated().map { index, proj in
                return "\(index). \"\(proj.name)\" (Area: \(proj.area?.name ?? "General"))"
            }.joined(separator: ", ")
        }
        
        var prompt = ""
        
        if let task = activeTask {
            // Validation Mode
            prompt = """
            User is focusing on the task: "\(task.title)" (Project: \(task.project?.name ?? "General")).
            
            Current Activity:
            \(sessionContext)
            
            Step 1: Is this activity RELEVANT to the active task?
            Step 2: If NOT relevant, does it belong to a different Active Project?
            
            Reply with JSON: {"task":"Description of activity","icon":"sf.symbol","projectIndex":null,"isDistraction":boolean}
            
            Rules:
            - "projectIndex": The index of the *actual* project this activity belongs to.
              - If it matches the Active Task, use its project index.
              - If it matches a DIFFERENT project, use that project's index.
              - If it matches NO project, return null.
            - "isDistraction": true ONLY if the activity is generic unproductive time (e.g. social media, entertainment, unrelated browsing) that does NOT belong to any project.
              - If it is productive work for a DIFFERENT project, set isDistraction: false.
            - "task": Describe what the user is doing.
            """
        } else {
            // Classification Mode
            prompt = """
            Classify this computer activity into one of the user's active projects.
            
            Active Projects: \(projectList)
            
            Current activity:
            \(sessionContext)
            
            Reply with JSON: {"task":"Task Name","icon":"sf.symbol","projectIndex":null,"isDistraction":false}
            
            Rules:
            - "projectIndex": The index of the matching Active Project. If it clearly belongs to one, use its index. If it does not match ANY project, return null.
            - "task": Describe the specific action (e.g. "Debugging", "Writing Report"). If matched to a project, describe the sub-task.
            - "icon": An SF Symbol name (e.g. "hammer.fill", "doc.text")
            - "isDistraction": true ONLY for entertainment/social media not related to the project.
            - IF "Category" is "Focused Work" or "Coding", favor Development/Productivity tasks.
            """
        }
        
        let url = URL(string: "\(baseURL)?key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 1000
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ClassificationError.apiError
        }
        
        // Parse Gemini response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw ClassificationError.parseError
        }
        
        // print("FocusGroupService: Raw AI response: \(text)")
        
        // Extract JSON from response
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks safely
        if jsonString.contains("```") {
            let lines = jsonString.components(separatedBy: "\n")
            var codeLines: [String] = []
            var inBlock = false
            for line in lines {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    inBlock = !inBlock
                    continue
                }
                if inBlock {
                    codeLines.append(line)
                }
            }
            if !codeLines.isEmpty {
                jsonString = codeLines.joined(separator: "\n")
            }
        }
        
        // Find JSON object safely using NSRange
        if let startIndex = jsonString.firstIndex(of: "{"),
           let endIndex = jsonString.lastIndex(of: "}") {
            if startIndex <= endIndex {
                jsonString = String(jsonString[startIndex...endIndex])
            }
        }
        
        // print("FocusGroupService: Extracted JSON: \(jsonString)")
        
        guard let jsonData = jsonString.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let taskName = result["task"] as? String else {
            // print("FocusGroupService: Failed to parse JSON")
            throw ClassificationError.parseError
        }
        
        let projectIndex = result["projectIndex"] as? Int
        let isDistraction = result["isDistraction"] as? Bool ?? false
        let icon = result["icon"] as? String
        
        return ClassificationResult(
            taskName: taskName,
            icon: icon,
            projectIndex: projectIndex,
            isDistraction: isDistraction
        )
    }
    
    /// Predict the best project for a given user-entered task description
    func predictProject(task: String, projects: [Project]) async throws -> Project? {
        // Build project list for prompt
        var projectList = "None"
        if !projects.isEmpty {
            projectList = projects.enumerated().map { index, proj in
                return "\(index). \"\(proj.name)\" (Area: \(proj.area?.name ?? "General"))"
            }.joined(separator: ", ")
        }
        
        let prompt = """
        Match this new task to one of the user's active projects.
        
        Active Projects: \(projectList)
        
        New Task Description:
        "\(task)"
        
        Reply with JSON: {"projectIndex": int or null}
        
        Rules:
        - Return the index of the single best matching project.
        - If it's ambiguous or doesn't match any, return null.
        """
        
        let url = URL(string: "\(baseURL)?key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.1, // Low temperature for deterministic matching
                "maxOutputTokens": 100
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ClassificationError.apiError
        }
        
        // Parse Gemini response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw ClassificationError.parseError
        }
        
        // Extract JSON
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonString.contains("```") {
            jsonString = jsonString.components(separatedBy: "```").dropFirst().first?.components(separatedBy: "```").first ?? jsonString
            jsonString = jsonString.replacingOccurrences(of: "json", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard let jsonData = jsonString.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        
        if let idx = result["projectIndex"] as? Int, idx >= 0 && idx < projects.count {
            return projects[idx]
        }
        
        return nil
    }
    
    // MARK: - Types
    
    struct ClassificationResult {
        let taskName: String
        let icon: String?
        let projectIndex: Int?
        let isDistraction: Bool
    }
    
    enum ClassificationError: LocalizedError {
        case apiError
        case parseError
        
        var errorDescription: String? {
            switch self {
            case .apiError: return "API request failed"
            case .parseError: return "Failed to parse AI response"
            }
        }
    }
}
