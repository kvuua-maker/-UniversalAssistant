import Foundation

struct GenericMoneyConstraint: Equatable, Codable, Sendable {
    var minimum: Decimal?; var maximum: Decimal?; var currency: String?
}
struct GenericLocationConstraint: Equatable, Codable, Sendable {
    var locality: String?; var nearCurrentLocation: Bool = false
}
struct GenericTimeWindow: Equatable, Codable, Sendable {
    var start: Date?; var end: Date?; var relativeExpression: String?
}
struct GenericIntent: Equatable, Codable, Sendable {
    var domain: String; var subject: String; var goal: String
    var location: GenericLocationConstraint?; var timeWindow: GenericTimeWindow?; var money: GenericMoneyConstraint?
    var quantity: Int?; var maximumDistanceMeters: Double?; var maximumDuration: TimeInterval?; var minimumRating: Double?
    var brandOrProvider: String?; var includes: [String] = []; var excludes: [String] = []; var sorting: String?
    var requiredFreshness: TimeInterval?; var requestedAction: String?; var risk: ActionRisk = .informational
    var metadata: [String: String] = [:]

    func validated() throws -> Self {
        let bounded = [domain, subject, goal].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 200 }
        guard bounded, metadata.count <= 12, metadata.allSatisfy({ $0.key.count <= 40 && $0.value.count <= 160 }),
              money?.minimum.map({ $0 >= 0 }) ?? true, money?.maximum.map({ $0 >= 0 }) ?? true,
              quantity.map({ $0 > 0 }) ?? true, minimumRating.map({ (0...5).contains($0) }) ?? true else { throw GenericDiscoveryError.invalidIntent }
        return self
    }
}

struct GenericIntentParser: Sendable {
    func parse(_ text: String, now: Date = .now) throws -> GenericIntent {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines), lower = value.lowercased()
        guard !value.isEmpty else { throw GenericDiscoveryError.ambiguous("Що саме потрібно знайти?") }
        if ["щось атмосферне", "щось цікаве", "something suitable"].contains(lower) { throw GenericDiscoveryError.ambiguous("Що саме ви хочете знайти?") }
        var domain = "general", goal = "find", subject = value
        if lower.contains("робот") || lower.contains("ваканс") { domain = "jobs"; goal = "find_job"; subject = capture(after: ["роботу", "вакансію"], in: value) ?? value }
        else if lower.contains("курс") || lower.contains("школ") { domain = "education"; goal = "find_course" }
        else if lower.contains("поді") || lower.contains("фестивал") { domain = "events"; goal = "find_event" }
        else if lower.contains("майстр") || lower.contains("відремонт") || lower.contains("сервіс") { domain = "local_service"; goal = "find_service" }
        else if lower.hasPrefix("коли") || lower.hasPrefix("які документи") || lower.hasPrefix("скільки") { domain = "factual"; goal = "answer" }
        var intent = GenericIntent(domain: domain, subject: subject, goal: goal)
        if lower.contains("поруч") || lower.contains("біля мене") || lower.contains("моєму місті") { intent.location = .init(locality: nil, nearCurrentLocation: true) }
        for (spoken, canonical) in ["Києві": "Київ", "Львові": "Львів", "Берліні": "Берлін", "Парижі": "Париж"] where value.localizedCaseInsensitiveContains(spoken) { intent.location = .init(locality: canonical, nearCurrentLocation: false) }
        if lower.contains("сьогодні") { intent.timeWindow = .init(start: Calendar.current.startOfDay(for: now), end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)), relativeExpression: "today") }
        else if lower.contains("наступними вихідними") { intent.timeWindow = .init(relativeExpression: "next_weekend") }
        let numbers = lower.replacingOccurrences(of: " ", with: "").split(whereSeparator: { !$0.isNumber }).compactMap { Decimal(string: String($0)) }
        if let amount = numbers.first, lower.contains("від") { intent.money = .init(minimum: amount, maximum: nil, currency: currency(lower)) }
        else if let amount = numbers.first, lower.contains("до") || lower.contains("дешевше") { intent.money = .init(minimum: nil, maximum: amount, currency: currency(lower)) }
        intent.requiredFreshness = ["jobs", "events", "local_service"].contains(domain) ? 86_400 : 604_800
        intent.requestedAction = "open"; return try intent.validated()
    }
    private func currency(_ text: String) -> String? { text.contains("грн") ? "UAH" : text.contains("€") || text.contains("eur") ? "EUR" : nil }
    private func capture(after words: [String], in text: String) -> String? {
        words.compactMap { text.range(of: $0, options: .caseInsensitive).map { String(text[$0.upperBound...]).trimmingCharacters(in: .whitespaces) } }.first
    }
}

