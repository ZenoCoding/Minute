//
//  SmartInputParser.swift
//  Minute
//
//  Helper to extract structured data (Project, Duration) from natural language input.
//

import Foundation
import NaturalLanguage

struct SmartInputParser {
    
    struct Result {
        let cleanTitle: String
        let project: Project?
        let duration: TimeInterval?
        let date: Date?
        let isRecurring: Bool
        let recurrenceInterval: String?
    }

    struct ComposerResult: Sendable {
        let cleanTitle: String
        let projectName: String?
        let duration: TimeInterval?
        let date: Date?
        let recurrenceInterval: String?
    }

    private struct CoreResult: Sendable {
        let cleanTitle: String
        let projectName: String?
        let duration: TimeInterval?
        let date: Date?
        let recurrenceInterval: String?
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
    
    /// Parses the raw input text to find a matching project and duration.
    /// - Parameters:
    ///   - text: The raw input string (e.g. "Draft report for Marketing 2h")
    ///   - projects: List of candidate projects.
    /// - Returns: A Result containing the inferred project, duration, and the "clean" title (optional).
    static func parse(text: String, projects: [Project]) -> Result {
        let projectNames = projects.map(\.name)
        let core = parseCore(text: text, projectNames: projectNames)
        let matchedProject = core.projectName.flatMap { name in
            projects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }

        return Result(
            cleanTitle: core.cleanTitle,
            project: matchedProject,
            duration: core.duration,
            date: core.date,
            isRecurring: core.recurrenceInterval != nil,
            recurrenceInterval: core.recurrenceInterval
        )
    }

    static func parseForComposer(text: String, projectNames: [String]) -> ComposerResult {
        let core = parseCore(text: text, projectNames: projectNames)
        return ComposerResult(
            cleanTitle: core.cleanTitle,
            projectName: core.projectName,
            duration: core.duration,
            date: core.date,
            recurrenceInterval: core.recurrenceInterval
        )
    }

    private static func parseCore(text: String, projectNames: [String]) -> CoreResult {
        var remainingText = text
        var foundProjectName: String?
        var foundDuration: TimeInterval?
        
        let lowerText = text.lowercased()
        
        // 0. Prepare Candidates
        let sortedProjectNames = projectNames.sorted { $0.count > $1.count }
        
        // 1. Exact Substring Match (Highest Confidence)
        // "Update Marketing stats" -> Matches "Marketing"
        if foundProjectName == nil {
            for projectName in sortedProjectNames {
                let pName = projectName.lowercased()
                if lowerText.contains(pName) {
                    foundProjectName = projectName
                    break
                }
            }
        }
        
        // 2. Token Intersection Match (Medium Confidence)
        // "Minute bug" -> Matches "Minute App" (intersection: "minute")
        if foundProjectName == nil {
            let inputTokens = Set(lowerText.components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 2 })
            
            // Find project with highest token overlap
            var bestMatch: String?
            var maxOverlap = 0
            
            for projectName in sortedProjectNames {
                let pTokens = Set(projectName.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 2 })
                let overlap = inputTokens.intersection(pTokens).count
                
                if overlap > maxOverlap {
                    maxOverlap = overlap
                    bestMatch = projectName
                }
            }
            
            if maxOverlap > 0 {
                foundProjectName = bestMatch
            }
        }
        
        // 2.5. Prefix/Abbreviation Match (Medium-Low Confidence)
        // "Chem" -> Matches "Chemistry"
        if foundProjectName == nil {
            let inputTokens = lowerText.components(separatedBy: .whitespacesAndNewlines).filter { $0.count >= 2 } // Allow 2 chars like "CS"
            
            for projectName in sortedProjectNames {
                let pTokens = projectName.lowercased().components(separatedBy: .whitespacesAndNewlines)
                
                // Check if ANY input token is a prefix of ANY project token
                // e.g. input "chem", project "chemistry" -> match
                for iToken in inputTokens {
                    for pToken in pTokens {
                        if pToken.hasPrefix(iToken) {
                            foundProjectName = projectName
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
                for projectName in sortedProjectNames {
                    // Check Levenshtein distance first (Typos)
                    // "Mrketing" -> "Marketing"
                    let pName = projectName.lowercased()
                    if levenshtein(a: word, b: pName) <= 2 && pName.count > 4 {
                        foundProjectName = projectName
                        break
                    }
                    
                    // Semantic Embedding
                    let pWords = pName.components(separatedBy: .whitespacesAndNewlines)
                    for pWord in pWords {
                        let distance = embedding.distance(between: word, and: pWord)
                        if distance < 0.8 && distance < bestDistance {
                            bestDistance = distance
                            bestSemanticMatch = projectName
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
            
            if let match = matches.last {
                if let valRange = Range(match.range(at: 1), in: remainingText),
                   let unitRange = Range(match.range(at: 2), in: remainingText) {
                    
                    let valString = String(remainingText[valRange])
                    let unitString = String(remainingText[unitRange]).lowercased()
                    
                    if let value = Double(valString) {
                        if unitString.starts(with: "h") {
                            foundDuration = value * 3600
                        } else if unitString.starts(with: "m") {
                            foundDuration = value * 60
                        }
                    }
                    
                    if let fullRange = Range(match.range(at: 0), in: remainingText) {
                        remainingText.removeSubrange(fullRange)
                        remainingText = remainingText.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }
        
        // 5. Detect Date (NSDataDetector)
        // Matches: "tomorrow", "next friday", "Jan 5th", "at 5pm".
        var foundDate: Date?
        
        if let detector = dateDetector {
            // Fix: "due Friday" is often misparsed by NSDataDetector as "Today".
            // Fix: also strip "on", "the" to help clean up "due on the 12th"
            let dateText = remainingText.replacingOccurrences(of: #"due\s+(?:on\s+)?(?:the\s+)?"#, with: "", options: [.regularExpression, .caseInsensitive])
            
            let matches = detector.matches(in: dateText, options: [], range: NSRange(dateText.startIndex..., in: dateText))
            
            if let match = matches.last, let date = match.date {
                foundDate = date
                // Remove from title logic...
                // (Simplified for brevity in this chunk, but we need to remove the ORIGINAL text range if possible, or just the matched range in the clean text?
                // Removing from 'remainingText' based on 'dateText' range is risky if indices shifted.
                // Safest is to just remove the matched string from remainingText.)
                if let range = Range(match.range, in: dateText) {
                    let matchedString = String(dateText[range])
                    // Attempt to remove this string from original
                    remainingText = remainingText.replacingOccurrences(of: matchedString, with: "", options: .caseInsensitive)
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
                             // Cleanup
                             if let fullRange = Range(dayMatch.range, in: dateText) {
                                 let matchedStr = String(dateText[fullRange])
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
        
        return CoreResult(
            cleanTitle: remainingText,
            projectName: foundProjectName,
            duration: foundDuration,
            date: foundDate,
            recurrenceInterval: foundRecurrence
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
}
