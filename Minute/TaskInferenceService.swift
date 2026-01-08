//
//  TaskInferenceService.swift
//  Minute
//
//  AI-powered task inference using Gemini API
//

import Foundation
import SwiftData
import Combine

@MainActor
class TaskInferenceService: ObservableObject {
    
    // Configuration
    private let apiKey: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    
    // State
    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastInferenceTime: Date?
    
    // Response Model
    struct InferenceResult: Codable {
        let taskId: String?
        let projectId: String?
        let label: String?
        let confidence: Double?
    }
    
    init() {
        // Load API key from UserDefaults or environment
        self.apiKey = UserDefaults.standard.string(forKey: "GeminiAPIKey") ?? ""
    }
    
    /// Set the API key
    func setAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "GeminiAPIKey")
    }
    
    /// Check if API key is configured
    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }
    
    /// Infer task labels for unlabeled sessions
    func inferTaskLabels(for sessions: [Session], modelContext: ModelContext) async {
        guard hasAPIKey else {
            lastError = "No API key configured"
            return
        }
        
        // Filter to sessions needing labels (unassigned task, project, and inferred label)
        let unlabeled = sessions.filter { $0.task == nil && $0.inferredTask == nil && $0.userTaskLabel == nil }
        guard !unlabeled.isEmpty else { return }
        
        isProcessing = true
        lastError = nil
        
        // Fetch Context (Active Tasks and Projects)
        let activeTasks = try? modelContext.fetch(FetchDescriptor<TaskItem>(
            predicate: #Predicate { !$0.isCompleted }
        ))
        
        let allProjects = try? modelContext.fetch(FetchDescriptor<Project>())
        let activeProjects = allProjects?.filter { $0.status == .active }
        
        defer { isProcessing = false }
        
        // Group sessions by similarity for batch inference
        // For now, process in batches of 10
        let batches = stride(from: 0, to: unlabeled.count, by: 10).map {
            Array(unlabeled[$0..<min($0 + 10, unlabeled.count)])
        }
        
        for batch in batches {
            do {
                let results = try await inferBatch(sessions: batch, tasks: activeTasks ?? [], projects: activeProjects ?? [])
                
                // Apply results to sessions
                for (session, result) in zip(batch, results) {
                    
                    // 1. Try Strict Task Link
                    if let taskIdStr = result.taskId,
                       let uuid = UUID(uuidString: taskIdStr),
                       let task = activeTasks?.first(where: { $0.id == uuid }) {
                        session.task = task
                        session.inferredTask = task.title // Fallback label
                    }
                    // 2. Try Project Categorization
                    else if let projectIdStr = result.projectId,
                            let uuid = UUID(uuidString: projectIdStr),
                            let project = activeProjects?.first(where: { $0.id == uuid }) {
                        session.project = project
                        session.inferredTask = result.label ?? project.name // Fallback label
                    }
                    // 3. Fallback Label
                    else {
                        session.inferredTask = result.label
                    }
                    
                    // Link confidence (default to 0.8 if AI returns nil)
                    session.confidence = result.confidence ?? 0.8
                    session.needsReview = false  // AI labeled
                }
                
                try? modelContext.save()
            } catch {
                lastError = error.localizedDescription
                // print("TaskInference: Error - \(error)")
            }
        }
        
        lastInferenceTime = Date()
    }
    
    /// Infer labels for a batch of sessions
    private func inferBatch(sessions: [Session], tasks: [TaskItem], projects: [Project]) async throws -> [InferenceResult] {
        // Build prompt with session context
        var sessionDescriptions: [String] = []
        
        for (index, session) in sessions.enumerated() {
            var desc = "\(index + 1). \(session.appName)"
            
            if session.activityType == .browser {
                // Include browser context
                if let domain = session.browserDomain {
                    desc += " - \(domain)"
                }
                
                // Include rich context from visits
                let visits = session.browserVisits.prefix(5)
                for visit in visits {
                    var visitDesc = "  - \(visit.domain)\(visit.path ?? "")"
                    if let title = visit.title {
                        visitDesc += " \"\(title.prefix(50))\""
                    }
                    if let snippet = visit.contentSnippet?.prefix(100) {
                        visitDesc += " [\(snippet)...]"
                    }
                    desc += "\n\(visitDesc)"
                }
            } else {
                // Non-browser app
                if let title = session.browserTitle {
                    desc += " - \(title)"
                }
            }
            
            sessionDescriptions.append(desc)
        }
        
        // Build Candidate Lists
        let taskList = tasks.map { "- [Task] ID: \($0.id.uuidString), Title: \($0.title), Project: \($0.project?.name ?? "None")" }.joined(separator: "\n")
        let projectList = projects.map { "- [Project] ID: \($0.id.uuidString), Name: \($0.name)" }.joined(separator: "\n")
        
        let prompt = """
        You are a productivity AI. Assign these work sessions to the correct Task or Project.
        
        Priority Logic:
        1. **Strict Match**: If a session clearly belongs to an active Task, output its `taskId`.
        2. **Category Match**: If no Task matches, but it belongs to a Project, output its `projectId`.
        3. **Fallback**: If neither, provide a short descriptive `label` (2-5 words).
        
        Active Tasks:
        \(taskList)
        
        Active Projects:
        \(projectList)
        
        Sessions to Classify:
        \(sessionDescriptions.joined(separator: "\n\n"))
        
        Respond with ONLY a JSON array of objects, one per session, in order:
        [
          { "taskId": "UUID" (or null), "projectId": "UUID" (or null), "label": "String", "confidence": 0.0-1.0 }
        ]
        """
        
        // Call Gemini API
        let response = try await callGemini(prompt: prompt)
        
        // Parse response
        let results = try parseResults(from: response, expectedCount: sessions.count)
        
        return results
    }
    
    /// Call Gemini API
    private func callGemini(prompt: String) async throws -> String {
        let url = URL(string: "\(baseURL)?key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 4000
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InferenceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw InferenceError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }
        
        // Parse Gemini response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw InferenceError.parseError
        }
        
        return text
    }
    
    /// Parse results from Gemini response
    private func parseResults(from response: String, expectedCount: Int) throws -> [InferenceResult] {
        // print("TaskInference: Raw response: \(response)")
        
        // Extract JSON array from response
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks if present
        if jsonString.contains("```") {
            let lines = jsonString.components(separatedBy: "\n")
            var inCodeBlock = false
            var codeLines: [String] = []
            for line in lines {
                if line.hasPrefix("```") {
                    inCodeBlock = !inCodeBlock
                    continue
                }
                if inCodeBlock {
                    codeLines.append(line)
                }
            }
            if !codeLines.isEmpty {
                jsonString = codeLines.joined(separator: "\n")
            }
        }
        
        // Find JSON array in response
        if let startRange = jsonString.range(of: "["),
           let endRange = jsonString.range(of: "]", options: .backwards) {
            jsonString = String(jsonString[startRange.lowerBound...endRange.upperBound])
        }
        
        // print("TaskInference: Extracted JSON: \(jsonString)")
        
        guard let data = jsonString.data(using: .utf8) else {
            throw InferenceError.parseError
        }
        
        do {
            let results = try JSONDecoder().decode([InferenceResult].self, from: data)
            // print("TaskInference: Parsed \(results.count) results")
            
            // Ensure we have the right number of labels
            if results.count < expectedCount {
                // Pad with empty results
                let dummy = InferenceResult(taskId: nil, projectId: nil, label: "Unknown", confidence: 0.0)
                return results + Array(repeating: dummy, count: expectedCount - results.count)
            }
            
            return Array(results.prefix(expectedCount))
        } catch {
            print("TaskInference: JSON Decode Error - \(error)")
            throw InferenceError.parseError
        }
    }
    
    // MARK: - Errors
    
    enum InferenceError: LocalizedError {
        case noAPIKey
        case invalidResponse
        case apiError(statusCode: Int, message: String)
        case parseError
        
        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No API key configured"
            case .invalidResponse: return "Invalid response from API"
            case .apiError(let code, let message): return "API error (\(code)): \(message)"
            case .parseError: return "Failed to parse response"
            }
        }
    }
}
