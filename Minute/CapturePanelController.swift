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
    private enum PresentationState {
        case hidden
        case presenting
        case presented
        case dismissing
    }

    private var panel: CapturePanel?
    private weak var previousMinuteKeyWindow: NSWindow?
    private weak var previousMinuteFirstResponder: NSResponder?
    private var isPresentingAuxiliaryUI = false
    private var presentationState = PresentationState.hidden
    private var presentationGeneration = 0
    private let panelSize = NSSize(width: 840, height: 620)
    private let screenMargin: CGFloat = 16
    private let presentationDuration: TimeInterval = 0.24

    var isPresented: Bool {
        switch presentationState {
        case .presenting, .presented:
            return true
        case .hidden, .dismissing:
            return false
        }
    }

    func show(modelContext: ModelContext, calendarManager: CalendarManager) {
        guard presentationState == .hidden else {
            if isPresented {
                panel?.makeKeyAndOrderFront(nil)
            }
            return
        }

        if panel == nil {
            panel = makePanel()
        }

        guard let panel else { return }

        presentationGeneration += 1
        let generation = presentationGeneration
        presentationState = .presenting
        previousMinuteKeyWindow = NSApp.isActive ? NSApp.keyWindow : nil
        previousMinuteFirstResponder = previousMinuteKeyWindow?.firstResponder
        isPresentingAuxiliaryUI = false

        installContent(
            in: panel,
            modelContext: modelContext,
            calendarManager: calendarManager
        )

        let targetFrame = centeredFrame(on: targetScreen())
        let initialFrame = targetFrame
            .insetBy(dx: 12, dy: 9)
            .offsetBy(dx: 0, dy: -8)
        panel.setFrame(initialFrame, display: false)
        panel.alphaValue = 0

        // A nonactivating panel can become key for text input while the user's
        // current application remains active. orderFrontRegardless is required
        // to place it above another application's full-screen Space.
        panel.orderFrontRegardless()
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = presentationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor [weak self, weak panel] in
                guard let self,
                      self.presentationGeneration == generation,
                      self.presentationState == .presenting,
                      panel?.isVisible == true else { return }
                self.presentationState = .presented
            }
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
        guard presentationState != .hidden else { return }

        presentationGeneration += 1
        presentationState = .dismissing

        let minuteKeyWindow = previousMinuteKeyWindow
        let minuteFirstResponder = previousMinuteFirstResponder
        previousMinuteKeyWindow = nil
        previousMinuteFirstResponder = nil
        isPresentingAuxiliaryUI = false
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        panel?.contentViewController = nil
        if NSApp.isActive, minuteKeyWindow?.isVisible == true {
            minuteKeyWindow?.makeKey()
            if let minuteFirstResponder {
                minuteKeyWindow?.makeFirstResponder(minuteFirstResponder)
            }
        }

        presentationState = .hidden
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }

        // Sheets and popovers briefly take key-window ownership from their
        // parent. Let AppKit settle the transition before deciding it was a
        // genuine click-away.
        let generation = presentationGeneration
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self,
                  let panel,
                  self.presentationGeneration == generation,
                  self.isPresented else { return }

            if self.isPresentingAuxiliaryUI || self.belongsToComposer(NSApp.keyWindow, panel: panel) {
                return
            }

            self.close()
        }
    }

    private func installContent(
        in panel: CapturePanel,
        modelContext: ModelContext,
        calendarManager: CalendarManager
    ) {
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

        let rootView = FullScreenCaptureView(
            isPresented: binding,
            onAuxiliaryPresentationChanged: { [weak self] isPresented in
                self?.setAuxiliaryPresentationActive(isPresented)
            }
        )
            .environment(\.modelContext, modelContext)
            .environmentObject(calendarManager)

        panel.contentViewController = NSHostingController(rootView: rootView)
    }

    private func setAuxiliaryPresentationActive(_ isActive: Bool) {
        isPresentingAuxiliaryUI = isActive

        guard !isActive, let panel, isPresented, !panel.isKeyWindow else { return }

        let generation = presentationGeneration
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self,
                  let panel,
                  self.presentationGeneration == generation,
                  self.isPresented,
                  !self.isPresentingAuxiliaryUI,
                  !self.belongsToComposer(NSApp.keyWindow, panel: panel) else { return }
            self.close()
        }
    }

    private func makePanel() -> CapturePanel {
        let panel = CapturePanel(
            contentRect: centeredFrame(on: NSScreen.main),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.onCancel = { [weak self] in
            self?.close()
        }
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .transient,
            .ignoresCycle,
        ]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false

        return panel
    }

    private func belongsToComposer(_ window: NSWindow?, panel: CapturePanel) -> Bool {
        guard let window else { return false }
        if window === panel { return true }

        var ancestor = window.parent
        while let current = ancestor {
            if current === panel { return true }
            ancestor = current.parent
        }

        var sheetParent = window.sheetParent
        while let current = sheetParent {
            if current === panel { return true }
            sheetParent = current.sheetParent
        }

        return panel.childWindows?.contains(where: { $0 === window }) == true
    }

    private func targetScreen() -> NSScreen? {
        // NSScreen.main follows the screen containing the currently active
        // application's key window, which is a better keyboard-driven default
        // than whichever display happens to contain the pointer.
        previousMinuteKeyWindow?.screen ?? screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        }
    }

    private func centeredFrame(on screen: NSScreen?) -> NSRect {
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let availableWidth = max(1, visibleFrame.width - (screenMargin * 2))
        let availableHeight = max(1, visibleFrame.height - (screenMargin * 2))
        let width = min(panelSize.width, availableWidth)
        let height = min(panelSize.height, availableHeight)

        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }
}

final class CapturePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
