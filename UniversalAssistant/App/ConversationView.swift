import SwiftUI

struct ConversationView: View {
    private var store: ConversationStore { ConversationStore.shared }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if store.messages.isEmpty {
                            Text("Тут з'являться ваші команди та відповіді")
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                        }
                        ForEach(store.messages) { message in
                            bubble(message).id(message.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: store.messages.count) { _, _ in
                    if let last = store.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .navigationTitle("Розмова")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Очистити", role: .destructive) { store.clear() }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: ConversationStore.Message) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(background(for: message.role), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(message.role == .user ? .white : .primary)
                .textSelection(.enabled)
            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private func background(for role: ConversationStore.Role) -> Color {
        switch role {
        case .user: .accentColor
        case .assistant: Color.secondary.opacity(0.15)
        case .status: Color.green.opacity(0.15)
        }
    }
}
