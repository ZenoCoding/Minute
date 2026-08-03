//
//  SmartInputParser.swift
//  Minute
//
//  Helper to extract structured data (Project, Duration) from natural language input.
//

import Foundation
import NaturalLanguage

struct ProjectInferenceMemory {
    struct Example: Codable, Equatable {
        let signature: String
        let projectName: String
        let updatedAt: Date
    }

    static let storageKey = "projectInferenceCorrectionExamples"
    private static let maximumExamples = 200
    private static let ignoredWords: Set<String> = [
        "and", "the", "for", "with", "from", "into", "this", "that",
        "task", "work", "finish", "start", "make", "update", "review",
        "write", "draft", "do", "complete", "on", "at", "to", "of"
    ]

    static func record(
        text: String,
        projectName: String,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        let signature = signature(for: text)
        let cleanProjectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !signature.isEmpty, !cleanProjectName.isEmpty else { return }

        var examples = load(defaults: defaults)
        examples.removeAll { $0.signature == signature }
        examples.insert(
            Example(signature: signature, projectName: cleanProjectName, updatedAt: now),
            at: 0
        )
        if examples.count > maximumExamples {
            examples.removeLast(examples.count - maximumExamples)
        }
        if let data = try? JSONEncoder().encode(examples) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static func inferredProjectName(
        for text: String,
        candidateNames: [String],
        defaults: UserDefaults = .standard
    ) -> String? {
        bestMatch(
            for: text,
            examples: load(defaults: defaults),
            candidateNames: candidateNames
        )
    }

    static func bestMatch(
        for text: String,
        examples: [Example],
        candidateNames: [String]
    ) -> String? {
        let inputSignature = signature(for: text)
        guard !inputSignature.isEmpty else { return nil }

        let validNames = Dictionary(uniqueKeysWithValues: candidateNames.map {
            ($0.lowercased(), $0)
        })
        let inputTokens = Set(inputSignature.split(separator: " ").map(String.init))
        var best: (projectName: String, score: Double, date: Date)?

        for example in examples {
            guard let validName = validNames[example.projectName.lowercased()] else { continue }
            let exampleTokens = Set(example.signature.split(separator: " ").map(String.init))
            let unionCount = inputTokens.union(exampleTokens).count
            guard unionCount > 0 else { continue }
            let score = Double(inputTokens.intersection(exampleTokens).count) / Double(unionCount)
            guard score >= 0.72 else { continue }

            if score > (best?.score ?? -1) ||
                (score == best?.score && example.updatedAt > (best?.date ?? .distantPast)) {
                best = (validName, score, example.updatedAt)
            }
        }

        return best?.projectName
    }

    private static func load(defaults: UserDefaults) -> [Example] {
        guard let data = defaults.data(forKey: storageKey),
              let examples = try? JSONDecoder().decode([Example].self, from: data) else {
            return []
        }
        return examples
    }

    private static func signature(for text: String) -> String {
        text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { token in
                token.count >= 2 && !ignoredWords.contains(token) && Int(token) == nil
            }
            .joined(separator: " ")
    }
}

struct SmartInputParser {

    enum EntryType: String, Sendable {
        case task
        case event
    }
    
    struct Result {
        let cleanTitle: String
        let project: Project?
        let duration: TimeInterval?
        let date: Date?
        let dateHasExplicitTime: Bool
        let isRecurring: Bool
        let recurrenceInterval: String?
        let entryType: EntryType

        var isEvent: Bool {
            entryType == .event
        }
    }

    struct ComposerResult: Sendable {
        let cleanTitle: String
        let projectName: String?
        let duration: TimeInterval?
        let date: Date?
        let dateHasExplicitTime: Bool
        let recurrenceInterval: String?
        let entryType: EntryType

        var isEvent: Bool {
            entryType == .event
        }
    }

    struct ProjectCandidate: Sendable {
        let name: String
        let hints: [String]

        init(name: String, hints: [String] = []) {
            self.name = name
            self.hints = hints
        }
    }

