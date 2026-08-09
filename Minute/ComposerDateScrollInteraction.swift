//
//  ComposerDateScrollInteraction.swift
//  Minute
//
//  Draft-only date scrubbing for the quick composer.
//

import AppKit
import SwiftUI

struct ComposerDateScrollAccumulator {
    private(set) var accumulatedDelta: CGFloat = 0

    mutating func consume(delta: CGFloat, isPrecise: Bool) -> Int {
        guard delta.isFinite, delta != 0 else { return 0 }

        if !isPrecise {
            return delta > 0 ? 1 : -1
        }

        accumulatedDelta += delta
        let threshold: CGFloat = 28
        let rawSteps = Int(accumulatedDelta / threshold)
        let steps = min(max(rawSteps, -7), 7)
        accumulatedDelta -= CGFloat(steps) * threshold
        return steps
    }

    mutating func endGesture() {
        accumulatedDelta = 0
    }
}

enum ComposerDraftDateStepper {
    static func date(
        afterApplying steps: Int,
        to selection: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard steps != 0 else { return selection }

        let today = calendar.startOfDay(for: now)
        var result = selection.map { calendar.startOfDay(for: $0) }
        let direction = steps > 0 ? 1 : -1

        for _ in 0..<abs(steps) {
            guard let current = result else {
                if direction > 0 {
                    result = today
                }
                continue
            }

            if direction < 0, current <= today {
                result = nil
            } else {
                result = calendar.date(byAdding: .day, value: direction, to: current)
            }
        }

        return result
    }
}

struct ComposerScrollWheelObserver: NSViewRepresentable {
    let isEnabled: Bool
    let onScroll: (_ deltaY: CGFloat, _ isPrecise: Bool) -> Void
    let onGestureEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll, onGestureEnded: onGestureEnded)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.observedView = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.observedView = nsView
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onScroll = onScroll
        context.coordinator.onGestureEnded = onGestureEnded
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        weak var observedView: NSView?
        var isEnabled = false
        var onScroll: (_ deltaY: CGFloat, _ isPrecise: Bool) -> Void
        var onGestureEnded: () -> Void
        private var monitor: Any?

        init(
            onScroll: @escaping (_ deltaY: CGFloat, _ isPrecise: Bool) -> Void,
            onGestureEnded: @escaping () -> Void
        ) {
            self.onScroll = onScroll
            self.onGestureEnded = onGestureEnded
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.shouldObserve(event) else { return event }

                // AppKit's scrolling delta follows the document direction. Invert it
                // so a downward gesture moves a deadline forward, matching the date rail.
                self.onScroll(-event.scrollingDeltaY, event.hasPreciseScrollingDeltas)

                if event.phase.contains(.ended) || event.momentumPhase.contains(.ended) {
                    self.onGestureEnded()
                }
                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func shouldObserve(_ event: NSEvent) -> Bool {
            guard isEnabled,
                  let view = observedView,
                  let window = view.window,
                  event.window === window else { return false }

            let location = view.convert(event.locationInWindow, from: nil)
            return view.bounds.contains(location)
        }

        deinit {
            removeMonitor()
        }
    }
}
