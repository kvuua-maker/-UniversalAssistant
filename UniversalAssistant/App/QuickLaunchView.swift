import SwiftUI

struct QuickLaunchView: View {
    let capabilities: QuickLaunchCapabilities
    private let policy = QuickLaunchPolicy()

    var body: some View {
        List(policy.recommendedMechanisms(capabilities), id: \.self) { mechanism in
            VStack(alignment: .leading, spacing: 4) {
                Label(title(mechanism), systemImage: icon(mechanism)).font(.headline)
                Text(instruction(mechanism)).font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical, 6)
        }
        .navigationTitle("Швидкий запуск")
    }

    private func title(_ value: QuickLaunchMechanism) -> String {
        switch value { case .actionButton: "Action Button"; case .backTap: "Back Tap"; case .appShortcut: "Siri / App Shortcut"; case .homeScreenShortcut: "Home Screen Shortcut"; case .assistiveTouch: "AssistiveTouch" }
    }
    private func icon(_ value: QuickLaunchMechanism) -> String {
        switch value { case .actionButton: "button.programmable"; case .backTap: "hand.tap"; case .appShortcut: "mic.badge.plus"; case .homeScreenShortcut: "square.grid.2x2"; case .assistiveTouch: "accessibility" }
    }
    private func instruction(_ value: QuickLaunchMechanism) -> String {
        switch value {
        case .actionButton: "У системних налаштуваннях призначте UniversalAssistant Voice Mode."
        case .backTap: "У Accessibility призначте Shortcut на подвійний або потрійний дотик."
        case .appShortcut: "Запустіть голосом через Siri або застосунок Shortcuts."
        case .homeScreenShortcut: "Додайте створений Shortcut на Home Screen."
        case .assistiveTouch: "Accessibility fallback: призначте Shortcut у AssistiveTouch."
        }
    }
}
