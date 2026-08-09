import SwiftData
import SwiftUI

@main
struct MinuteIOSApp: App {
    @StateObject private var appModel: MinuteIOSAppModel

    init() {
        do {
            let modelContainer = try MinuteModelContainerFactory.makeContainer(
                configuration: .privateCloudKit(
                    containerIdentifier: MinuteCloudKit.containerIdentifier
                )
            )
            _appModel = StateObject(wrappedValue: MinuteIOSAppModel(modelContainer: modelContainer))
        } catch {
            fatalError("Could not create the iOS model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environmentObject(appModel)
                .task {
                    await appModel.start()
                }
        }
        .modelContainer(appModel.modelContainer)
    }
}
