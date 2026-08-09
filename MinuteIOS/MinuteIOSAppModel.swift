import SwiftData
import SwiftUI
import UserNotifications
import WidgetKit

@MainActor
final class MinuteIOSAppModel: ObservableObject {
    let modelContainer: ModelContainer

    private let snapshotStore: MinuteWidgetSnapshotStore
    private let notificationCoordinator: MinuteNotificationCoordinator
    private var observers: [NSObjectProtocol] = []

    init(
        modelContainer: ModelContainer,
        snapshotStore: MinuteWidgetSnapshotStore? = nil
    ) {
        self.modelContainer = modelContainer
        self.snapshotStore = snapshotStore ?? MinuteWidgetSnapshotStore()
        self.notificationCoordinator = MinuteNotificationCoordinator(
            modelContext: modelContainer.mainContext,
            scheduler: MinuteUserNotificationScheduler()
        )

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: ModelContext.didSave,
                object: modelContainer.mainContext,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshWidgetSnapshot()
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: .NSPersistentStoreRemoteChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshWidgetSnapshot()
                }
            }
        )
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func start() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        )
        refreshWidgetSnapshot()
        try? await notificationCoordinator.reconcile()
    }

    func refreshWidgetSnapshot(now: Date = Date()) {
        do {
            let tasks = try modelContainer.mainContext.fetch(
                FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\TaskItem.createdAt)])
            )
            let snapshot = MinuteWidgetSnapshotBuilder.makeSnapshot(from: tasks, now: now)
            snapshotStore.write(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: "MinuteWidget")
        } catch {
            // The app remains usable when the widget snapshot cannot be refreshed.
            // The next app activation will retry the read from the current store.
        }
    }
}
