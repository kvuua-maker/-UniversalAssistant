import SwiftUI

@main
struct UniversalAssistantApp: App {
    @State private var model = AssistantViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AssistantHomeView(model: model)
                .task {
                    _ = model.ingestPendingShare()
                    await PhysicalDiagnosticDelivery.shared.flush()
                }
        }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    model.handleSceneBecameInactive()
                } else if model.ingestPendingShare() {
                    return
                } else {
                    model.handleQuickLaunch()
                }
            }
    }
}
