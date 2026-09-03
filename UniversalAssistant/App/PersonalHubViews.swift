import SwiftUI

struct MyTasksView: View {
    let items: [PersonalTaskItem]
    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty { ContentUnavailableView("my_tasks", systemImage: "checklist") }
                else {
                    List(items) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.requiresAttention ? "exclamationmark.circle.fill" : "checklist")
                                .foregroundStyle(item.requiresAttention ? .orange : .secondary)
                            VStack(alignment: .leading) {
                                Text(item.title).font(.headline)
                                Text(item.status.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityElement(children: .combine)
                    }
                }
            }.navigationTitle("my_tasks")
        }
    }
}

struct FavoritesView: View {
    let favorites: [FavoriteReference]
    var body: some View {
        NavigationStack {
            Group {
                if favorites.isEmpty { ContentUnavailableView("favorites", systemImage: "star") }
                else {
                    List(favorites) { favorite in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(favorite.displayTitle).font(.headline)
                            if let subtitle = favorite.displaySubtitle { Text(subtitle).foregroundStyle(.secondary) }
                            Text(favorite.freshness.rawValue).font(.caption).foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine)
                    }
                }
            }.navigationTitle("favorites")
        }
    }
}
