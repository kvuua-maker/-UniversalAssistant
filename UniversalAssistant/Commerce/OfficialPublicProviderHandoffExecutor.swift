import Foundation

@MainActor
extension ProductionCanonicalCapabilityExecutor {
    func hasExplicitOfficialPublicProvider(in command: StructuredCommand) -> Bool {
        officialProviderDomains(for: command)
            .flatMap(OfficialPublicProviderHandoffRegistry.records(in:))
            .contains { officialProviderIsExplicit($0, command: command) }
    }

    func officialPublicProviderHandoff(
        _ command: StructuredCommand,
        routingDecision: CanonicalRoutingDecision
    ) throws -> CapabilityExecutionOutcome {
        let policy = routingDecision
        let domains = officialProviderDomains(for: command)
        var candidates = domains.flatMap(OfficialPublicProviderHandoffRegistry.records(in:))
        if let policyID = policy.providerID,
           let policyProvider = OfficialPublicProviderHandoffRegistry.records.first(where: { $0.id == policyID }) {
            candidates.append(policyProvider)
        }
        candidates = candidates.reduce(into: [String: OfficialPublicProviderHandoff]()) { unique, candidate in
            if unique[candidate.id] == nil { unique[candidate.id] = candidate }
        }.values.sorted { $0.id < $1.id }
        guard !candidates.isEmpty else {
            throw CanonicalCapabilityExecutionError.externalProviderRequired(command.intent.rawValue)
        }

        let explicit = candidates.filter { officialProviderIsExplicit($0, command: command) }
        let policySelected = policy.providerID.flatMap { id in candidates.first(where: { $0.id == id }) }
        let selected: [OfficialPublicProviderHandoff]
        if !explicit.isEmpty {
            selected = explicit
        } else if let policySelected {
            selected = [policySelected]
        } else if policy.allowsMultipleResults {
            selected = candidates
        } else {
            throw CanonicalCapabilityExecutionError.externalProviderRequired("deterministic_provider_selection_required")
        }
        let query = officialProviderQuery(command, selectedProviderOrBrand: selected.first?.displayName)
        let destinations = try selected.compactMap { provider -> (OfficialPublicProviderHandoff, PurchaseHandoff)? in
            guard let exact = officialProviderDestination(provider, command: command, query: query) else { return nil }
            let routed = try AffiliatePurchaseRouter().route(
                providerID: provider.id,
                exactDestination: exact,
                configuration: affiliateConfigurations[provider.id],
                requestID: command.id
            )
            return (provider, routed)
        }
        guard !destinations.isEmpty else {
            throw CanonicalCapabilityExecutionError.externalProviderRequired(command.intent.rawValue)
        }

        if destinations.count == 1, let selected = destinations.first {
            let monetization = CanonicalPartnerPolicyRegistry.policy(for: selected.0.id)?.decision.rawValue ?? "UNKNOWN"
            LocalVoiceDiagnosticReport.shared.record(
                "provider_handoff_selected",
                "provider=\(selected.0.id) mechanism=\(selected.0.mechanism) " +
                    "query_preserved=\(providerPreservesRequestedContext(selected.0, command: command)) " +
                    "policy_lane=\(policy.lane.rawValue) policy_reason=\(policy.reason) " +
                    "attribution=\(selected.1.attribution.rawValue) monetization=\(monetization) " +
                    "destination=\(selected.1.destination.absoluteString)"
            )
            return .handoff(.init(
                query: query,
                destination: selected.1.destination,
                kind: .provider,
                requiresExplicitUserActivation: selected.1.requiresExplicitUserActivation
            ))
        }

        // Multiple destinations are permitted only for an explicit comparison.
        let actions = destinations.map { provider, handoff in
            ResultAction(
                id: provider.id,
                title: provider.displayName,
                kind: officialProviderActionKind(provider.domain),
                destination: handoff.destination
            )
        }
        LocalVoiceDiagnosticReport.shared.record(
            "provider_handoff_selected",
            "provider_count=\(actions.count) mechanism=official_public_handoff " +
                "query_preserved=\(destinations.allSatisfy { $0.0.preservesQuery }) attribution=mixed_or_not_configured"
        )
        let result = try DeterministicResultComposer().compose(
            primaryAnswer: "Порівняння офіційних сервісів",
            facts: [],
            actions: actions,
            warnings: ["Ціну, наявність і завершення операції підтверджує вибраний сервіс."]
        )
        return .result(result)
    }

