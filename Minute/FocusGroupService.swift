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
    
    // Cache of today's focus groups for quick lookup
    private var todayGroups: [FocusGroup] = []
    private var todayDate: Date = Date()
    
    init() {
        self.apiKey = UserDefaults.standard.string(forKey: "GeminiAPIKey") ?? ""
    }
    
    var hasAPIKey: Bool { !apiKey.isEmpty }
    
    /// Classify a session and assign to a focus group
    func classifySession(_ session: Session, modelContext: ModelContext) async {
        guard hasAPIKey else {
            print("FocusGroupService: No API key configured")
            return
        }
        
        // Skip if already assigned
        guard session.focusGroup == nil else { return }
        
        // Refresh today's groups if needed
        await refreshTodayGroups(modelContext: modelContext)
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            // Build context for AI
            let context = buildSessionContext(session)
            
            // Call AI for classification
            let result = try await callAI(sessionContext: context, existingGroups: todayGroups)
            
            print("FocusGroupService: AI result - task: \(result.taskName), existing: \(result.existingGroupIndex ?? -1), distraction: \(result.isDistraction)")
            
            // Apply result
            if let existingIndex = result.existingGroupIndex, existingIndex < todayGroups.count {
                // Assign to existing group
                let group = todayGroups[existingIndex]
                session.focusGroup = group
                session.isGroupDistraction = result.isDistraction
                group.lastActiveAt = Date()
                group.sessions.append(session)
            } else {
                // Create new group
                let newGroup = FocusGroup(name: result.taskName)
                modelContext.insert(newGroup)
                session.focusGroup = newGroup
                session.isGroupDistraction = result.isDistraction
                newGroup.sessions.append(session)
                todayGroups.append(newGroup)
            }
            
            try? modelContext.save()
            
        } catch {
            lastError = error.localizedDescription
            print("FocusGroupService: Error - \(error)")
        }
    }
    
    /// Refresh cache of today's groups
    private func refreshTodayGroups(modelContext: ModelContext) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Only refresh if date changed or cache is empty
        if calendar.isDate(todayDate, inSameDayAs: today) && !todayGroups.isEmpty {
            return
        }
        
        todayDate = today
        
        let descriptor = FetchDescriptor<FocusGroup>(
            predicate: #Predicate { $0.date >= today },
            sortBy: [SortDescriptor(\.lastActiveAt, order: .reverse)]
        )
        
        do {
            todayGroups = try modelContext.fetch(descriptor)
        } catch {
            print("FocusGroupService: Failed to fetch groups - \(error)")
            todayGroups = []
        }
    }
    
    /// Build context string for AI classification
    private func buildSessionContext(_ session: Session) -> String {
        var context = "App: \(session.appName)"
        
        if let domain = session.browserDomain {
            context += "\nDomain: \(domain)"
        }
        
        if let title = session.browserTitle {
            context += "\nTitle: \(title)"
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
    private func callAI(sessionContext: String, existingGroups: [FocusGroup]) async throws -> ClassificationResult {
        // Build group list for prompt
        var groupList = "None"
        if !existingGroups.isEmpty {
            groupList = existingGroups.enumerated().map { index, group in
                let ago = Int(Date().timeIntervalSince(group.lastActiveAt) / 60)
                return "\(index). \"\(group.name)\""
            }.joined(separator: ", ")
        }
        
        let prompt = """
        Classify this computer activity into a task/focus group.
        
        Existing groups today: \(groupList)
        
        Current activity:
        \(sessionContext)
        
        Reply with JSON: {"task":"Task Name","existingGroup":null,"isDistraction":false}
        
        Rules:
        - "task": Describe WHAT the user is doing (e.g., "Physics Homework", "iOS Development", "Email"), NOT the app name
        - "existingGroup": index number if this matches an existing group, null if it's a new task
        - "isDistraction": true ONLY for entertainment (YouTube, Reddit, Twitter, TikTok, games)
        - For browsers, use the website content/domain to determine the task, not the browser name
        """
        
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
        
        print("FocusGroupService: Raw AI response: \(text)")
        
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
        
        print("FocusGroupService: Extracted JSON: \(jsonString)")
        
        guard let jsonData = jsonString.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let taskName = result["task"] as? String else {
            print("FocusGroupService: Failed to parse JSON")
            throw ClassificationError.parseError
        }
        
        let existingIndex = result["existingGroup"] as? Int
        let isDistraction = result["isDistraction"] as? Bool ?? false
        
        return ClassificationResult(
            taskName: taskName,
            existingGroupIndex: existingIndex,
            isDistraction: isDistraction
        )
    }
    
    // MARK: - Types
    
    struct ClassificationResult {
        let taskName: String
        let existingGroupIndex: Int?
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
