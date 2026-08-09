import Foundation

struct MinuteWidgetTask: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let projectName: String?
    let dueDate: Date?
    let isOverdue: Bool

    init(
        id: UUID,
        title: String,
        projectName: String? = nil,
        dueDate: Date? = nil,
        isOverdue: Bool = false
    ) {
        self.id = id
        self.title = title
        self.projectName = projectName
        self.dueDate = dueDate
        self.isOverdue = isOverdue
    }
}

struct MinuteWidgetSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let generatedAt: Date
    let tasks: [MinuteWidgetTask]

    init(
        generatedAt: Date = Date(),
        tasks: [MinuteWidgetTask] = [],
        version: Int = MinuteWidgetSnapshot.currentVersion
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.tasks = tasks
    }
}

struct MinuteWidgetSnapshotStore {
    static let appGroupIdentifier = "group.com.tychoyoung.Minute"
    static let storageKey = "minute.widget.snapshot"

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: Self.appGroupIdentifier)
            ?? .standard
    }

    func read() -> MinuteWidgetSnapshot? {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(MinuteWidgetSnapshot.self, from: data)
    }

    func write(_ snapshot: MinuteWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}

enum MinuteWidgetSampleData {
    static let referenceDate = Date(timeIntervalSince1970: 1_735_689_600)

    static let snapshot = MinuteWidgetSnapshot(
        generatedAt: referenceDate,
        tasks: [
            MinuteWidgetTask(
                id: UUID(uuidString: "B6C5A2C5-3A3C-4C16-8A12-2DC059F4B95D")!,
                title: "Review the next small step",
                projectName: "Minute iOS",
                dueDate: referenceDate,
                isOverdue: false
            ),
            MinuteWidgetTask(
                id: UUID(uuidString: "73D4F4A2-6A35-46B5-8B4D-4EBB7BB4BF3D")!,
                title: "Capture a task from the phone",
                projectName: "Inbox",
                dueDate: nil,
                isOverdue: false
            ),
            MinuteWidgetTask(
                id: UUID(uuidString: "5D6E1A48-F5C3-4A96-93B2-6A0B4F32E5A9")!,
                title: "Keep the list light",
                projectName: nil,
                dueDate: nil,
                isOverdue: false
            )
        ]
    )
}
