//
//  CapturePanelController.swift
//  Minute
//
//  Presents quick capture as a transient global panel over the user's current work.
//

import AppKit
import SwiftData
import SwiftUI

@MainActor
final class CapturePanelController: NSObject, NSWindowDelegate {
    private var panel: CapturePanel?
    private var previousApplication: NSRunningApplication?
    private let panelSize = NSSize(width: 840, height: 620)
    private let presentationDuration: TimeInterval = 0.24

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var isPresented: Bool {
        panel?.isVisible == true
    }

    func show(modelContext: ModelContext, calendarManager: CalendarManager) {
        if panel == nil {
            panel = makePanel(modelContext: modelContext, calendarManager: calendarManager)
        }

        guard let panel else { return }
        previousApplication = NSWorkspace.shared.frontmostApplication.flatMap { app in
            app.processIdentifier == NSRunningApplication.current.processIdentifier ? nil : app
        }

        let targetScreen = screenContainingMouse() ?? NSScreen.main
        let targetFrame: NSRect
        if let screen = targetScreen {
            targetFrame = centeredFrame(on: screen)
        } else {
            targetFrame = centeredFrame(on: nil)
        }

        let initialFrame = targetFrame
            .insetBy(dx: 12, dy: 9)
            .offsetBy(dx: 0, dy: -8)
        panel.setFrame(initialFrame, display: false)
        panel.alphaValue = 0

        ShortcutManager.shared.isComposerOpen = true
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = presentationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    func toggle(modelContext: ModelContext, calendarManager: CalendarManager) {
        if isPresented {
            close()
        } else {
            show(modelContext: modelContext, calendarManager: calendarManager)
        }
    }

    func close() {
        close(restorePreviousApplication: true)
    }

    private func close(restorePreviousApplication: Bool) {
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        ShortcutManager.shared.isComposerOpen = false

        if restorePreviousApplication {
            if let previousApplication {
                previousApplication.activate(options: [])
            } else {
                NSApp.hide(nil)
            }
        }
        previousApplication = nil
    }

    func windowWillClose(_ notification: Notification) {
        ShortcutManager.shared.isComposerOpen = false
    }

    private func makePanel(modelContext: ModelContext, calendarManager: CalendarManager) -> CapturePanel {
        let binding = Binding<Bool>(
            get: { [weak self] in
                self?.isPresented ?? false
            },
            set: { [weak self] isPresented in
                if !isPresented {
                    self?.close()
                }
            }
        )

        let rootView = FullScreenCaptureView(isPresented: binding)
            .environment(\.modelContext, modelContext)
            .environmentObject(calendarManager)

        let panel = CapturePanel(
            contentRect: centeredFrame(on: NSScreen.main),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView: rootView)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false

        return panel
    }

    @objc private func appDidResignActive(_ notification: Notification) {
        close(restorePreviousApplication: false)
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        }
    }

    private func centeredFrame(on screen: NSScreen?) -> NSRect {
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        return NSRect(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}

final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