enum GenericSourceKind: String, Codable, Sendable { case officialPrimary, government, authorizedFeed, structuredMarketplace, reputableSecondary, generalWeb }
struct GenericSourceEvidence: Equatable, Codable, Sendable { let url: URL; let kind: GenericSourceKind; let retrievedAt: Date; let publishedAt: Date?; let confidence: Double }
struct GenericEntity: Identifiable, Equatable, Sendable {
    let id: String; let title: String; let entityType: String; let facts: [String: String]
    let evidence: GenericSourceEvidence; let actionURL: URL; var variantID: String?
}
struct GenericDiscoveryDocument: Sendable { let response: RetailPageResponse; let sourceKind: GenericSourceKind }
protocol GenericDiscoveryProvider: Sendable { var id: String { get }; func discover(_ intent: GenericIntent, query: String) async throws -> [GenericDiscoveryDocument] }
protocol GenericSpecializedResolver: Sendable { func resolve(_ command: StructuredCommand) async -> DeterministicResult? }
protocol GenericAIIntentResolver: Sendable { func resolve(_ text: String) async throws -> GenericIntent }

struct ConfiguredGenericWebDiscoveryProvider: GenericDiscoveryProvider, Sendable {
    let id: String; let endpoint: URL; let bearerToken: String
    let transport: any RetailDiscoveryTransport; let pageRetriever: any RetailPageRetrieving
    var maximumPages = 8
    func discover(_ intent: GenericIntent, query: String) async throws -> [GenericDiscoveryDocument] {
        guard endpoint.scheme?.lowercased() == "https", endpoint.host != nil, !bearerToken.isEmpty, (1...20).contains(maximumPages) else { throw RetailPageFailure.invalidURL }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "q", value: query), .init(name: "limit", value: String(maximumPages))]
        guard let url = components?.url else { throw RetailPageFailure.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let raw = root["results"] as? [[String: Any]] else { throw RetailPageFailure.unavailable }
        let candidates: [(URL, GenericSourceKind)] = raw.compactMap { item -> (URL, GenericSourceKind)? in
            guard let value = item["url"] as? String, let url = URL(string: value), URLSessionRetailPageRetriever.allowed(url) else { return nil }
            return (url, (item["source_kind"] as? String).flatMap(GenericSourceKind.init(rawValue:)) ?? .generalWeb)
        }.reduce(into: []) { result, candidate in
            if !result.contains(where: { $0.0.absoluteString == candidate.0.absoluteString }) { result.append(candidate) }
        }
        guard !candidates.isEmpty else { throw RetailPageFailure.unavailable }
        return await withTaskGroup(of: GenericDiscoveryDocument?.self) { group in
            for (url, kind) in candidates.prefix(maximumPages) { group.addTask { guard let page = try? await pageRetriever.retrieve(url) else { return nil }; return .init(response: page, sourceKind: kind) } }
            var documents: [GenericDiscoveryDocument] = []; for await document in group { if let document { documents.append(document) } }; return documents
        }
    }
}

enum GenericDiscoveryError: Error, Equatable { case invalidIntent, ambiguous(String), allSourcesFailed, unsafeAction, noTrustworthyResults }

struct GenericQuerySanitizer: Sendable {
    func query(for intent: GenericIntent) throws -> String {
        // goal is an internal semantic operator, not user-authored query text.
        // Excluding it prevents an artificial English prefix while preserving a user-authored "find".
        var pieces = [intent.subject, intent.location?.locality, intent.timeWindow?.relativeExpression,
                      intent.money?.minimum.map(String.init(describing:)), intent.money?.maximum.map(String.init(describing:)), intent.money?.currency].compactMap { $0 }
        let forbidden = ["@", "calendar", "contact:", "loyalty", "password", "token", "latitude", "longitude"]
        pieces.removeAll { piece in forbidden.contains(where: { piece.lowercased().contains($0) }) }
        let result = pieces.joined(separator: " ").prefix(300)
        guard !result.isEmpty else { return "information" }; return String(result)
    }
}

