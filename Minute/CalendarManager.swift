//
//  CalendarManager.swift
//  Minute
//
//  Manages integration with EventKit (Apple Calendar).
//

import Foundation
import EventKit
import SwiftUI

@MainActor
class CalendarManager: ObservableObject {
    private let store = EKEventStore()
    @Published var events: [EKEvent] = []
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    
    init() {
        checkStatus()
    }
    
    func checkStatus() {
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if self.authorizationStatus == .authorized {
            fetchEvents()
        }
    }
    
    func requestAccess() {
        store.requestAccess(to: .event) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.checkStatus()
            }
        }
    }
    
    func fetchEvents() {
        let calendars = store.calendars(for: .event)
        
        // Fetch for Today and Tomorrow
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let endOfTomorrow = Calendar.current.date(byAdding: .day, value: 2, to: startOfDay)!
        
        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfTomorrow, calendars: calendars)
        
        let fetchedEvents = store.events(matching: predicate)
        self.events = fetchedEvents.sorted { $0.startDate < $1.startDate }
    }
    
    // Helper to group events by day or interleave
    func events(for date: Date) -> [EKEvent] {
        return events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: date) }
    }
}
