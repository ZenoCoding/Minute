//
//  HabitService.swift
//  Minute
//
//  Handles the logic for recurring tasks (Habits).
//  Runs on app launch to reset completed habits for the new cycle.
//

import Foundation
import SwiftData
import SwiftUI

class HabitService {
    private var modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Checks all recurring tasks and resets them if their cycle has renewed.
    func checkAndResetHabits() {
        print("🔄 Checking recurring tasks...")
        
        // Fetch all completed, recurring tasks
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { task in
                task.isRecurring == true && task.isCompleted == true
            }
        )
        
        guard let tasks = try? modelContext.fetch(descriptor) else { return }
        
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        
        var resetCount = 0
        
        for task in tasks {
            guard let completedDate = task.completedAt else { continue }
            guard let interval = task.recurrenceInterval else { continue }
            
            var shouldReset = false
            
            switch interval.lowercased() {
            case "daily", "every day":
                // If completed BEFORE today, reset it.
                if completedDate < startOfToday {
                    shouldReset = true
                }
                
            case "weekly", "every week":
                // If completed before the start of this week (e.g. Sunday/Monday)
                if let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) {
                    if completedDate < startOfWeek {
                        shouldReset = true
                    }
                }
                
            default:
                break
            }
            
            if shouldReset {
                print("♻️ Resetting habit: \(task.title)")
                task.isCompleted = false
                task.completedAt = nil
                resetCount += 1
            }
        }
        
        if resetCount > 0 {
            try? modelContext.save()
            print("✅ Reset \(resetCount) recurring tasks.")
        } else {
            print("🌱 No recurring tasks needed reset.")
        }
    }
}