    func officialBrandHandoff(_ command: StructuredCommand) throws -> CapabilityExecutionOutcome {
        let explicit = command.constraints.brand ?? command.entities["brand"]
        guard let brand = explicit.flatMap({ BrandOfficialDestinationRegistry.match($0) })
                ?? BrandOfficialDestinationRegistry.match(inText: command.originalText) else {
            throw CanonicalCapabilityExecutionError.externalProviderRequired("official_brand_destination_unavailable")
        }
        let query = officialProviderQuery(command, selectedProviderOrBrand: brand.displayName)
        guard let exact = brand.route.destination(query: query) else {
            throw CanonicalCapabilityExecutionError.externalProviderRequired("official_brand_destination_invalid")
        }
        LocalVoiceDiagnosticReport.shared.record(
            "provider_handoff_selected",
            "provider=\(brand.id) mechanism=official_brand_destination query_preserved=\(brand.route.preservesQuery) " +
                "attribution=unattributed destination=\(exact.absoluteString)"
        )
        return .handoff(.init(query: query, destination: exact, kind: .provider))
    }

    private func officialProviderDestination(
        _ provider: OfficialPublicProviderHandoff,
        command: StructuredCommand,
        query: String
    ) -> URL? {
        if provider.id == "events.karabas" {
            guard let city = command.entities["location"] ?? command.entities["destination"] else { return nil }
            return KarabasOfficialCityRoute.destination(for: city, command: command)
        }
        guard let destination = provider.destination(query: query) else { return nil }
        guard provider.id == "lodging.booking",
              var components = URLComponents(url: destination, resolvingAgainstBaseURL: false) else { return destination }
        var items = components.queryItems ?? []
        let supported = [
            ("checkin", command.entities["checkin"] ?? command.entities["start_date"]),
            ("checkout", command.entities["checkout"] ?? command.entities["end_date"]),
            ("group_adults", command.entities["guest_count"] ?? command.entities["party_size"]),
            ("no_rooms", command.entities["room_count"])
        ]
        for (name, value) in supported where value?.isEmpty == false {
            items.removeAll { $0.name == name }
            items.append(.init(name: name, value: value))
        }
        components.queryItems = items
        return components.url
    }

    private func providerPreservesRequestedContext(
        _ provider: OfficialPublicProviderHandoff,
        command: StructuredCommand
    ) -> Bool {
        if provider.id == "events.karabas" {
            guard let city = command.entities["location"] ?? command.entities["destination"] else { return false }
            // The public fallback preserves a verified city and, where an
            // official category path exists, the category. It must not claim
            // arbitrary artist/date-query preservation without partner API.
            return KarabasOfficialCityRoute.destination(for: city, command: command) != nil &&
                KarabasOfficialCityRoute.preservesEveryConstraint(in: command)
        }
        return provider.preservesQuery
    }

    private func officialProviderDomains(for command: StructuredCommand) -> [OfficialPublicProviderDomain] {
        if let providerDomain = command.entities["provider_domain"] {
            switch providerDomain {
            case "product_catalog": return [.marketplace]
            case "grocery_delivery": return [.grocery]
            case "jobs": return [.jobs]
            case "car_rental": return [.carRental]
            case "lodging": return [.lodging]
            case "tickets": return [.events, .cinema]
            case "transport_tickets": return [.transport]
            case "parcel_tracking": return [.parcel]
            default: return []
            }
        }
        switch command.intent {
        case .productSearch, .fashionDiscovery: return [.marketplace]
        case .groceryBasket: return [.grocery]
        case .hotelSearch: return [.lodging]
        case .ticketSearch, .ticketPurchaseHandoff: return [.events, .cinema, .transport]
        case .parcelTrack: return [.parcel]
        case .travelPlan: return [.lodging, .transport, .carRental]
        default: return []
        }
    }

