import SwiftUI

struct CommerceOfferCard: View {
    @Environment(\.locale) private var locale
    let presentation: CommerceOfferPresentation
    let onPurchase: () -> Void

    private var offer: NormalizedOffer { presentation.offer }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                productImage
                VStack(alignment: .leading, spacing: 5) {
                    Text(presentation.title)
                        .font(.headline)
                        .lineLimit(2)
                    if let variant = presentation.variant {
                        Text(variant).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(offer.seller.name).font(.subheadline.weight(.medium))
                }
                Spacer(minLength: 0)
            }

            badgeRow
            priceBlock
            if isHistoricalPriceEvidence {
                Text("Історичне спостереження ціни · \(offer.sourceTimestamp.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label(availabilityKey, systemImage: availabilitySymbol)
                if let deliveryKey { Label(deliveryKey, systemImage: "shippingbox.fill") }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            DisclosureGroup {
                details
            } label: {
                Text("commerce_details").font(.subheadline.weight(.semibold))
            }

            Button(action: onPurchase) {
                Text(isHistoricalPriceEvidence ? "Відкрити джерело" : AppText.value("commerce_buy_at_seller"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(offer.availability == .outOfStock)
            .accessibilityHint(Text("commerce_buy_hint"))
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("commerce.offer.\(offer.id)")
    }

    @ViewBuilder private var productImage: some View {
        AsyncImage(url: offer.imageURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "shippingbox.fill")
                    .resizable().scaledToFit().padding(20).foregroundStyle(.secondary)
            }
        }
        .frame(width: 88, height: 88)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityHidden(true)
    }

    @ViewBuilder private var badgeRow: some View {
        if !presentation.badges.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(presentation.badges, id: \.self) { badge in
                        Text(badgeKey(badge))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }

    private var priceBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(money(offer.cost.item)).font(.title3.bold())
                if let original = offer.originalItemPrice, presentation.discountPercentage != nil {
                    Text(money(original)).strikethrough().font(.subheadline).foregroundStyle(.secondary)
                }
                if let discount = presentation.discountPercentage {
                    Text("−\(discount)%").font(.caption.bold()).foregroundStyle(.green)
                }
            }
            if let total = offer.cost.calculableTotal {
                Text(String(format: AppText.value("commerce_estimated_total_format"), money(total)))
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("commerce_total_unknown").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            costLine("commerce_shipping", offer.cost.shipping)
            costLine("commerce_tax", offer.cost.tax)
            costLine("commerce_duties", offer.cost.duties)
            if let value = offer.seller.returns { detailLine("commerce_returns", value) }
            if let value = offer.seller.warranty { detailLine("commerce_warranty", value) }
            if let value = offer.seller.buyerProtection { detailLine("commerce_protection", value) }
            detailLine("commerce_freshness", LocalizedFormatting.relativeDate(
                offer.sourceTimestamp, relativeTo: .now, locale: locale
            ))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func detailLine(_ key: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(key); Spacer(); Text(value).multilineTextAlignment(.trailing) }
    }

    private func costLine(_ key: LocalizedStringKey, _ component: CostComponent) -> some View {
        detailLine(key, component.value.map(money) ?? AppText.value("commerce_unknown"))
    }

    private func money(_ value: Money) -> String {
        LocalizedFormatting.money(value, locale: locale)
    }

    private var availabilityKey: LocalizedStringKey {
        switch offer.availability {
        case .inStock: "commerce_in_stock"
        case .outOfStock: "commerce_out_of_stock"
        case .preorder: "commerce_preorder"
        case .unknown: "commerce_availability_unknown"
        }
    }

    private var availabilitySymbol: String { offer.availability == .inStock ? "checkmark.circle.fill" : "questionmark.circle" }
    private var isHistoricalPriceEvidence: Bool { offer.providerID == "open-food-facts-open-prices" }
    private var deliveryKey: LocalizedStringKey? {
        switch offer.deliversToUkraine {
        case true: "commerce_delivers_ukraine"
        case false: "commerce_no_ukraine_delivery"
        case nil: nil
        }
    }
    private func badgeKey(_ badge: CommerceOfferBadge) -> LocalizedStringKey {
        switch badge {
        case .bestTotalPrice: "commerce_best_total"
        case .fastestDelivery: "commerce_fastest"
        case .officialStore: "commerce_official_store"
        }
    }
}

enum LocalizedFormatting {
    static func money(_ value: Money, locale: Locale) -> String {
        value.amount.formatted(.currency(code: value.currency).locale(locale))
    }

    static func relativeDate(_ date: Date, relativeTo reference: Date, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        return formatter.localizedString(for: date, relativeTo: reference)
    }
}
