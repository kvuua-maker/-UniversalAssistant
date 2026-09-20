import Foundation

actor StateEmploymentOpenDataProvider: JobDiscoveryProvider {
    nonisolated let id = "state-employment-open-data"
    nonisolated let tier: JobResultTier = .directEmployer

    private static let organizationID = "6c0a211b-9ade-4268-aaf8-a17e9009a380"
    private static let datasetID = "a95174b2-ff4b-43f8-bee2-a89d3a258215"
    private static let apiBase = URL(string: "https://data.gov.ua/api/3/action/")!
    private let session: URLSession
    private let cacheURL: URL
    private let refreshInterval: TimeInterval
    private var memory: Snapshot?
    private var refreshInFlight = false

    struct Snapshot: Codable, Sendable {
        let datasetID: String
        let resourceID: String
        let sourceDate: Date
        let fetchedAt: Date
        let jobs: [JobDiscoveryResult]
    }

    init(session: URLSession = .shared, cacheURL: URL? = nil, refreshInterval: TimeInterval = 12 * 60 * 60) {
        self.session = session
        self.refreshInterval = refreshInterval
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheURL = cacheURL ?? root.appendingPathComponent("UniversalAssistant/state-employment-jobs.json")
    }

    func search(_ intent: GenericIntent) async throws -> [JobDiscoveryResult] {
        let snapshot = try await currentSnapshot()
        let subject = normalized(intent.subject)
        let locality = intent.location?.locality.map(normalized)
        return snapshot.jobs.filter { job in
            let roleMatches = subject.isEmpty || subject == "робота" || normalized(job.title).contains(subject) || subject.contains(normalized(job.title))
            let localityMatches = locality.map { expected in normalized(job.locality ?? "").contains(expected) } ?? true
            return roleMatches && localityMatches
        }
    }

    private func currentSnapshot(now: Date = .now) async throws -> Snapshot {
        if memory == nil, let cached = loadCache() { memory = cached }
        if let memory {
            if now.timeIntervalSince(memory.fetchedAt) >= refreshInterval {
                refreshInBackground()
            }
            // A valid normalized cache is the interactive search source. A
            // refresh must never put the full CKAN/XML download in front of a
            // user's job query.
            return memory
        }
        return try await refreshSnapshot(now: now)
    }

    private func refreshInBackground() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.refreshSnapshot(now: .now)
            await self.finishRefresh()
        }
    }

    private func finishRefresh() {
        refreshInFlight = false
    }

    private func refreshSnapshot(now: Date) async throws -> Snapshot {
        do {
            let datasetID = (try? await resolveDatasetID()) ?? Self.datasetID
            let resource = try await latestResource(datasetID: datasetID)
            let (data, response) = try await session.data(for: boundedRequest(resource.url))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ProviderError.invalidResponse }
            let jobs = StateEmploymentXMLParser.parse(data, sourceDate: resource.modified)
            guard !jobs.isEmpty else { throw ProviderError.invalidResponse }
            let snapshot = Snapshot(datasetID: datasetID, resourceID: resource.id, sourceDate: resource.modified, fetchedAt: now, jobs: jobs)
            memory = snapshot
            persist(snapshot)
            return snapshot
        } catch {
            if let memory { return memory }
            throw error
        }
    }

    private func resolveDatasetID() async throws -> String {
        let url = Self.apiBase.appendingPathComponent("package_search").appending(queryItems: [
            .init(name: "q", value: "Перелік актуальних вакансій станом на дату"),
            .init(name: "fq", value: "organization:\(Self.organizationID)"),
            .init(name: "rows", value: "10")
        ])
        let (data, response) = try await session.data(for: boundedRequest(url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ProviderError.invalidResponse }
        let payload = try JSONDecoder.dataGov.decode(CKANSearchResponse.self, from: data)
        guard payload.success,
              let match = payload.result.results.first(where: {
                  $0.organization?.id == Self.organizationID &&
                  $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA"))
                    .contains("актуальних вакансій")
              }) else { throw ProviderError.resourceNotFound }
        return match.id
    }

    private func latestResource(datasetID: String) async throws -> Resource {
        let url = Self.apiBase.appendingPathComponent("package_show").appending(queryItems: [.init(name: "id", value: datasetID)])
        let (data, response) = try await session.data(for: boundedRequest(url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ProviderError.invalidResponse }
        let payload = try JSONDecoder.dataGov.decode(CKANPackageResponse.self, from: data)
        guard payload.success, payload.result.organization?.id == Self.organizationID,
              let resource = payload.result.resources
                .filter({ $0.format.caseInsensitiveCompare("XML") == .orderedSame })
                .compactMap(Resource.init)
                .max(by: { $0.modified < $1.modified }) else { throw ProviderError.resourceNotFound }
        return resource
    }

    private func loadCache() -> Snapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder.dataGov.decode(Snapshot.self, from: data)
    }

    private func persist(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder.dataGov.encode(snapshot) else { return }
        let directory = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(UUID().uuidString)
        do {
            try data.write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: cacheURL.path) { try FileManager.default.removeItem(at: cacheURL) }
            try FileManager.default.moveItem(at: temporary, to: cacheURL)
        } catch { try? FileManager.default.removeItem(at: temporary) }
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA"))
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func boundedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.cachePolicy = .reloadRevalidatingCacheData
        return request
    }

    enum ProviderError: Error { case invalidResponse, resourceNotFound }

    private struct Resource: Sendable {
        let id: String; let url: URL; let modified: Date
        init?(_ value: CKANResource) {
            guard let url = URL(string: value.url), let modified = value.lastModified ?? value.created else { return nil }
            id = value.id; self.url = url; self.modified = modified
        }
    }
}

