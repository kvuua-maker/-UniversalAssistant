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
        let rateQuery = ["курс", "rate", "exchange rate"].contains(where: normalized.contains)
        let amount = firstDecimal(normalized) ?? (rateQuery ? 1 : nil)
        guard let amount else { return nil }
        var ordered = currencyMentions(normalized)
        if rateQuery, ordered.count == 1, ordered[0].code != "UAH" {
            ordered.append((normalized.endIndex, "UAH"))
        }
        guard ordered.count >= 2, ordered[0].code != ordered[1].code else { return nil }
        // In “how many <target> for <amount> <source>” constructions the
        // target is spoken first, unlike the usual “<source> to <target>” order.
        if isTargetFirstQuestion(normalized, amount: amount, currencies: ordered) {
            ordered.swapAt(0, 1)
        }
        return .init(amount: amount, source: ordered[0].code, destination: ordered[1].code)
    }

    private func isTargetFirstQuestion(
        _ text: String,
        amount: Decimal,
        currencies: [(offset: String.Index, code: String)]
    ) -> Bool {
        guard currencies.count >= 2,
              ["скільки", "сколько", "how many", "how much"].contains(where: text.contains),
              let amountRange = text.range(
                of: NSRegularExpression.escapedPattern(for: NSDecimalNumber(decimal: amount).stringValue),
                options: .regularExpression
              )
        else { return false }
        return currencies[0].offset < amountRange.lowerBound && currencies[1].offset > amountRange.lowerBound
    }

    private func firstDecimal(_ text: String) -> Decimal? {
        guard let match = text.range(of: #"[-+]?\d+(?:\.\d+)?"#, options: .regularExpression) else { return nil }
        return Decimal(string: String(text[match]), locale: Locale(identifier: "en_US_POSIX"))
    }

    private func currencyMentions(_ text: String) -> [(offset: String.Index, code: String)] {
        let aliases: [(String, String)] = [
            ("долар", "USD"), ("доллар", "USD"), ("usd", "USD"), ("$", "USD"),
            ("євро", "EUR"), ("евро", "EUR"), ("eur", "EUR"), ("€", "EUR"),
            ("злот", "PLN"), ("pln", "PLN"),
            ("фунт", "GBP"), ("gbp", "GBP"), ("£", "GBP"),
            ("грив", "UAH"), ("uah", "UAH"), ("₴", "UAH"),
            ("франк", "CHF"), ("chf", "CHF"),
            ("крон", "CZK"), ("czk", "CZK"),
            ("ієн", "JPY"), ("иен", "JPY"), ("jpy", "JPY"), ("¥", "JPY")
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


/// Official credential-free NBU reference rates for conversions involving UAH.
/// Values are UAH per one unit of the reported currency; no commercial quote or
/// executable exchange price is implied.
struct NBUCurrentFXProvider: CurrentFXProviding {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let load: DataLoader
    private let now: @Sendable () -> Date

    init(load: @escaping DataLoader = { try await URLSession.shared.data(for: $0) },
         now: @escaping @Sendable () -> Date = Date.init) {
        self.load = load
        self.now = now
    }

    func convert(_ request: FXConversionRequest) async throws -> CurrentFXConversion {
        guard request.source == "UAH" || request.destination == "UAH" else {
            throw CurrentFXError.unsupportedCurrency("NBU requires a UAH side")
        }
        if request.source == request.destination {
            return .init(request: request, convertedAmount: request.amount,
                         observedAt: now(), provider: "National Bank of Ukraine")
        }
        let url = URL(string: "https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json")!
        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 8
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await load(urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CurrentFXError.invalidResponse
        }
        let rows: [RateRow]
        do { rows = try JSONDecoder().decode([RateRow].self, from: data) }
        catch { throw CurrentFXError.invalidResponse }
        let sourceRate = try rate(for: request.source, rows: rows)
        let destinationRate = try rate(for: request.destination, rows: rows)
        let converted = request.amount * sourceRate / destinationRate
        let observedAt = rows.first(where: { $0.cc == (request.source == "UAH" ? request.destination : request.source) })
            .flatMap { Self.date($0.exchangedate) } ?? now()
        return .init(request: request, convertedAmount: converted,
                     observedAt: observedAt, provider: "National Bank of Ukraine")
    }

    private func rate(for code: String, rows: [RateRow]) throws -> Decimal {
        if code == "UAH" { return 1 }
        guard let rate = rows.first(where: { $0.cc == code })?.rate, rate > 0 else {
            throw CurrentFXError.unsupportedCurrency(code)
        }
        return rate
    }

    private static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.date(from: value)
    }

    private struct RateRow: Decodable { let rate: Decimal; let cc: String; let exchangedate: String }
}

struct RegionalCurrentFXProvider: CurrentFXProviding {
    let ecb: ECBCurrentFXProvider
    let nbu: NBUCurrentFXProvider

    init(ecb: ECBCurrentFXProvider = .init(), nbu: NBUCurrentFXProvider = .init()) {
        self.ecb = ecb
        self.nbu = nbu
    }

    func convert(_ request: FXConversionRequest) async throws -> CurrentFXConversion {
        if request.source == "UAH" || request.destination == "UAH" {
            return try await nbu.convert(request)
        }
        return try await ecb.convert(request)
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
