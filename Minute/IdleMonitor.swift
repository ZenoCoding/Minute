//
//  IdleMonitor.swift
//  Minute
//
//  Created by Tycho Young on 1/2/26.
//

import Foundation
import CoreGraphics
import Combine

class IdleMonitor: ObservableObject {
    @Published var currentIdleTime: TimeInterval = 0
    @Published var isIdle: Bool = false
    @Published var isAway: Bool = false
    
    // Configurable thresholds
    let idleThreshold: TimeInterval = 120 // 2 minutes
    let awayThreshold: TimeInterval = 900 // 15 minutes
    
    private var timer: Timer?
    
    init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkIdleStatus()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    @objc private func checkIdleStatus() {
        let idle = getSecondsSinceLastInput()
        
        DispatchQueue.main.async {
            self.currentIdleTime = idle
            
            let wasAway = self.isAway
            let wasIdle = self.isIdle
            
            self.isAway = idle >= self.awayThreshold
            self.isIdle = idle >= self.idleThreshold && idle < self.awayThreshold
            
            // Debug print on state change
            if self.isAway != wasAway {
                print("IdleMonitor: State changed to \(self.isAway ? "AWAY" : "ACTIVE/IDLE")")
            } else if self.isIdle != wasIdle {
                print("IdleMonitor: State changed to \(self.isIdle ? "IDLE" : "ACTIVE")")
            }
        }
    }
    
    private func getSecondsSinceLastInput() -> TimeInterval {
        // CGEventSource.secondsSinceLastEventType returns the time in seconds since the last input event
        // StateID.combinedSessionState checks across all sessions (good for local user)
        // StateID.hidSystemState is also an option, but combined usually works best for "user at computer"
        
        // Note: This API requires Accessibility permissions to be fully accurate in some contexts,
        // but often returns valid data for the current user 
        // without explicit permission prompts in newer macOS versions *if* just checking time.
        // However, if it returns -1 or 0 constantly, we know we hit a permission wall.
        
        let seconds = CGEventSource.secondsSinceLastEventType(CGEventSourceStateID.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        return seconds
    }
}
