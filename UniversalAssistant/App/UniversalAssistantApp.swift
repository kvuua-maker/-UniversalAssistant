import SwiftUI

@main
struct UniversalAssistantApp: App {
    @State private var model = AssistantViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup { AssistantHomeView(model: model) }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    model.handleSceneBecameInactive()
                } else if let shared = SharedInboxStore().consume() {
                    model.ingestShared(shared)
                } else {
                    model.handleQuickLaunch()
                }
            }
    }
}
