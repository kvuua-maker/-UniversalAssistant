import Foundation

struct EventKitExecutionResult: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case calendar, reminder }
    enum Operation: Equatable, Sendable { case created, queried, updated, completed, deleted }
    let kind: Kind; let operation: Operation; let title: String; let detail: String; let itemCount: Int
}
enum EventKitExecutionError: Error, Equatable { case unsupportedIntent, unresolvedDateTime, missingSubject, itemNotFound, ambiguousItem }
protocol EventKitCommandExecuting: Sendable { func execute(_ command: StructuredCommand) async throws -> EventKitExecutionResult }
struct EventKitCommandArguments: Equatable, Sendable { let subject: String?; let dateTime: ResolvedNaturalDateTime? }

struct EventKitCommandArgumentExtractor: Sendable {
    func extract(_ command: StructuredCommand, now: Date = .now, timeZone: TimeZone = .autoupdatingCurrent) -> EventKitCommandArguments {
        let locale = LanguageConfiguration(uiLanguage: .uk, commandLanguage: command.language).voiceLocale
        let resolution = NaturalDateTimeResolver().resolve(command.originalText, locale: locale, timeZone: timeZone, relativeTo: now)
        let dateTime: ResolvedNaturalDateTime? = if case let .resolved(value) = resolution { value } else { nil }
        let action = ["запиши", "додай", "зустріч", "перенеси", "видали", "скасуй", "нагадай", "нагадати", "покажи", "календарі", "нагадування", "виконай", "познач", "виконаним", "заверши", "complete", "создай", "встречу", "удали", "напомни", "календаре", "напоминания", "add", "event", "move", "delete", "remind", "show", "calendar", "reminders", "termin", "erstellen", "verschieben", "löschen", "erinnere", "kalendertermine", "rendez-vous", "ajoute", "déplace", "supprime", "rappelle", "événements", "rappels"]
        let temporal = ["сьогодні", "завтра", "післязавтра", "сегодня", "послезавтра", "today", "tomorrow", "day after tomorrow", "heute", "morgen", "übermorgen", "aujourd’hui", "demain", "après-demain"]
        var subject = command.originalText
        for token in action + temporal { subject = subject.replacingOccurrences(of: token, with: " ", options: [.caseInsensitive, .diacriticInsensitive]) }
        subject = subject.replacingOccurrences(of: #"\b(?:о|об|в|at|um|a)?\s*\d{1,2}(?:[:.]\d{2})?\s*(?:am|pm)?\b"#, with: " ", options: .regularExpression)
        subject = subject.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return .init(subject: subject.isEmpty ? nil : subject, dateTime: dateTime)
    }
}

struct ProductionEventKitCommandExecutor: EventKitCommandExecuting {
    private let calendar: EventKitCalendarService; private let reminders: EventKitReminderService
    private let now: @Sendable () -> Date; private let timeZone: TimeZone
    init(calendar: EventKitCalendarService = .init(), reminders: EventKitReminderService = .init(), now: @escaping @Sendable () -> Date = { .now }, timeZone: TimeZone = .autoupdatingCurrent) { self.calendar = calendar; self.reminders = reminders; self.now = now; self.timeZone = timeZone }
    func execute(_ command: StructuredCommand) async throws -> EventKitExecutionResult {
        let args = EventKitCommandArgumentExtractor().extract(command, now: now(), timeZone: timeZone)
        switch command.intent {
        case .calendarCreate:
            guard let title = args.subject else { throw EventKitExecutionError.missingSubject }
            guard let date = args.dateTime, date.precision == .minute else { throw EventKitExecutionError.unresolvedDateTime }
            try await calendar.requestFullAccessIfNeeded()
            let value = try await calendar.create(.init(title: title, start: date.instant, end: date.instant.addingTimeInterval(3600), notes: nil))
            return result(.calendar, .created, value.draft.title, value.draft.start, 1)
        case .calendarQuery:
            try await calendar.requestFullAccessIfNeeded(); let interval = day(args.dateTime?.instant ?? now())
            let values = try await calendar.events(from: interval.start, to: interval.end)
            return .init(kind: .calendar, operation: .queried, title: String(localized: "eventkit_calendar"), detail: list(values.map { "\($0.draft.title) — \(format($0.draft.start))" }), itemCount: values.count)
        case .calendarUpdate:
            guard let date = args.dateTime, date.precision == .minute else { throw EventKitExecutionError.unresolvedDateTime }
            let old = try await match(args.subject); let duration = max(60, old.draft.end.timeIntervalSince(old.draft.start))
            let value = try await calendar.update(identifier: old.identifier, with: .init(title: old.draft.title, start: date.instant, end: date.instant.addingTimeInterval(duration), notes: old.draft.notes))
            return result(.calendar, .updated, value.draft.title, value.draft.start, 1)
        case .calendarDelete:
            let old = try await match(args.subject); try await calendar.delete(identifier: old.identifier)
            return .init(kind: .calendar, operation: .deleted, title: old.draft.title, detail: String(localized: "eventkit_deleted"), itemCount: 1)
        case .reminderCreate:
            guard let title = args.subject else { throw EventKitExecutionError.missingSubject }
            guard let date = args.dateTime else { throw EventKitExecutionError.unresolvedDateTime }
            try await reminders.requestFullAccessIfNeeded()
            let value = try await reminders.create(.init(title: title, dueDate: date.instant, notes: nil, priority: 0, timeZoneIdentifier: date.timeZoneIdentifier, locationTrigger: nil))
            return result(.reminder, .created, value.draft.title, value.draft.dueDate ?? date.instant, 1)
        case .reminderQuery:
            try await reminders.requestFullAccessIfNeeded(); let interval = args.dateTime.map { day($0.instant) }
            let values = try await reminders.incomplete(dueFrom: interval?.start, to: interval?.end)
            return .init(kind: .reminder, operation: .queried, title: String(localized: "eventkit_reminders"), detail: list(values.map { $0.draft.title }), itemCount: values.count)
        case .reminderComplete:
            let old = try await matchReminder(args.subject)
            let value = try await reminders.update(identifier: old.identifier, with: old.draft, isCompleted: true)
            return .init(kind: .reminder, operation: .completed, title: value.draft.title, detail: String(localized: "eventkit_updated"), itemCount: 1)
        case .reminderDelete:
            let old = try await matchReminder(args.subject); try await reminders.delete(identifier: old.identifier)
            return .init(kind: .reminder, operation: .deleted, title: old.draft.title, detail: String(localized: "eventkit_deleted"), itemCount: 1)
        default: throw EventKitExecutionError.unsupportedIntent
        }
    }
    private func match(_ subject: String?) async throws -> CalendarEventSnapshot {
        guard let subject else { throw EventKitExecutionError.missingSubject }; try await calendar.requestFullAccessIfNeeded()
        var cal = Calendar.autoupdatingCurrent; cal.timeZone = timeZone
        let values = try await calendar.events(from: cal.date(byAdding: .day, value: -1, to: now())!, to: cal.date(byAdding: .day, value: 90, to: now())!)
        let matches = values.filter { $0.draft.title.localizedCaseInsensitiveContains(subject) || subject.localizedCaseInsensitiveContains($0.draft.title) }
        guard !matches.isEmpty else { throw EventKitExecutionError.itemNotFound }; guard matches.count == 1 else { throw EventKitExecutionError.ambiguousItem }; return matches[0]
    }
    private func matchReminder(_ subject: String?) async throws -> ReminderSnapshot {
        guard let subject else { throw EventKitExecutionError.missingSubject }
        try await reminders.requestFullAccessIfNeeded()
        let values = try await reminders.incomplete(dueFrom: nil, to: nil)
        let matches = values.filter { $0.draft.title.localizedCaseInsensitiveContains(subject) || subject.localizedCaseInsensitiveContains($0.draft.title) }
        guard !matches.isEmpty else { throw EventKitExecutionError.itemNotFound }
        guard matches.count == 1 else { throw EventKitExecutionError.ambiguousItem }
        return matches[0]
    }
    private func day(_ date: Date) -> DateInterval { var cal = Calendar.autoupdatingCurrent; cal.timeZone = timeZone; let start = cal.startOfDay(for: date); return .init(start: start, end: cal.date(byAdding: .day, value: 1, to: start)!) }
    private func format(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) }
    private func result(_ kind: EventKitExecutionResult.Kind, _ op: EventKitExecutionResult.Operation, _ title: String, _ date: Date, _ count: Int) -> EventKitExecutionResult { .init(kind: kind, operation: op, title: title, detail: format(date), itemCount: count) }
    private func list(_ values: [String]) -> String { values.isEmpty ? String(localized: "eventkit_empty") : values.prefix(10).joined(separator: "\n") }
}