struct GenericStructuredExtractor: Sendable {
    func extract(_ document: GenericDiscoveryDocument) throws -> [GenericEntity] {
        let html = document.response.html, lower = html.lowercased()
        if lower.contains("captcha") || lower.contains("verify you are human") { throw RetailPageFailure.captcha }
        if lower.contains("login required") || lower.contains("access denied") { throw RetailPageFailure.blocked }
        let pattern = #"<script[^>]*type\s*=\s*[\"']application/ld\+json[\"'][^>]*>([\s\S]*?)</script>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive]); let source = html as NSString
        let objects = regex.matches(in: html, range: NSRange(location: 0, length: source.length)).flatMap { match -> [[String: Any]] in
            guard let data = source.substring(with: match.range(at: 1)).data(using: .utf8), let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
            return flatten(root)
        }
        return objects.compactMap { object in
            guard let title = string(object["title"] ?? object["name"] ?? object["headline"]), !title.isEmpty else { return nil }
            let type = string(object["@type"]) ?? "Thing", urlString = string(object["url"]) ?? document.response.finalURL.absoluteString
            guard let url = URL(string: urlString, relativeTo: document.response.finalURL)?.absoluteURL, URLSessionRetailPageRetriever.allowed(url) else { return nil }
            var facts: [String: String] = [:]
            for key in ["description", "datePosted", "startDate", "employmentType", "price", "priceCurrency", "address", "salary"] { if let value = string(object[key]) { facts[key] = value } }
            let published = ["dateModified", "datePosted", "startDate"].compactMap { string(object[$0]) }.compactMap(ISO8601DateFormatter().date).first
            let evidence = GenericSourceEvidence(url: url, kind: document.sourceKind, retrievedAt: document.response.fetchedAt, publishedAt: published ?? document.response.sourceTimestamp, confidence: document.sourceKind == .officialPrimary ? 1 : 0.75)
            return .init(id: "\(url.host ?? "source"):\(title.lowercased())", title: title, entityType: type, facts: facts, evidence: evidence, actionURL: url, variantID: string(object["sku"] ?? object["identifier"]))
        }
    }
    private func flatten(_ value: Any) -> [[String: Any]] { if let a = value as? [Any] { return a.flatMap(flatten) }; guard let o = value as? [String: Any] else { return [] }; if let graph = o["@graph"] { return flatten(graph) }; return [o] }
    private func string(_ value: Any?) -> String? { if let s = value as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }; if let n = value as? NSNumber { return n.stringValue }; if let o = value as? [String: Any] { return string(o["value"] ?? o["name"]) }; return nil }
}

actor GenericSemanticCache {
    private struct Entry { let expiresAt: Date; let entities: [GenericEntity] }; private var values: [String: Entry] = [:]
    func key(_ intent: GenericIntent) throws -> String { String(data: try JSONEncoder().encode(intent), encoding: .utf8)! }
    func get(_ intent: GenericIntent, now: Date) throws -> [GenericEntity]? { guard let e = values[try key(intent)], e.expiresAt > now else { return nil }; return e.entities }
    func put(_ entities: [GenericEntity], for intent: GenericIntent, now: Date) throws { values[try key(intent)] = .init(expiresAt: now.addingTimeInterval(intent.requiredFreshness ?? 300), entities: entities) }
}

