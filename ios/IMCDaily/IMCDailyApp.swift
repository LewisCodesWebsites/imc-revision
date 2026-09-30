import SwiftUI

@main
struct IMCDailyApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(.imcAccent)
                .task { await model.refresh() }
                .onChange(of: scenePhase) { phase in
                    // Check for new topics and questions whenever the app comes back.
                    if phase == .active { Task { await model.refresh() } }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "flame") }
            TopicsView()
                .tabItem { Label("Topics", systemImage: "square.grid.2x2") }
        }
        .fullScreenCover(item: $model.session) { session in
            SessionView(session: session)
                .environmentObject(model)
                .tint(.imcAccent)
        }
    }
}
