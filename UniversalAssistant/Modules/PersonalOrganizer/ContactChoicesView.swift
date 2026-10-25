import SwiftUI
import ContactsUI

/// Shown when a name matches several contacts: the user picks the right person
/// instead of the app guessing.
struct ContactChoicesView: View {
    let candidates: [ContactCandidate]
    let onSelect: (ContactCandidate) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List(candidates, id: \.identifier) { candidate in
                Button {
                    onSelect(candidate)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color.accentColor.opacity(0.15))
                            Text(initials(for: candidate.displayName))
                                .font(.headline)
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.displayName)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            if let phone = candidate.phoneNumbers.first {
                                Text(phone)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Кого ви мали на увазі?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Скасувати") { onCancel() }
                }
            }
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}
