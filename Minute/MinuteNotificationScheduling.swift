//
//  MinuteNotificationScheduling.swift
//  Minute
//
//  Platform-neutral due-task notification derivation and the iOS/macOS
//  UserNotifications adapter.
//

import Foundation
import CoreData
import SwiftData

struct MinuteTaskNotificationRequest: Equatable, Sendable {
    static let identifierPrefix = "com.tychoyoung.Minute.task."

    let identifier: String
    let taskID: UUID
    let title: String
    let body: String
    let fireDate: Date

    static func identifier(for taskID: UUID) -> String {
        identifierPrefix + taskID.uuidString.lowercased()
    }
}

enum MinuteTaskNotificationRequestDeriver {
    static func request(
        for task: TaskItem,
        now: Date = Date()
    ) -> MinuteTaskNotificationRequest? {
        guard !task.isCompleted, let dueDate = task.dueDate, dueDate > now else {
            return nil
        }

        let body = task.project.map { "\($0.name)" } ?? "Minute task"
        return MinuteTaskNotificationRequest(
            identifier: MinuteTaskNotificationRequest.identifier(for: task.id),
            taskID: task.id,
            title: task.title,
            body: body,
            fireDate: dueDate
        )
    }
}

@MainActor
protocol MinuteNotificationScheduler: AnyObject {
    func schedule(_ request: MinuteTaskNotificationRequest) async throws
    func cancel(taskID: UUID)
    func cancelAllMinuteTaskNotifications() async
}

/// Reconciles the complete set of due-task notifications after local saves,
/// CloudKit imports, and app launch. Replacing only Minute-owned identifiers
/// makes completion/deletion cancellation safe and keeps identifiers stable.
@MainActor
final class MinuteNotificationCoordinator {
    private let modelContext: ModelContext
    private let scheduler: MinuteNotificationScheduler
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(
        modelContext: ModelContext,
        scheduler: MinuteNotificationScheduler,
        notificationCenter: NotificationCenter = .default
    ) {
        self.modelContext = modelContext
        self.scheduler = scheduler
        self.notificationCenter = notificationCenter

        observers.append(
            notificationCenter.addObserver(
                forName: ModelContext.didSave,
                object: modelContext,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rescheduleAfterStoreChange()
                }
            }
        )
        observers.append(
            notificationCenter.addObserver(
                forName: .NSPersistentStoreRemoteChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rescheduleAfterStoreChange()
                }
            }
        )
    }

    deinit {
        observers.forEach(notificationCenter.removeObserver)
    }

    func rescheduleAfterStoreChange() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await reconcile()
        }
    }

    func reconcile(now: Date = Date()) async throws {
        let tasks = try modelContext.fetch(FetchDescriptor<TaskItem>())
        let requests = tasks.compactMap {
            MinuteTaskNotificationRequestDeriver.request(for: $0, now: now)
        }

        await scheduler.cancelAllMinuteTaskNotifications()
        for request in requests {
            try await scheduler.schedule(request)
        }
    }
}

#if canImport(UserNotifications)
import UserNotifications

@MainActor
final class MinuteUserNotificationScheduler: MinuteNotificationScheduler {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func schedule(_ request: MinuteTaskNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default

        let dateComponents = Calendar.autoupdatingCurrent.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
            from: request.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let notification = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(notification) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func cancel(taskID: UUID) {
        let identifier = MinuteTaskNotificationRequest.identifier(for: taskID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func cancelAllMinuteTaskNotifications() async {
        let identifiers = await minuteTaskNotificationIdentifiers()
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func minuteTaskNotificationIdentifiers() async -> [String] {
        let pending = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(
                    returning: requests
                        .map(\.identifier)
                        .filter { $0.hasPrefix(MinuteTaskNotificationRequest.identifierPrefix) }
                )
            }
        }
        let delivered = await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(
                    returning: notifications
                        .map(\.request.identifier)
                        .filter { $0.hasPrefix(MinuteTaskNotificationRequest.identifierPrefix) }
                )
            }
        }
        return Array(Set(pending + delivered))
    }
}
#endif