private struct CKANPackageResponse: Decodable {
    let success: Bool
    let result: Package
    struct Package: Decodable { let organization: Organization?; let resources: [CKANResource] }
    struct Organization: Decodable { let id: String }
}

private struct CKANSearchResponse: Decodable {
    let success: Bool
    let result: Result
    struct Result: Decodable { let results: [Dataset] }
    struct Dataset: Decodable {
        let id: String
        let title: String
        let organization: CKANPackageResponse.Organization?
    }
}

private struct CKANResource: Decodable {
    let id: String; let format: String; let url: String
    let lastModified: Date?; let created: Date?
    enum CodingKeys: String, CodingKey { case id, format, url, lastModified = "last_modified", created }
}

final class StateEmploymentXMLParser: NSObject, XMLParserDelegate {
    private var currentID = "", currentElement = "", buffer = ""
    private var name = "", region = "", link = "", descriptionHTML = ""
    private let sourceDate: Date
    private(set) var jobs: [JobDiscoveryResult] = []

    init(sourceDate: Date) { self.sourceDate = sourceDate }

    static func parse(_ data: Data, sourceDate: Date) -> [JobDiscoveryResult] {
        let delegate = StateEmploymentXMLParser(sourceDate: sourceDate)
        let parser = XMLParser(data: data); parser.delegate = delegate
        return parser.parse() ? delegate.jobs : []
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName; buffer = ""
        if elementName == "job" { currentID = attributeDict["id"] ?? UUID().uuidString; name = ""; region = ""; link = ""; descriptionHTML = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = clean(buffer)
        switch elementName { case "name": name = value; case "region": region = value; case "link": link = value; case "description": descriptionHTML = value; default: break }
        guard elementName == "job", !name.isEmpty,
              let url = URL(string: link.replacingOccurrences(of: "![CDATA[", with: "").replacingOccurrences(of: "]]", with: "")) else { return }
        let plain = clean(descriptionHTML.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression))
        let employer = capture(#"(?:Назва підприємства|Роботодавець):?\s*([^\n]{2,120})"#, in: plain) ?? "Роботодавець за даними ДСЗ"
        let salary = capture(#"Заробітна плата \(усього\):\s*([0-9 ]+)"#, in: plain).flatMap { Decimal(string: $0.replacingOccurrences(of: " ", with: "")) }
        let employment = capture(#"Характер виконуваної роботи:?\s*([^\n]{2,80})"#, in: plain)
        jobs.append(.init(id: currentID, title: name, employer: employer, locality: region,
                          salaryMinimum: salary, salaryMaximum: salary, currency: salary == nil ? nil : "UAH",
                          salaryBasis: salary == nil ? nil : "місяць", employmentType: employment,
                          publishedAt: sourceDate, observedAt: sourceDate, sourceName: "Державна служба зайнятості",
                          sourceURL: url, tier: .directEmployer, commercialEvidenceID: nil, confidence: 0.95))
    }

    private func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "![CDATA[", with: "").replacingOccurrences(of: "]]", with: "")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func capture(_ pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension JSONDecoder {
    static var dataGov: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
}
private extension JSONEncoder {
    static var dataGov: JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value }
}