    private struct CoreResult: Sendable {
        let cleanTitle: String
        let projectName: String?
        let duration: TimeInterval?
        let date: Date?
        let dateHasExplicitTime: Bool
        let recurrenceInterval: String?
        let entryType: EntryType
    }

    // Cache expensive resources used across parses.
    private static let englishEmbedding = NLEmbedding.wordEmbedding(for: .english)
    private static let durationRegex = try? NSRegularExpression(
        pattern: #"(\b\d+(?:\.\d+)?)\s*(h(?:ours?|rs?)?|m(?:in(?:utes?)?s?)?)\b"#,
        options: .caseInsensitive
    )
    private static let dateDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
    )
    private static let dayOfMonthRegex = try? NSRegularExpression(
        pattern: #"\b(\d+)(?:st|nd|rd|th)\b"#,
        options: .caseInsensitive
    )
    private static let eventMarkerRegex = try? NSRegularExpression(
        pattern: #"(?i)(?:^\s*(?:event|evt|calendar|cal)\s*:?\s*)|(?:\s+(?:event|evt|calendar|cal)\s*:?\s*$)"#,
        options: []
    )
    private static let explicitTimeRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(?:(?:1[0-2]|[1-9])(?::[0-5]\d)?\s?[ap]m|(?:[01]?\d|2[0-3]):[0-5]\d|noon|midnight|tonight)\b"#,
        options: []
    )
    private static let projectStopWords: Set<String> = [
        "and", "the", "for", "with", "from", "into", "this", "that",
        "task", "work", "finish", "start", "make", "update", "review"
    ]
    
    /// Parses the raw input text to find a matching project and duration.
    /// - Parameters:
    ///   - text: The raw input string (e.g. "Draft report for Marketing 2h")
    ///   - projects: List of candidate projects.
    /// - Returns: A Result containing the inferred project, duration, and the "clean" title (optional).
    static func parse(text: String, projects: [Project]) -> Result {
        let candidates = projects.map { ProjectCandidate(name: $0.name) }
        let core = parseCore(text: text, projectCandidates: candidates)
        let matchedProject = core.projectName.flatMap { name in
            projects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }

        return Result(
            cleanTitle: core.cleanTitle,
            project: matchedProject,
            duration: core.duration,
            date: core.date,
            dateHasExplicitTime: core.dateHasExplicitTime,
            isRecurring: core.recurrenceInterval != nil,
            recurrenceInterval: core.recurrenceInterval,
            entryType: core.entryType
        )
    }

    static func parseForComposer(text: String, projectNames: [String]) -> ComposerResult {
        let candidates = projectNames.map { ProjectCandidate(name: $0) }
        return parseForComposer(text: text, projectCandidates: candidates)
    }

    static func parseForComposer(text: String, projectCandidates: [ProjectCandidate]) -> ComposerResult {
        let core = parseCore(text: text, projectCandidates: projectCandidates)
        return ComposerResult(
            cleanTitle: core.cleanTitle,
            projectName: core.projectName,
            duration: core.duration,
            date: core.date,
            dateHasExplicitTime: core.dateHasExplicitTime,
            recurrenceInterval: core.recurrenceInterval,
            entryType: core.entryType
        )
    }

    private static func parseCore(text: String, projectCandidates: [ProjectCandidate]) -> CoreResult {
        var remainingText = text
        var foundProjectName: String?
        var foundDuration: TimeInterval?
        var foundEntryType: EntryType = .task
        var foundDateHasExplicitTime = false
        
        if let eventRegex = eventMarkerRegex {
            let matches = eventRegex.matches(
                in: remainingText,
                range: NSRange(remainingText.startIndex..., in: remainingText)
            )
            if !matches.isEmpty {
                foundEntryType = .event
                for match in matches.reversed() {
                    if let range = Range(match.range, in: remainingText) {
                        remainingText.removeSubrange(range)
                    }
                }
                remainingText = cleanWhitespace(remainingText)
            }
        }
        
        let lowerText = remainingText.lowercased()
        
        // 0. Prepare Candidates
        let sortedCandidates = projectCandidates.sorted { $0.name.count > $1.name.count }
        
        // 1. Exact Substring Match (Highest Confidence)
        // "Update Marketing stats" -> Matches "Marketing"
        if foundProjectName == nil {
            for candidate in sortedCandidates {
                if containsTokenSequence(candidate.name, in: lowerText) {
                    foundProjectName = candidate.name
                    break
                }
            }
        }

        // 1.5. Corrections made during ordinary use become durable local examples.
        // This keeps familiar phrases off the LLM path after the user has taught Minute once.
        if foundProjectName == nil {
            foundProjectName = ProjectInferenceMemory.inferredProjectName(
                for: lowerText,
                candidateNames: sortedCandidates.map(\.name)
            )
        }
        
        // 2. Weighted token match against the project name, area, and recent task titles.
        if foundProjectName == nil {
            let inputTokens = projectTokens(in: lowerText)
            let hintTokenFrequency = sortedCandidates.reduce(into: [String: Int]()) { frequencies, candidate in
                for token in projectTokens(in: candidate.hints.joined(separator: " ")) {
                    frequencies[token, default: 0] += 1
                }
            }
            var bestMatch: (name: String, score: Int)?
            var hasAmbiguousBestMatch = false

            for candidate in sortedCandidates {
                let nameTokens = projectTokens(in: candidate.name)
                let hintTokens = projectTokens(in: candidate.hints.joined(separator: " "))
                let nameOverlap = inputTokens.intersection(nameTokens).count
                let overlappingHints = inputTokens.intersection(hintTokens)
                let uniqueHintOverlap = overlappingHints.filter { hintTokenFrequency[$0] == 1 }.count
                let score = (nameOverlap * 4) + overlappingHints.count + (uniqueHintOverlap * 2)
                let isStrongEnough = nameOverlap > 0 || uniqueHintOverlap > 0 || overlappingHints.count >= 2

                if isStrongEnough, score > (bestMatch?.score ?? 0) {
                    bestMatch = (candidate.name, score)
                    hasAmbiguousBestMatch = false
                } else if isStrongEnough, score == bestMatch?.score {
                    hasAmbiguousBestMatch = true
                }
            }

            if !hasAmbiguousBestMatch {
                foundProjectName = bestMatch?.name
            }
        }
        
        // 2.5. Prefix/Abbreviation Match (Medium-Low Confidence)
        // "Chem" -> Matches "Chemistry"
        if foundProjectName == nil {
            let inputTokens = projectTokens(in: lowerText).filter { $0.count >= 3 }
            
            for candidate in sortedCandidates {
                let pTokens = projectTokens(in: candidate.name)
                
                // Check if ANY input token is a prefix of ANY project token
                // e.g. input "chem", project "chemistry" -> match
                for iToken in inputTokens {
                    for pToken in pTokens {
                        if pToken.hasPrefix(iToken) {
                            foundProjectName = candidate.name
                            break
                        }
                    }
                    if foundProjectName != nil { break }
                }
                if foundProjectName != nil { break }
            }
        }
        
        // 3. Semantic Match via Embeddings (Low Confidence / Concept Match)
        // "Advertise" -> Matches "Marketing"
        // Skip semantic matching for very short inputs to reduce parse cost while typing.
        if foundProjectName == nil, lowerText.count > 5, let embedding = englishEmbedding {
            var bestDistance: Double = 2.0
            var bestSemanticMatch: String?
            
            let words = lowerText.components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 3 }
            
            for word in words {
                for candidate in sortedCandidates {
                    // Check Levenshtein distance first (Typos)
                    // "Mrketing" -> "Marketing"
                    let pName = candidate.name.lowercased()
                    if levenshtein(a: word, b: pName) <= 2 && pName.count > 4 {
                        foundProjectName = candidate.name
                        break
                    }
                    
                    // Semantic Embedding
                    let pWords = pName.components(separatedBy: .whitespacesAndNewlines)
                    for pWord in pWords {
                        let distance = embedding.distance(between: word, and: pWord)
                        if distance < 0.55 && distance < bestDistance {
                            bestDistance = distance
                            bestSemanticMatch = candidate.name
                        }
                    }
                }
                if foundProjectName != nil { break }
            }
            
            if foundProjectName == nil, let match = bestSemanticMatch {
                foundProjectName = match
            }
        }

        // 4. Detect Duration (Regex)
        // Improved to handle "hrs", "mins" and slight variations.
        // Matches: 2h, 2.5hrs, 30m, 30mins, 45 minute.
        if let regex = durationRegex {
            let matches = regex.matches(
                in: remainingText,
                range: NSRange(remainingText.startIndex..., in: remainingText)
            )

            var totalDuration: TimeInterval = 0

            for match in matches {
                if let valRange = Range(match.range(at: 1), in: remainingText),
                   let unitRange = Range(match.range(at: 2), in: remainingText) {

                    let valString = String(remainingText[valRange])
                    let unitString = String(remainingText[unitRange]).lowercased()

                    if let value = Double(valString) {
                        if unitString.starts(with: "h") {
                            totalDuration += value * 3600
                        } else if unitString.starts(with: "m") {
                            totalDuration += value * 60
                        }
                    }
                }
            }

            if totalDuration > 0 {
                foundDuration = totalDuration

                for match in matches.reversed() {
                    if let fullRange = Range(match.range(at: 0), in: remainingText) {
                        remainingText.removeSubrange(fullRange)
                    }
                }

                remainingText = cleanWhitespace(remainingText)
            }
        }
        
        // 5. Detect Date (NSDataDetector)
        // Matches: "tomorrow", "next friday", "Jan 5th", "at 5pm".
        var foundDate: Date?
        
        if let detector = dateDetector {
            // Fix: "due Friday" is often misparsed by NSDataDetector as "Today".
            // Fix: also strip "on", "the" to help clean up "due on the 12th"
            let rawDateText = remainingText.replacingOccurrences(of: #"due\s+(?:on\s+)?(?:the\s+)?"#, with: "", options: [.regularExpression, .caseInsensitive])
            let dateText = normalizeDateTypos(rawDateText)
            
            let matches = detector.matches(in: dateText, options: [], range: NSRange(dateText.startIndex..., in: dateText))
            
            if let match = matches.last, let date = match.date {
                foundDate = date
                // Remove from title logic...
                // (Simplified for brevity in this chunk, but we need to remove the ORIGINAL text range if possible, or just the matched range in the clean text?
                // Removing from 'remainingText' based on 'dateText' range is risky if indices shifted.
                // Safest is to just remove the matched string from remainingText.)
                if let normalizedRange = Range(match.range, in: dateText) {
                    let normalizedMatchedString = String(dateText[normalizedRange])
                    let rawMatchedString = Range(match.range, in: rawDateText).map { String(rawDateText[$0]) } ?? normalizedMatchedString
                    foundDateHasExplicitTime = hasExplicitTime(in: normalizedMatchedString)
                    // Attempt to remove this string from original
                    remainingText = remainingText.replacingOccurrences(of: rawMatchedString, with: "", options: .caseInsensitive)
                    // Also attempt to remove "due " prefix if it was adjacent? 
                    // Let's just do a rough clean of "due" keyword if date found.
                    remainingText = remainingText.replacingOccurrences(of: "due ", with: "", options: .caseInsensitive)
                     .replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
                }
            } else {
                // Fallback: Check for "12th", "5th" (NSDataDetector often misses these without Month)
                if let regex = dayOfMonthRegex {
                     let dayMatches = regex.matches(
                        in: dateText,
                        range: NSRange(dateText.startIndex..., in: dateText)
                    )
                     if let dayMatch = dayMatches.last, let range = Range(dayMatch.range(at: 1), in: dateText), let day = Int(dateText[range]) {
                         // Find next occurrence of this day
                         let today = Date()
                         let calendar = Calendar.current
                         let currentDay = calendar.component(.day, from: today)
                         let currentMonth = calendar.component(.month, from: today)
                         let currentYear = calendar.component(.year, from: today)
                         
                         var components = DateComponents(year: currentYear, month: currentMonth, day: day)
                         if day < currentDay {
                             components.month = currentMonth + 1
                         }
                         if let date = calendar.date(from: components) {
                             foundDate = date
                             foundDateHasExplicitTime = hasExplicitTime(in: dateText)
                             // Cleanup
                             if let fullRange = Range(dayMatch.range, in: rawDateText) {
                                 let matchedStr = String(rawDateText[fullRange])
                                 remainingText = remainingText.replacingOccurrences(of: matchedStr, with: "")
                                 remainingText = remainingText.replacingOccurrences(of: "due ", with: "", options: .caseInsensitive)
                                     .replacingOccurrences(of: "on the", with: "", options: .caseInsensitive) // Rough clean
                                     .replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
                             }
                         }
                     }
                }
            }
        }
        
        // 6. Detect Recurrence (Habits)
        var foundRecurrence: String?
        
        let recurrencePatterns = [
            (pattern: #"\b(every day|daily)\b"#, interval: "daily"),
            (pattern: #"\b(every week|weekly)\b"#, interval: "weekly")
        ]
        
        for (pattern, interval) in recurrencePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: remainingText, range: NSRange(remainingText.startIndex..., in: remainingText))
                if let match = matches.first, let range = Range(match.range, in: remainingText) {
                    foundRecurrence = interval
                    // Remove from text
                    let matchedStr = String(remainingText[range])
                    remainingText = remainingText.replacingOccurrences(of: matchedStr, with: "")
                        .replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
                    break // Only support one interval for now
                }
            }
        }
        
        let normalizedDate = DueDateSupport.normalizeParsedDate(foundDate, hasExplicitTime: foundDateHasExplicitTime)

        return CoreResult(
            cleanTitle: remainingText,
            projectName: foundProjectName,
            duration: foundDuration,
            date: normalizedDate,
            dateHasExplicitTime: foundDateHasExplicitTime,
            recurrenceInterval: foundRecurrence,
            entryType: foundEntryType
        )
    }
    
    // MARK: - Helpers
    
    /// Calculates Levenshtein distance between two strings
    private static func levenshtein(a: String, b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        
        var dist = [[Int]]()
        
        for i in 0...a.count {
            var row = [Int]()
            for j in 0...b.count {
                if i == 0 { row.append(j) }
                else if j == 0 { row.append(i) }
                else { row.append(0) }
            }
            dist.append(row)
        }
        
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                dist[i][j] = Swift.min(
                    dist[i - 1][j] + 1,      // Deletion
                    dist[i][j - 1] + 1,      // Insertion
                    dist[i - 1][j - 1] + cost // Substitution
                )
            }
        }
        
        return dist[a.count][b.count]
    }

    private static func cleanWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func projectTokens(in text: String) -> Set<String> {
        Set(normalizedWords(in: text).filter { token in
            token.count >= 2 && !projectStopWords.contains(token)
        })
    }

    private static func containsTokenSequence(_ phrase: String, in text: String) -> Bool {
        let phraseWords = normalizedWords(in: phrase)
        let textWords = normalizedWords(in: text)
        guard !phraseWords.isEmpty, phraseWords.count <= textWords.count else { return false }

        for startIndex in 0...(textWords.count - phraseWords.count) {
            let endIndex = startIndex + phraseWords.count
            if Array(textWords[startIndex..<endIndex]) == phraseWords {
                return true
            }
        }

        return false
    }

    private static func normalizedWords(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func hasExplicitTime(in text: String) -> Bool {
        guard let regex = explicitTimeRegex else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func normalizeDateTypos(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\bfeburary\b"#,
            with: "february",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
