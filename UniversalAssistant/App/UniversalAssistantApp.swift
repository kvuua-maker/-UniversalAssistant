import SwiftUI

@main
struct UniversalAssistantApp: App {
    @State private var model = AssistantViewModel()

    var body: some Scene {
        WindowGroup { AssistantHomeView(model: model) }
    }
}
