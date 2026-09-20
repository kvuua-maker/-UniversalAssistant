import Foundation

enum JobResultTier: String, Codable, Sendable {
  case directEmployer, verifiedCommercial, externalFallback
}
struct JobDiscoveryResult: Identifiable, Equatable, Codable, Sendable {
  let id: String
  let title: String
  let employer: String
  let locality: String?
  let salaryMinimum, salaryMaximum: Decimal?
  let currency, salaryBasis: String?
  let employmentType: String?
  let publishedAt, observedAt: Date
  let sourceName: String
  let sourceURL: URL
  let tier: JobResultTier
  let commercialEvidenceID: String?
  let confidence: Double
}
protocol JobDiscoveryProvider: Sendable {
  var id: String { get }
  var tier: JobResultTier { get }
  func search(_ intent: GenericIntent) async throws -> [JobDiscoveryResult]
}
struct UkrainianJobSource: Equatable, Sendable {
  let id, name: String
  let url: URL
  let mechanism: String
  let publicDiscoveryAllowed: Bool
  let authenticatedAPI: Bool
}
enum UkrainianJobSourceRegistry {
  static let audited: [UkrainianJobSource] = [
    .init(
      id: "workua", name: "Work.ua", url: URL(string: "https://www.work.ua/jobs/")!,
      mechanism: "public_https_handoff", publicDiscoveryAllowed: true, authenticatedAPI: false),
    .init(
      id: "robotaua", name: "robota.ua", url: URL(string: "https://robota.ua/zapros/")!,
      mechanism: "blocked_public_page_handoff", publicDiscoveryAllowed: false,
      authenticatedAPI: false),
    .init(
      id: "jobsua", name: "Jobs.ua", url: URL(string: "https://jobs.ua/vacancy")!,
      mechanism: "public_https_handoff", publicDiscoveryAllowed: true, authenticatedAPI: false),
    .init(
      id: "dcz", name: "Державна служба зайнятості",
      url: URL(string: "https://dcz.gov.ua/userSearch/vacancy")!,
      mechanism: "official_public_handoff", publicDiscoveryAllowed: true, authenticatedAPI: false),
    .init(
      id: "djinni", name: "Djinni", url: URL(string: "https://djinni.co/jobs/")!,
      mechanism: "public_https_handoff", publicDiscoveryAllowed: true, authenticatedAPI: false),
    .init(
      id: "dou", name: "DOU Jobs", url: URL(string: "https://jobs.dou.ua/")!,
      mechanism: "public_https_handoff", publicDiscoveryAllowed: true, authenticatedAPI: false),
    .init(
      id: "happymonday", name: "Happy Monday",
      url: URL(string: "https://happymonday.ua/jobs-search")!,
      mechanism: "public_reference_handoff", publicDiscoveryAllowed: true, authenticatedAPI: false),
  ]
}
enum JobDiscoveryError: Error, Equatable { case invalidIntent, noVerifiedResults }
struct JobDiscoveryEngine: Sendable {
  let providers: [any JobDiscoveryProvider]
  func searchResults(_ intent: GenericIntent, minimumPreferredResults: Int = 3) async throws
    -> [JobDiscoveryResult]
  {
    guard intent.domain == "jobs", intent.risk == .informational else {
      throw JobDiscoveryError.invalidIntent
    }
    let preferredProviders = providers.filter { $0.tier != .externalFallback }
    let preferred = await fetch(preferredProviders, intent)
    let eligiblePreferred = normalize(preferred, intent: intent)
    let external = eligiblePreferred.count >= minimumPreferredResults
      ? [] : await fetch(providers.filter { $0.tier == .externalFallback }, intent)
    let results = Array(normalize(eligiblePreferred + external, intent: intent).prefix(10))
    guard !results.isEmpty else { throw JobDiscoveryError.noVerifiedResults }
    return results
  }

  func search(_ intent: GenericIntent, minimumPreferredResults: Int = 3) async throws
    -> DeterministicResult
  {
    let results = try await searchResults(intent, minimumPreferredResults: minimumPreferredResults)
    let facts = results.map { result in
      let salary = formattedSalary(result)
      return ResultFact(
        id: result.id, label: result.title,
        value: [result.employer, result.locality, salary].compactMap { $0 }.joined(
          separator: " · "), state: .verified,
        source: "\(result.sourceName):\(result.sourceURL.host ?? "source")",
        observedAt: result.observedAt,
        priority: result.tier == .directEmployer
          ? 100 : result.tier == .verifiedCommercial ? 90 : 70)
    }
    let actions = results.map {
      ResultAction(id: $0.id, title: "Відкрити вакансію", kind: .open, destination: $0.sourceURL)
    }
    return try DeterministicResultComposer().compose(
      primaryAnswer: "Актуальні вакансії", facts: facts, actions: actions)
  }
  private func fetch(_ sources: [any JobDiscoveryProvider], _ intent: GenericIntent) async
    -> [JobDiscoveryResult]
  {
    await withTaskGroup(of: [JobDiscoveryResult].self) { group in
      for source in sources { group.addTask { (try? await source.search(intent)) ?? [] } }
      var all: [JobDiscoveryResult] = []
      for await batch in group { all += batch }
      return all
    }
  }
  private func normalize(_ values: [JobDiscoveryResult], intent: GenericIntent)
    -> [JobDiscoveryResult]
  {
    let minimum = intent.money?.minimum
    let filtered = values.filter { value in
      value.confidence >= 0.5 && value.observedAt <= .now
        && (minimum.map { required in
          value.salaryMaximum.map { maximum in maximum >= required } ?? false
        } ?? true) && (value.tier != .verifiedCommercial || value.commercialEvidenceID != nil)
    }
    return Dictionary(
      grouping: filtered,
      by: { "\($0.title.lowercased())|\($0.employer.lowercased())|\($0.locality ?? "")" }
    ).values.compactMap { group in
      group.max { lhs, rhs in
        lhs.tier.weight == rhs.tier.weight
          ? lhs.observedAt < rhs.observedAt : lhs.tier.weight < rhs.tier.weight
      }
    }.sorted {
      $0.tier.weight == $1.tier.weight
        ? $0.observedAt > $1.observedAt : $0.tier.weight > $1.tier.weight
    }
  }
  private func formattedSalary(_ value: JobDiscoveryResult) -> String? {
    guard let currency = value.currency else { return nil }
    if let minimum = value.salaryMinimum, let maximum = value.salaryMaximum {
      return "\(minimum)–\(maximum) \(currency) \(value.salaryBasis ?? "")"
    }
    if let minimum = value.salaryMinimum {
      return "від \(minimum) \(currency) \(value.salaryBasis ?? "")"
    }
    return nil
  }
}
extension JobResultTier {
  fileprivate var weight: Int { self == .directEmployer ? 3 : self == .verifiedCommercial ? 2 : 1 }
}
