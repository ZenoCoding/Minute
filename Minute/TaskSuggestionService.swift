import Foundation
import SwiftData

enum TaskSuggestionStatus {
    static let pending = "pending"
    static let accepted = "accepted"
    static let dismissed = "dismissed"
}

struct TaskSuggestionInput: Codable {
    let fingerprint: String
    let title: String
    let sourceType: String
    let sourceLabel: String?
    let sourceURL: String?
    let evidenceSnippet: String?
    let reason: String?
    let project: String?
    let dueDate: String?
    let confidence: Double?
    let rank: Int?
}

@MainActor
final class TaskSuggestionService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func importSuggestions(
        _ inputs: [TaskSuggestionInput],
        sourceRequestID: String
    ) throws -> [TaskSuggestion] {
        let existing = try modelContext.fetch(FetchDescriptor<TaskSuggestion>())
        var byFingerprint = Dictionary(uniqueKeysWithValues: existing.map { ($0.fingerprint, $0) })
        var imported: [TaskSuggestion] = []

        for input in inputs.prefix(50) {
            let fingerprint = input.fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fingerprint.isEmpty, !title.isEmpty else { continue }

            if let suggestion = byFingerprint[fingerprint] {
                // Accepted and dismissed suggestions stay terminal so daily refreshes
                // cannot resurrect work the user already handled.
                guard suggestion.status == TaskSuggestionStatus.pending else { continue }
                apply(input, to: suggestion, sourceRequestID: sourceRequestID)
                imported.append(suggestion)
            } else {
                let suggestion = TaskSuggestion(
                    fingerprint: fingerprint,
                    title: title,
                    sourceType: normalizedSource(input.sourceType),
                    sourceLabel: clean(input.sourceLabel) ?? defaultLabel(for: input.sourceType),
                    sourceURL: clean(input.sourceURL),
                    evidenceSnippet: clean(input.evidenceSnippet),
                    reason: clean(input.reason),
                    inferredProjectName: clean(input.project),
                    dueDate: try input.dueDate.map(parseDate),
                    confidence: min(max(input.confidence ?? 0, 0), 1),
                    rank: input.rank ?? imported.count,
                    sourceRequestID: sourceRequestID
                )
                modelContext.insert(suggestion)
                byFingerprint[fingerprint] = suggestion
                imported.append(suggestion)
            }
        }

        try modelContext.save()
        return imported
    }

    func accept(_ suggestion: TaskSuggestion) throws -> TaskItem {
        if let acceptedTaskID = suggestion.acceptedTaskID,
           let existing = try task(id: acceptedTaskID) {
            return existing
        }

        let dataService = MinuteDataService(modelContext: modelContext)
        let project = try suggestion.inferredProjectName.flatMap { try dataService.findProject(named: $0) }
        let task = try dataService.createTask(
            title: suggestion.title,
            project: project,
            dueDate: suggestion.dueDate,
            sourceRequestID: "suggestion:\(suggestion.fingerprint)"
        )
        suggestion.status = TaskSuggestionStatus.accepted
        suggestion.acceptedTaskID = task.id
        try dataService.save()
        return task
    }

    func markAccepted(_ suggestion: TaskSuggestion, task: TaskItem) throws {
        suggestion.status = TaskSuggestionStatus.accepted
        suggestion.acceptedTaskID = task.id
        if task.sourceRequestID == nil {
            task.sourceRequestID = "suggestion:\(suggestion.fingerprint)"
        }
        try modelContext.save()
    }

    func dismiss(_ suggestion: TaskSuggestion) throws {
        suggestion.status = TaskSuggestionStatus.dismissed
        try modelContext.save()
    }

    func resolve(_ identifier: String) throws -> TaskSuggestion {
        let suggestions = try modelContext.fetch(FetchDescriptor<TaskSuggestion>())
        if let id = UUID(uuidString: identifier), let match = suggestions.first(where: { $0.id == id }) {
            return match
        }
        if let match = suggestions.first(where: { $0.fingerprint == identifier }) {
            return match
        }
        throw MinuteDataError.entityNotFound("Suggestion", identifier)
    }

    private func apply(
        _ input: TaskSuggestionInput,
        to suggestion: TaskSuggestion,
        sourceRequestID: String
    ) {
        suggestion.title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestion.sourceType = normalizedSource(input.sourceType)
        suggestion.sourceLabel = clean(input.sourceLabel) ?? defaultLabel(for: input.sourceType)
        suggestion.sourceURL = clean(input.sourceURL)
        suggestion.evidenceSnippet = clean(input.evidenceSnippet)
        suggestion.reason = clean(input.reason)
        suggestion.inferredProjectName = clean(input.project)
        if let dueDate = input.dueDate {
            suggestion.dueDate = try? parseDate(dueDate)
        } else {
            suggestion.dueDate = nil
        }
        suggestion.confidence = min(max(input.confidence ?? 0, 0), 1)
        suggestion.rank = input.rank ?? suggestion.rank
        suggestion.generatedAt = Date()
        suggestion.sourceRequestID = sourceRequestID
    }

    private func task(id: UUID) throws -> TaskItem? {
        try modelContext.fetch(FetchDescriptor<TaskItem>()).first { $0.id == id }
    }

    private func normalizedSource(_ value: String) -> String {
        let value = value.lowercased()
        return ["gmail", "calendar", "drive", "idea"].contains(value) ? value : "idea"
    }

    private func defaultLabel(for source: String) -> String {
        switch normalizedSource(source) {
        case "gmail": return "Gmail"
        case "calendar": return "Calendar"
        case "drive": return "Drive"
        default: return "Idea"
        }
    }

    private func clean(_ value: String?) -> String? {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned?.isEmpty == false ? cleaned : nil
    }

    private func parseDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date }
        throw MinuteCommandAPIError.invalidDate(value)
    }
}
