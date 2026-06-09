//
//  ShortcutManager.swift
//  Minute
//
//  Created by Antigravity on 6/5/26.
//

import Cocoa
import ApplicationServices

enum ShortcutActivationMode: String, CaseIterable, Identifiable {
    case doubleOption = "doubleOption"
    case bothOptions = "bothOptions"
    case disabled = "disabled"
    
    var id: String { self.rawValue }
    var title: String {
        switch self {
        case .doubleOption: return "Double Press Option Key"
        case .bothOptions: return "Press Both Option Keys"
        case .disabled: return "Command + Shift + J Only"
        }
    }
}

class ShortcutManager {
    static let shared = ShortcutManager()
    
    private var localMonitor: Any?
    private var globalMonitor: Any?
    
    // State to track if the composer is already open
    var isComposerOpen = false
    
    // State for Double Option detection
    private var lastOptionPressTime: Date?
    private var wasOptionPressedBefore = false
    
    // State for Both Options detection
    private var leftOptionDown = false
    private var rightOptionDown = false
    
    // Raw bits in NSEvent.modifierFlags for Left/Right Option keys
    private static let leftOptionMask: UInt = 0x000020
    private static let rightOptionMask: UInt = 0x000040
    
    private init() {
        // Event monitoring is started manually after app launch (e.g. in .task or finished launching)
    }
    
    func startMonitoring() {
        stopMonitoring()
        
        // Register local monitor (works when the app is active)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            if event.type == .keyDown {
                self?.handleKeyDown(event)
            } else if event.type == .flagsChanged {
                self?.handleFlagsChanged(event)
            }
            return event
        }
        
        // Register global monitor (works when the app is in background, if Accessibility permission is granted)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            if event.type == .keyDown {
                self?.handleKeyDown(event)
            } else if event.type == .flagsChanged {
                self?.handleFlagsChanged(event)
            }
        }
    }
    
    func stopMonitoring() {
        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }
        if let global = globalMonitor {
            NSEvent.removeMonitor(global)
            globalMonitor = nil
        }
    }
    
    private func handleKeyDown(_ event: NSEvent) {
        // Any physical key down event resets the double press timer.
        // This prevents Option-modifier combos (like cursor navigation or text deletion) from triggering the hotkey.
        lastOptionPressTime = nil
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        let mode = activationMode
        guard mode != .disabled else { return }
        
        let flags = event.modifierFlags
        
        // Differentiate Left vs Right Option using the device-dependent raw flags
        let isLeftPressed = (flags.rawValue & Self.leftOptionMask) != 0
        let isRightPressed = (flags.rawValue & Self.rightOptionMask) != 0
        
        switch mode {
        case .bothOptions:
            // Trigger when both Option keys are held down simultaneously
            if isLeftPressed && isRightPressed {
                // To avoid multiple triggers while held, we only fire when this state transitions to both-down
                if !(leftOptionDown && rightOptionDown) {
                    leftOptionDown = true
                    rightOptionDown = true
                    triggerToggle()
                }
            } else {
                leftOptionDown = isLeftPressed
                rightOptionDown = isRightPressed
            }
            
        case .doubleOption:
            // Double press Option: triggers when EITHER option key is pressed twice within 0.3 seconds.
            let isOptionPressed = flags.contains(.option)
            
            // Check if other modifier keys (Command, Shift, Control) are active
            let otherModifiers = flags.intersection([.command, .control, .shift])
            if !otherModifiers.isEmpty {
                // Reset double tap state if other modifiers are pressed
                lastOptionPressTime = nil
                wasOptionPressedBefore = isOptionPressed
                return
            }
            
            if isOptionPressed {
                if !wasOptionPressedBefore {
                    wasOptionPressedBefore = true
                    let now = Date()
                    if let lastPress = lastOptionPressTime, now.timeIntervalSince(lastPress) < 0.3 {
                        triggerToggle()
                        lastOptionPressTime = nil // Reset so a third press doesn't double-trigger
                    } else {
                        lastOptionPressTime = now
                    }
                }
            } else {
                wasOptionPressedBefore = false
            }
            
        case .disabled:
            break
        }
    }
    
    private func triggerToggle() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .toggleCaptureMode, object: nil)
        }
    }
    
    // MARK: - Accessibility Permissions
    
    static var isAccessibilityTrusted: Bool {
        return AXIsProcessTrusted()
    }
    
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        // Open the System Settings Privacy -> Accessibility pane directly
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private var activationMode: ShortcutActivationMode {
        let raw = UserDefaults.standard.string(forKey: "shortcutActivationMode") ?? ShortcutActivationMode.doubleOption.rawValue
        return ShortcutActivationMode(rawValue: raw) ?? .doubleOption
    }
}
