import SwiftUI

struct CommerceResultsView: View {
    let presentations: [CommerceOfferPresentation]
    let isComplete: Bool
    let onPurchase: (NormalizedOffer) -> Void

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(presentations) { presentation in
                CommerceOfferCard(presentation: presentation) {
                    onPurchase(presentation.offer)
                }
            }
            if !isComplete { ProgressView().padding().accessibilityLabel(Text("commerce_loading_more")) }
        }
        .animation(.snappy, value: presentations.map(\.id))
    }
}
