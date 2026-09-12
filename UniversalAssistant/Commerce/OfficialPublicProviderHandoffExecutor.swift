import Foundation

@MainActor
extension ProductionCanonicalCapabilityExecutor {
    func hasExplicitOfficialPublicProvider(in command: StructuredCommand) -> Bool {
        officialProviderDomains(for: command)
            .flatMap(OfficialPublicProviderHandoffRegistry.records(in:))
            .contains { officialProviderIsExplicit($0, command: command) }
    }

    func officialPublicProviderHandoff(_ command: StructuredCommand) throws -> CapabilityExecutionOutcome {
        let domains = officialProviderDomains(for: command)
        var candidates = domains.flatMap(OfficialPublicProviderHandoffRegistry.records(in:))
        candidates = Array(Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) }).values)
            .sorted { $0.id < $1.id }
        guard !candidates.isEmpty else {
            throw CanonicalCapabilityExecutionError.externalProviderRequired(command.intent.rawValue)
        }

        let explicit = candidates.filter { officialProviderIsExplicit($0, command: command) }
        let selected = explicit.isEmpty ? candidates : explicit
        let query = officialProviderQuery(command)
        let destinations = selected.compactMap { provider -> (OfficialPublicProviderHandoff, URL)? in
            provider.destination(query: query).map { (provider, $0) }
        }
        guard !destinations.isEmpty else {
            throw CanonicalCapabilityExecutionError.externalProviderRequired(command.intent.rawValue)
        }

        if destinations.count == 1, let selected = destinations.first {
            LocalVoiceDiagnosticReport.shared.record(
                "provider_handoff_selected",
                "provider=\(selected.0.id) mechanism=\(selected.0.mechanism) " +
                    "query_preserved=\(selected.0.preservesQuery)"
            )
            return .handoff(.init(query: query, destination: selected.1, kind: .provider))
        }

        let actions = destinations.map { provider, destination in
            ResultAction(
                id: provider.id,
                title: provider.displayName,
                kind: officialProviderActionKind(provider.domain),
                destination: destination
            )
        }
        LocalVoiceDiagnosticReport.shared.record(
            "provider_handoff_selected",
            "provider_count=\(actions.count) mechanism=official_public_handoff " +
                "query_preserved=\(destinations.allSatisfy { $0.0.preservesQuery })"
        )
        let result = try DeterministicResultComposer().compose(
            primaryAnswer: "Оберіть офіційний сервіс для продовження",
            facts: [],
            actions: actions,
            warnings: ["Ціну, наявність і завершення операції підтверджує вибраний сервіс."]
        )
        return .result(result)
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

    private func officialProviderQuery(_ command: StructuredCommand) -> String {
        let domain = command.entities["provider_domain"]
        let preferred: String? = switch domain {
        case "lodging", "car_rental": command.entities["location"] ?? command.entities["destination"]
        default: command.entities["product"] ?? command.entities["query"]
        }
        let value = preferred ?? command.originalText
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? command.originalText : value
    }

    private func officialProviderActionKind(_ domain: OfficialPublicProviderDomain) -> ResultActionKind {
        switch domain {
        case .jobs, .parcel: .open
        case .marketplace, .grocery, .lodging, .carRental, .events, .cinema, .transport: .purchaseHandoff
        }
    }
}
