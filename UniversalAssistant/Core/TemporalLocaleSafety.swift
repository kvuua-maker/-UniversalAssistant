import Foundation

struct ZonedInstant: Equatable, Codable, Sendable {
    let instant: Date
    let timeZoneIdentifier: String

    init(instant: Date, timeZone: TimeZone) {
        self.instant = instant
        timeZoneIdentifier = timeZone.identifier
    }

    var timeZone: TimeZone? { TimeZone(identifier: timeZoneIdentifier) }
}

struct AuthoritativeTimeWindow: Equatable, Sendable {
    let issuedAt: Date
    let expiresAt: Date
    let permittedClockSkew: TimeInterval

    func isValid(clientNow: Date) -> Bool {
        guard expiresAt > issuedAt, permittedClockSkew >= 0 else { return false }
        return clientNow >= issuedAt.addingTimeInterval(-permittedClockSkew) &&
            clientNow <= expiresAt.addingTimeInterval(permittedClockSkew)
    }
}

enum SafeMoneyComparison: Equatable, Sendable {
    case ordered(ComparisonResult)
    case currencyConversionRequired(left: String, right: String)
}

extension Money {
    func safelyCompare(to other: Money) -> SafeMoneyComparison {
        let left = currency.uppercased(), right = other.currency.uppercased()
        guard left == right else { return .currencyConversionRequired(left: left, right: right) }
        if amount < other.amount { return .ordered(.orderedAscending) }
        if amount > other.amount { return .ordered(.orderedDescending) }
        return .ordered(.orderedSame)
    }
}

enum GroceryQuantityComparison: Equatable, Sendable {
    case ordered(ComparisonResult)
    case incompatibleUnits(left: GroceryUnit, right: GroceryUnit)
}

extension GroceryQuantity {
    func safelyCompare(to other: GroceryQuantity) -> GroceryQuantityComparison {
        guard unit == other.unit else { return .incompatibleUnits(left: unit, right: other.unit) }
        if amount < other.amount { return .ordered(.orderedAscending) }
        if amount > other.amount { return .ordered(.orderedDescending) }
        return .ordered(.orderedSame)
    }
}

struct RuntimePresentationContext: Equatable, Sendable {
    let locale: Locale
    let timeZone: TimeZone

    static var current: Self { .init(locale: .current, timeZone: .current) }

    func calendar() -> Calendar {
        var value = Calendar.autoupdatingCurrent
        value.locale = locale
        value.timeZone = timeZone
        return value
    }
}
