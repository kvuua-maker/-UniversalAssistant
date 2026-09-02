import Foundation

struct SponsoredCampaign: Equatable, Sendable {
    let campaignID: String
    let offerID: String
    let startsAt: Date
    let endsAt: Date
    let budget: Money
    let spent: Money
    let disclosureByLanguageCode: [String: String]
    let enabled: Bool
}

struct SponsoredOfferPlacement: Equatable, Sendable {
    let offer: NormalizedOffer
    let campaignID: String
    let disclosure: String
}

struct SeparatedCommerceResults: Equatable, Sendable {
    let organic: [NormalizedOffer]
    let sponsored: [SponsoredOfferPlacement]
}

enum SponsoredSeparationError: Error, Equatable, Sendable { case invalidCampaign }

struct SponsoredResultSeparator: Sendable {
    private let organicRanker = OfferRanker()

    func separate(offers: [NormalizedOffer], campaigns: [SponsoredCampaign], languageCode: String,
                  now: Date = .now) throws -> SeparatedCommerceResults {
        for campaign in campaigns {
            guard campaign.startsAt < campaign.endsAt,
                  campaign.budget.amount >= 0, campaign.spent.amount >= 0,
                  campaign.budget.currency == campaign.spent.currency else {
                throw SponsoredSeparationError.invalidCampaign
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: offers.map { ($0.id, $0) })
        let sponsored = campaigns.filter {
            $0.enabled && $0.startsAt <= now && now < $0.endsAt && $0.spent.amount < $0.budget.amount
        }.compactMap { campaign -> SponsoredOfferPlacement? in
            guard let offer = byID[campaign.offerID],
                  let disclosure = campaign.disclosureByLanguageCode[languageCode]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !disclosure.isEmpty else { return nil }
            return .init(offer: offer, campaignID: campaign.campaignID, disclosure: disclosure)
        }
        // Every lawful offer remains eligible for organic ranking, including sponsored
        // offers and non-partners; campaign economics never enter the ranker.
        return .init(organic: organicRanker.rank(offers, now: now), sponsored: sponsored)
    }
}
