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
        
        // Filter to sessions needing labels
        let unlabeled = sessions.filter { $0.inferredTask == nil && $0.userTaskLabel == nil }
        guard !unlabeled.isEmpty else { return }
        
        isProcessing = true
        lastError = nil
        
        defer { isProcessing = false }
        
        // Group sessions by similarity for batch inference
        // For now, process in batches of 10
        let batches = stride(from: 0, to: unlabeled.count, by: 10).map {
            Array(unlabeled[$0..<min($0 + 10, unlabeled.count)])
        }
        
        for batch in batches {
            do {
                let labels = try await inferBatch(sessions: batch)
                
                // Apply labels to sessions
                for (session, label) in zip(batch, labels) {
                    session.inferredTask = label
                    session.needsReview = false  // AI labeled
                }
                
                try? modelContext.save()
            } catch {
                lastError = error.localizedDescription
                print("TaskInference: Error - \(error)")
            }
        }
        
        lastInferenceTime = Date()
    }
    
    /// Infer labels for a batch of sessions
    private func inferBatch(sessions: [Session]) async throws -> [String] {
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
        
        let prompt = """
        You are a productivity assistant. Based on the following app usage sessions, infer what task the user was working on.
        
        For each session, provide a short task label (2-5 words) that describes the activity.
        Examples: "iOS Development", "Research", "Email", "Video Watching", "Documentation", "Code Review", "Shopping", "Social Media"
        
        Sessions:
        \(sessionDescriptions.joined(separator: "\n\n"))
        
        Respond with ONLY a JSON array of task labels, one per session, in the same order:
        ["label1", "label2", ...]
        """
        
        // Call Gemini API
        let response = try await callGemini(prompt: prompt)
        
        // Parse response
        let labels = try parseLabels(from: response, expectedCount: sessions.count)
        
        return labels
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
                "temperature": 0.3,
                "maxOutputTokens": 2000
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
    
    /// Parse task labels from Gemini response
    private func parseLabels(from response: String, expectedCount: Int) throws -> [String] {
        print("TaskInference: Raw response: \(response)")
        
        // Extract JSON array from response
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks if present
        if jsonString.contains("```") {
            // Extract content between ``` markers
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
        
        print("TaskInference: Extracted JSON: \(jsonString)")
        
        guard let data = jsonString.data(using: .utf8),
              let labels = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            print("TaskInference: Failed to parse as [String]")
            throw InferenceError.parseError
        }
        
        print("TaskInference: Parsed \(labels.count) labels: \(labels)")
        
        // Ensure we have the right number of labels
        if labels.count < expectedCount {
            // Pad with "Unknown"
            return labels + Array(repeating: "Unknown", count: expectedCount - labels.count)
        }
        
        return Array(labels.prefix(expectedCount))
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
