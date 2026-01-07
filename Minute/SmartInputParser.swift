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
    }
    
    /// Parses the raw input text to find a matching project and duration.
    /// - Parameters:
    ///   - text: The raw input string (e.g. "Draft report for Marketing 2h")
    ///   - projects: List of candidate projects.
    /// - Returns: A Result containing the inferred project, duration, and the "clean" title (optional).
    /// Parses the raw input text to find a matching project and duration.
    /// - Parameters:
    ///   - text: The raw input string (e.g. "Draft report for Marketing 2h")
    ///   - projects: List of candidate projects.
    /// - Returns: A Result containing the inferred project, duration, and the "clean" title (optional).
    static func parse(text: String, projects: [Project]) -> Result {
        var remainingText = text
        var foundProject: Project?
        var foundDuration: TimeInterval?
        
        let lowerText = text.lowercased()
        
        // 0. Prepare Candidates
        let sortedProjects = projects.sorted { $0.name.count > $1.name.count }
        
        // 1. Exact Substring Match (Highest Confidence)
        // "Update Marketing stats" -> Matches "Marketing"
        if foundProject == nil {
            for project in sortedProjects {
                let pName = project.name.lowercased()
                if lowerText.contains(pName) {
                    foundProject = project
                    break
                }
            }
        }
        
        // 2. Token Intersection Match (Medium Confidence)
        // "Minute bug" -> Matches "Minute App" (intersection: "minute")
        if foundProject == nil {
            let inputTokens = Set(lowerText.components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 2 })
            
            // Find project with highest token overlap
            var bestMatch: Project?
            var maxOverlap = 0
            
            for project in sortedProjects {
                let pTokens = Set(project.name.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 2 })
                let overlap = inputTokens.intersection(pTokens).count
                
                if overlap > maxOverlap {
                    maxOverlap = overlap
                    bestMatch = project
                }
            }
            
            if maxOverlap > 0 {
                foundProject = bestMatch
            }
        }
        
        // 2.5. Prefix/Abbreviation Match (Medium-Low Confidence)
        // "Chem" -> Matches "Chemistry"
        if foundProject == nil {
            let inputTokens = lowerText.components(separatedBy: .whitespacesAndNewlines).filter { $0.count >= 2 } // Allow 2 chars like "CS"
            
            for project in sortedProjects {
                let pTokens = project.name.lowercased().components(separatedBy: .whitespacesAndNewlines)
                
                // Check if ANY input token is a prefix of ANY project token
                // e.g. input "chem", project "chemistry" -> match
                for iToken in inputTokens {
                    for pToken in pTokens {
                        if pToken.hasPrefix(iToken) {
                            foundProject = project
                            break
                        }
                    }
                    if foundProject != nil { break }
                }
                if foundProject != nil { break }
            }
        }
        
        // 3. Semantic Match via Embeddings (Low Confidence / Concept Match)
        // "Advertise" -> Matches "Marketing"
        if foundProject == nil, let embedding = NLEmbedding.wordEmbedding(for: .english) {
            var bestDistance: Double = 2.0
            var bestSemanticMatch: Project?
            
            let words = lowerText.components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 3 }
            
            for word in words {
                for project in projects {
                    // Check Levenshtein distance first (Typos)
                    // "Mrketing" -> "Marketing"
                    let pName = project.name.lowercased()
                    if levenshtein(a: word, b: pName) <= 2 && pName.count > 4 {
                        foundProject = project
                        break
                    }
                    
                    // Semantic Embedding
                    let pWords = pName.components(separatedBy: .whitespacesAndNewlines)
                    for pWord in pWords {
                        let distance = embedding.distance(between: word, and: pWord)
                        if distance < 0.8 && distance < bestDistance {
                            bestDistance = distance
                            bestSemanticMatch = project
                        }
                    }
                }
                if foundProject != nil { break }
            }
            
            if foundProject == nil, let match = bestSemanticMatch {
                foundProject = match
            }
        }
        
        // 4. Detect Duration (Regex)
        // Improved to handle "hrs", "mins" and slight variations
        // Matches: 2h, 2.5hrs, 30m, 30mins, 45 minute
        let durationPattern = #"(\b\d+(?:\.\d+)?)\s*(h(?:ours?|rs?)?|m(?:in(?:utes?)?s?)?)\b"#
        
        if let regex = try? NSRegularExpression(pattern: durationPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: remainingText, range: NSRange(remainingText.startIndex..., in: remainingText))
            
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
        // Matches: "tomorrow", "next friday", "Jan 5th", "at 5pm"
        var foundDate: Date?
        
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
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
                let dayPattern = #"\b(\d+)(?:st|nd|rd|th)\b"#
                if let regex = try? NSRegularExpression(pattern: dayPattern, options: .caseInsensitive) {
                     let dayMatches = regex.matches(in: dateText, range: NSRange(dateText.startIndex..., in: dateText))
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
        
        return Result(cleanTitle: remainingText, project: foundProject, duration: foundDuration, date: foundDate)
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
