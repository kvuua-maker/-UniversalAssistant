import Foundation

struct FXConversionRequest: Equatable, Sendable {
    let amount: Decimal
    let source: String
    let destination: String
}

struct CurrentFXConversion: Equatable, Sendable {
    let request: FXConversionRequest
    let convertedAmount: Decimal
    let observedAt: Date
    let provider: String
}

enum CurrentFXError: Error, Equatable {
    case unsupportedCurrency(String)
    case invalidResponse
    case unavailable
}

protocol CurrentFXProviding: Sendable {
    func convert(_ request: FXConversionRequest) async throws -> CurrentFXConversion
}

struct FXConversionRequestParser: Sendable {
    func parse(_ text: String) -> FXConversionRequest? {
        let normalized = text.lowercased().replacingOccurrences(of: ",", with: ".")
        guard let amount = firstDecimal(normalized) else { return nil }
        let ordered = currencyMentions(normalized)
        guard ordered.count >= 2, ordered[0].code != ordered[1].code else { return nil }
        return .init(amount: amount, source: ordered[0].code, destination: ordered[1].code)
    }

    private func firstDecimal(_ text: String) -> Decimal? {
        guard let match = text.range(of: #"[-+]?\d+(?:\.\d+)?"#, options: .regularExpression) else { return nil }
        return Decimal(string: String(text[match]), locale: Locale(identifier: "en_US_POSIX"))
    }

    private func currencyMentions(_ text: String) -> [(offset: String.Index, code: String)] {
        let aliases: [(String, String)] = [
            ("долар", "USD"), ("доллар", "USD"), ("usd", "USD"),
            ("євро", "EUR"), ("евро", "EUR"), ("eur", "EUR"),
            ("злот", "PLN"), ("pln", "PLN"),
            ("фунт", "GBP"), ("gbp", "GBP"),
            ("гривн", "UAH"), ("uah", "UAH"),
            ("франк", "CHF"), ("chf", "CHF"),
            ("крон", "CZK"), ("czk", "CZK"),
            ("ієн", "JPY"), ("иен", "JPY"), ("jpy", "JPY")
        ]
        var matches: [(offset: String.Index, code: String)] = []
        for (alias, code) in aliases {
            if let range = text.range(of: alias) { matches.append((range.lowerBound, code)) }
        }
        matches.sort { left, right in left.offset < right.offset }
        var distinct: [(offset: String.Index, code: String)] = []
        for value in matches {
            let previousCode = distinct.last?.code
            if previousCode != value.code { distinct.append(value) }
        }
        return distinct
    }
}

struct ECBCurrentFXProvider: CurrentFXProviding {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let load: DataLoader
    private let now: @Sendable () -> Date
    private let supported = Set(["EUR", "USD", "JPY", "CZK", "DKK", "GBP", "HUF", "PLN", "RON", "SEK", "CHF", "NOK", "AUD", "CAD", "CNY"])

    init(load: @escaping DataLoader = { try await URLSession.shared.data(for: $0) }, now: @escaping @Sendable () -> Date = Date.init) {
        self.load = load
        self.now = now
    }

    func convert(_ request: FXConversionRequest) async throws -> CurrentFXConversion {
        guard supported.contains(request.source) else { throw CurrentFXError.unsupportedCurrency(request.source) }
        guard supported.contains(request.destination) else { throw CurrentFXError.unsupportedCurrency(request.destination) }
        if request.source == request.destination {
            return .init(request: request, convertedAmount: request.amount, observedAt: now(), provider: "European Central Bank")
        }
        let currencies = Set([request.source, request.destination]).subtracting(["EUR"]).sorted().joined(separator: "+")
        guard let encoded = currencies.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://data-api.ecb.europa.eu/service/data/EXR/D.\(encoded).EUR.SP00.A?lastNObservations=1&format=csvdata") else {
            throw CurrentFXError.unavailable
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 8
        urlRequest.setValue("text/csv", forHTTPHeaderField: "Accept")
        let (data, response) = try await load(urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let csv = String(data: data, encoding: .utf8) else { throw CurrentFXError.invalidResponse }
        let rates = try parseRates(csv)
        let sourcePerEUR: Decimal = request.source == "EUR" ? 1 : try requiredRate(request.source, rates)
        let destinationPerEUR: Decimal = request.destination == "EUR" ? 1 : try requiredRate(request.destination, rates)
        let value = request.amount / sourcePerEUR * destinationPerEUR
        return .init(request: request, convertedAmount: value, observedAt: now(), provider: "European Central Bank")
    }

    private func requiredRate(_ code: String, _ rates: [String: Decimal]) throws -> Decimal {
        guard let value = rates[code], value > 0 else { throw CurrentFXError.invalidResponse }
        return value
    }

    private func parseRates(_ csv: String) throws -> [String: Decimal] {
        let rows = csv.split(whereSeparator: \.isNewline).map { String($0).split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        guard let header = rows.first,
              let currencyIndex = header.firstIndex(of: "CURRENCY"),
              let valueIndex = header.firstIndex(of: "OBS_VALUE") else { throw CurrentFXError.invalidResponse }
        var rates: [String: Decimal] = [:]
        for row in rows.dropFirst() where row.indices.contains(currencyIndex) && row.indices.contains(valueIndex) {
            if let value = Decimal(string: row[valueIndex], locale: Locale(identifier: "en_US_POSIX")) { rates[row[currencyIndex]] = value }
        }
        return rates
    }
}
