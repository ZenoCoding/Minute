//
//  MinuteModelContainer.swift
//  Minute
//
//  Shared model-container configuration for macOS, iOS, and tests.
//

import Foundation
import SwiftData

enum MinuteModelContainerConfiguration: Equatable {
    case local(url: URL)
    case inMemory
    case privateCloudKit(containerIdentifier: String, storeURL: URL? = nil)
}

enum MinuteCloudKit {
    static let containerIdentifier = "iCloud.com.tychoyoung.Minute"
}

enum MinuteModelContainerFactory {
    static let schema = Schema([
        Area.self,
        Project.self,
        TaskItem.self,
        TaskChecklistItem.self,
        TaskSuggestion.self
    ])

    static func makeContainer(
        configuration: MinuteModelContainerConfiguration
    ) throws -> ModelContainer {
        let modelConfiguration: ModelConfiguration

        switch configuration {
        case .local(let url):
            // Keep the existing macOS store local unless a caller explicitly
            // opts into the private CloudKit configuration below.
            modelConfiguration = ModelConfiguration(
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
        case .inMemory:
            modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        case .privateCloudKit(let containerIdentifier, let storeURL):
            let identifier = containerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            precondition(!identifier.isEmpty, "A CloudKit container identifier is required.")
            if let storeURL {
                // Supplying the existing macOS URL upgrades that store in place
                // instead of silently creating a second, empty database.
                modelConfiguration = ModelConfiguration(
                    schema: schema,
                    url: storeURL,
                    cloudKitDatabase: .private(identifier)
                )
            } else {
                modelConfiguration = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .private(identifier)
                )
            }
        }

        return try ModelContainer(for: schema, configurations: [modelConfiguration])
    }
}
