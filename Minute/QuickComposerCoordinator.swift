//
//  QuickComposerCoordinator.swift
//  Minute
//
//  Owns the global quick composer independently of any individual SwiftUI window.
//

import Combine
import SwiftData

@MainActor
final class QuickComposerCoordinator: ObservableObject {
    private let modelContext: ModelContext
    private let calendarManager: CalendarManager
    private let panelController = CapturePanelController()
    private var isStarted = false

    init(modelContext: ModelContext, calendarManager: CalendarManager) {
        self.modelContext = modelContext
        self.calendarManager = calendarManager
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        ShortcutManager.shared.startMonitoring { [weak self] in
            self?.toggle()
        }
    }

    func show() {
        panelController.show(
            modelContext: modelContext,
            calendarManager: calendarManager
        )
    }

    func toggle() {
        panelController.toggle(
            modelContext: modelContext,
            calendarManager: calendarManager
        )
    }
}