    private func officialProviderIsExplicit(
        _ provider: OfficialPublicProviderHandoff,
        command: StructuredCommand
    ) -> Bool {
        if command.entities["catalog_entity_id"] == provider.id { return true }
        let explicitValues = [command.entities["provider"], command.entities["retailer"]]
            .compactMap { $0 }
            .map(officialProviderComparable)
        let aliases = (provider.aliases.union([provider.displayName])).map(officialProviderComparable)
        if explicitValues.contains(where: aliases.contains) { return true }
        let text = " \(officialProviderComparable(command.originalText)) "
        return aliases.contains { alias in !alias.isEmpty && text.contains(" \(alias) ") }
    }

    private func officialProviderComparable(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    private func officialProviderQuery(_ command: StructuredCommand, selectedProviderOrBrand: String? = nil) -> String {
        let domain = command.entities["provider_domain"]
        let preferred: String? = switch domain {
        case "lodging", "car_rental": command.entities["location"] ?? command.entities["destination"]
        default: command.entities["product"] ?? command.entities["query"]
        }
        var parts = [CanonicalProductQueryBuilder.query(for: command, selectedProviderOrBrand: selectedProviderOrBrand)]
        if ["lodging", "car_rental"].contains(domain), let preferred { parts = [preferred] }
        let constraints: [String?] = [
            command.constraints.brand,
            command.constraints.category,
            command.constraints.color,
            command.constraints.size.map { "size \($0)" },
            command.constraints.maximumPrice.map { "up to \($0) \(command.constraints.currency ?? "")" },
            command.entities["location"], command.entities["delivery_constraint"]
        ]
        for value in constraints.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) where !value.isEmpty {
            let comparableValue = officialProviderComparable(value)
            if !parts.contains(where: { officialProviderComparable($0).contains(comparableValue) }) {
                parts.append(value)
            }
        }
        let value = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? command.originalText : value
    }

    private func officialProviderActionKind(_ domain: OfficialPublicProviderDomain) -> ResultActionKind {
        switch domain {
        case .jobs, .parcel: .open
        case .marketplace, .grocery, .lodging, .carRental, .events, .cinema, .transport: .purchaseHandoff
        }
    }
}

enum KarabasOfficialCityRoute {
    private static let verifiedSlugs: [String: String] = [
        "київ": "kyiv", "киев": "kyiv", "kyiv": "kyiv", "kiev": "kyiv",
        "львів": "lviv", "львов": "lviv", "lviv": "lviv",
        "полтава": "poltava", "poltava": "poltava",
        "черкаси": "cherkasy", "черкассы": "cherkasy", "cherkasy": "cherkasy"
    ]

    static func destination(for city: String, command: StructuredCommand? = nil) -> URL? {
        let normalized = CanonicalLocalityNormalizer.normalize(city)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slug = verifiedSlugs[normalized] else { return nil }
        let path = command.flatMap(verifiedCategoryPath) ?? ""
        return URL(string: "https://\(slug).karabas.com/\(path)")
    }

    static func preservesEveryConstraint(in command: StructuredCommand) -> Bool {
        let hasUnrepresentedDate = ["date", "calendar_day", "time", "start_date"]
            .contains { command.entities[$0]?.isEmpty == false }
        let genericQuery = command.entities["query"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSpecificQuery = genericQuery.map { !genericEventTerms.contains(comparable($0)) } ?? false
        return !hasUnrepresentedDate && !hasSpecificQuery
    }

    private static func verifiedCategoryPath(_ command: StructuredCommand) -> String? {
        let value = comparable([
            command.constraints.category,
            command.entities["category"],
            command.entities["event_category"],
            command.entities["query"],
            command.normalizedText
        ].compactMap { $0 }.joined(separator: " "))
        if ["дит", "child", "kid"].contains(where: value.contains) { return "kids/" }
        if ["театр", "theatre", "theater", "вистав", "спектак"].contains(where: value.contains) { return "theatres/" }
        if ["стендап", "stand up", "standup"].contains(where: value.contains) { return "stand-up/" }
        if ["концерт", "concert", "музик"].contains(where: value.contains) { return "concerts/" }
        return nil
    }

    private static let genericEventTerms: Set<String> = [
        "подія", "подии", "event", "events", "концерт", "concert", "вистава", "театр",
        "дитяча вистава", "stand up", "стендап"
    ]

    private static func comparable(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
}
