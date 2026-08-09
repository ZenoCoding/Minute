import SwiftUI

struct IOSRootView: View {
    @State private var isShowingCapture = false

    var body: some View {
        TabView {
            NavigationStack {
                TodayView(isShowingCapture: $isShowingCapture)
            }
            .tabItem {
                Label("Today", systemImage: "checklist")
            }

            NavigationStack {
                UpcomingView(isShowingCapture: $isShowingCapture)
            }
            .tabItem {
                Label("Upcoming", systemImage: "calendar")
            }

            NavigationStack {
                ProjectsView(isShowingCapture: $isShowingCapture)
            }
            .tabItem {
                Label("Projects", systemImage: "folder")
            }
        }
        .tint(.indigo)
        .sheet(isPresented: $isShowingCapture) {
            QuickCaptureView()
        }
    }
}
