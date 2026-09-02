import SwiftUI

@main
struct UniversalAssistantApp: App {
    @State private var model = AssistantViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup { AssistantHomeView(model: model) }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, let shared = SharedInboxStore().consume() else { return }
                model.ingestShared(shared)
            }
    }
}