struct GenericUnknownRequestCoordinator: Sendable {
    let providers: [any GenericDiscoveryProvider]; let cache: GenericSemanticCache; var ai: (any GenericAIIntentResolver)?
    func execute(text: String, parsed: StructuredCommand, specialized: (any GenericSpecializedResolver)? = nil, now: Date = .now) async throws -> DeterministicResult {
        if parsed.intent != .unknown, let result = await specialized?.resolve(parsed) { return result }
        let intent: GenericIntent
        let aiInvocationCount: Int
        if parsed.intent == .unknown, let ai {
            intent = try await ai.resolve(text).validated(); aiInvocationCount = 1
        } else {
            do { intent = try GenericIntentParser().parse(text, now: now); aiInvocationCount = 0 }
            catch { if let ai { intent = try await ai.resolve(text).validated(); aiInvocationCount = 1 } else { throw error } }
        }
        if intent.risk != .informational || ![nil, "open", "view"].contains(intent.requestedAction) { throw GenericDiscoveryError.unsafeAction }
        if let cached = try await cache.get(intent, now: now) { return try compose(cached, partial: false, aiInvocationCount: aiInvocationCount) }
        let query = try GenericQuerySanitizer().query(for: intent)
        let batches = await withTaskGroup(of: [GenericEntity]?.self) { group in
            for provider in providers { group.addTask { guard let docs = try? await provider.discover(intent, query: query) else { return nil }; return docs.flatMap { (try? GenericStructuredExtractor().extract($0)) ?? [] } } }
            var result: [[GenericEntity]?] = []; for await batch in group { result.append(batch) }; return result
        }
        let succeeded = batches.compactMap { $0 }; guard !succeeded.isEmpty else { throw GenericDiscoveryError.allSourcesFailed }
        let fresh = succeeded.flatMap { $0 }.filter { entity in now.timeIntervalSince(entity.evidence.publishedAt ?? entity.evidence.retrievedAt) <= (intent.requiredFreshness ?? 604_800) }
        let ranked = resolve(fresh); guard !ranked.isEmpty else { throw GenericDiscoveryError.noTrustworthyResults }
        try await cache.put(ranked, for: intent, now: now); return try compose(ranked, partial: succeeded.count < providers.count, aiInvocationCount: aiInvocationCount)
    }
    private func resolve(_ entities: [GenericEntity]) -> [GenericEntity] {
        Dictionary(grouping: entities, by: { "\($0.title.lowercased())|\($0.variantID ?? "")" }).values.compactMap { group in group.max { lhs, rhs in score(lhs.evidence) < score(rhs.evidence) } }.sorted { score($0.evidence) > score($1.evidence) }
    }
    private func score(_ e: GenericSourceEvidence) -> Double { Double([.officialPrimary: 6, .government: 6, .authorizedFeed: 5, .structuredMarketplace: 4, .reputableSecondary: 3, .generalWeb: 2][e.kind]!) + e.confidence }
    private func compose(_ entities: [GenericEntity], partial: Bool, aiInvocationCount: Int) throws -> DeterministicResult {
        let shortlist = Array(entities.prefix(3))
        let facts = shortlist.enumerated().map { index, entity in ResultFact(id: entity.id, label: entity.title, value: entity.facts.values.first ?? entity.entityType, state: .verified, source: "\(entity.evidence.kind.rawValue):\(entity.evidence.url.host ?? "source")", observedAt: entity.evidence.retrievedAt, priority: 100 - index) }
        var actions = shortlist.map { ResultAction(id: $0.id, title: "Відкрити", kind: .open, destination: $0.actionURL) }
        if entities.count > shortlist.count { actions.append(.init(id: "show-more", title: "Показати ще", kind: .showMore, destination: nil)) }
        let result = try DeterministicResultComposer().compose(primaryAnswer: "Знайдено перевірені результати", facts: facts, actions: actions, warnings: partial ? ["Частина джерел недоступна"] : [])
        return .init(primaryAnswer: result.primaryAnswer, facts: result.facts, actions: result.actions, warnings: result.warnings, aiInvocationCount: aiInvocationCount)
    }
}

struct GenericUnknownJourney: Equatable, Sendable { let request: String; let expectedDomain: String?; let expectedOutcome: String }
enum GenericUnknownJourneyCatalog {
    static let canonical: [GenericUnknownJourney] = [
        .init(request: "Знайди мені роботу водієм у Києві від 40 000 грн", expectedDomain: "jobs", expectedOutcome: "structured_results"),
        .init(request: "Знайди майстра поруч, який сьогодні може відремонтувати бойлер", expectedDomain: "local_service", expectedOutcome: "structured_results"),
        .init(request: "Знайди курси німецької до 5 000 грн на місяць", expectedDomain: "education", expectedOutcome: "structured_results"),
        .init(request: "Які цікаві події будуть у Києві наступними вихідними", expectedDomain: "events", expectedOutcome: "structured_results"),
        .init(request: "Скільки зараз коштує металобрухт у моєму місті", expectedDomain: "factual", expectedOutcome: "verified_answer"),
        .init(request: "Коли краще садити помідори", expectedDomain: "factual", expectedOutcome: "verified_answer"),
        .init(request: "Щось цікаве", expectedDomain: nil, expectedOutcome: "one_clarification"),
        .init(request: "Де відремонтувати кавоварку", expectedDomain: "local_service", expectedOutcome: "no_ai_results"),
        .init(request: "Щось атмосферне", expectedDomain: nil, expectedOutcome: "bounded_ai_over_verified_sources"),
        .init(request: "Яка актуальна ціна невідомої послуги", expectedDomain: "general", expectedOutcome: "truthful_unknown_when_unverified")
    ]
}
