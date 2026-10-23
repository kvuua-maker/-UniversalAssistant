import SwiftUI

struct CommerceResultsView: View {
    let presentations: [CommerceOfferPresentation]
    let isComplete: Bool
    let onPurchase: (NormalizedOffer) -> Void
    var isFavorite: (String) -> Bool = { _ in false }
    var onToggleFavorite: ((CommerceOfferPresentation) -> Void)? = nil

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(presentations) { presentation in
                VStack(alignment: .trailing, spacing: 6) {
                    CommerceOfferCard(presentation: presentation) {
                        onPurchase(presentation.offer)
                    }
                    if let onToggleFavorite {
                        Button {
                            onToggleFavorite(presentation)
                        } label: {
                            Image(
                                systemName: isFavorite("product:\(presentation.offer.id)")
                                    ? "star.fill" : "star")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(
                            Text(
                                isFavorite("product:\(presentation.offer.id)")
                                    ? "Видалити з обраного" : "Додати в обране"))
                    }
                }
            }
            if !isComplete { ProgressView().padding().accessibilityLabel(Text("commerce_loading_more")) }
        }
        .animation(.snappy, value: presentations.map(\.id))
    }
}
