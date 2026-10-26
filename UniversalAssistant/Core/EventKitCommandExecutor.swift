import Foundation

struct EventKitExecutionResult: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case calendar, reminder }
    enum Operation: Equatable, Sendable { case created, queried, updated, completed, deleted, undone }
    let kind: Kind; let operation: Operation; let title: String; let detail: String; let itemCount: Int
}
enum EventKitExecutionError: Error, Equatable { case unsupportedIntent, unresolvedDateTime, missingSubject, itemNotFound, ambiguousItem }
protocol EventKitCommandExecuting: Sendable { func execute(_ command: StructuredCommand) async throws -> EventKitExecutionResult }
protocol EventKitCalendarExecuting: CalendarMutating {
    func requestFullAccessIfNeeded() async throws
    func create(_ input: CalendarEventDraft) async throws -> CalendarEventSnapshot
    func events(from start: Date, to end: Date) async throws -> [CalendarEventSnapshot]
    func update(identifier: String, with input: CalendarEventDraft) async throws -> CalendarEventSnapshot
}
protocol EventKitReminderExecuting: ReminderMutating {
    func requestFullAccessIfNeeded() async throws
    func create(_ input: ReminderDraft) async throws -> ReminderSnapshot
    func incomplete(dueFrom start: Date?, to end: Date?) async throws -> [ReminderSnapshot]
    func update(identifier: String, with input: ReminderDraft, isCompleted: Bool?) async throws -> ReminderSnapshot
}
extension EventKitCalendarService: EventKitCalendarExecuting {}
extension EventKitReminderService: EventKitReminderExecuting {}
struct EventKitCommandArguments: Equatable, Sendable { let subject: String?; let dateTime: ResolvedNaturalDateTime?; let durationSeconds: TimeInterval? }

struct EventKitCommandArgumentExtractor: Sendable {
    func extract(_ command: StructuredCommand, now: Date = .now, timeZone: TimeZone = .autoupdatingCurrent) -> EventKitCommandArguments {
        let locale = LanguageConfiguration(uiLanguage: .uk, commandLanguage: command.language).voiceLocale
        let resolution = NaturalDateTimeResolver().resolve(command, locale: locale, timeZone: timeZone, relativeTo: now)
        let dateTime: ResolvedNaturalDateTime? = if case let .resolved(value) = resolution { value } else { nil }
        // Event-type vocabulary is not automatically disposable title text.
        // “зустріч” may be the complete user-supplied subject.
        let action = ["запиши", "створи", "додай", "заплануй", "запланируй", "подію", "подія", "перенеси", "видали", "скасуй", "нагадай", "нагадати", "покажи", "календарі", "нагадування", "виконай", "познач", "виконаним", "заверши", "complete", "создай", "событие", "удали", "напомни", "календаре", "напоминания", "add", "create", "event", "move", "delete", "remind", "show", "calendar", "reminders", "termin", "erstellen", "verschieben", "löschen", "erinnere", "kalendertermine", "rendez-vous", "ajoute", "déplace", "supprime", "rappelle", "événements", "rappels"]
        let temporal = ["будь ласка", "пожалуйста", "please", "на сьогодні", "на завтра", "на післязавтра", "на сегодня", "на послезавтра", "сьогодні", "завтра", "післязавтра", "сегодня", "послезавтра", "today", "tomorrow", "day after tomorrow", "heute", "morgen", "übermorgen", "aujourd’hui", "demain", "après-demain", "мені", "мне", "через", "ранку", "утра", "вранці", "вечора", "вечером"]
        var subject = command.originalText
        // Remove canonical action/object roles by morphology, not by one
        // memorized utterance. Temporal and user payload terms are cleaned
        // separately below, leaving only the event/reminder title.
        subject = subject.replacingOccurrences(
            of: #"\b(?:постав\p{L}*|встанов\p{L}*|установ\p{L}*|створ\p{L}*|созд\p{L}*|дод\p{L}*|добав\p{L}*|заплан\p{L}*|нагада\p{L}*|напомн\p{L}*|remind\p{L}*|create\p{L}*|add\p{L}*|schedule\p{L}*)\b"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        subject = subject.replacingOccurrences(
            of: #"\b(?:нагадув\p{L}*|напомин\p{L}*|reminder\p{L}*|календар\p{L}*|поді\p{L}*|событ\p{L}*|event\p{L}*)\b"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        subject = subject.replacingOccurrences(
            of: #"(?:\bна|\bfor)\s+\d+\s*(?:годин(?:у|и)?|hours?|хвилин(?:у|и)?|хв|минут(?:у|ы)?|мин|minutes?|mins?)"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        for token in action + temporal { subject = subject.replacingOccurrences(of: token, with: " ", options: [.caseInsensitive, .diacriticInsensitive]) }
        subject = subject.replacingOccurrences(of: #"\b(?:о|об|в|at|um|a)?\s*\d{1,2}(?:[:.]\d{2})?\s*(?:am|pm)?\b"#, with: " ", options: .regularExpression)
        subject = subject.replacingOccurrences(of: #"\d+\s*(?:годин(?:у|и)?|hours?|хвилин(?:у|и)?|хв|минут(?:у|ы)?|мин|minutes?|mins?|секунд(?:у|и)?|сек|seconds?|secs?)"#, with: " ", options: [.regularExpression, .caseInsensitive])
        subject = subject.replacingOccurrences(of: #"(?:годин(?:у|и)?|hours?|хвилин(?:у|и)?|хв|минут(?:у|ы)?|мин|minutes?|mins?|секунд(?:у|и)?|сек|seconds?|secs?)"#, with: " ", options: [.regularExpression, .caseInsensitive])
        subject = subject.replacingOccurrences(
            of: #"\b(?:о|об|в)\s+(?:(?:двадцять|двадцать)\s+)?(?:п['’]?ятнадцят|пятнадцат|дванадцят|двенадцат|одинадцят|одиннадцат|дев['’]?ятнадцят|девятнадцат|вісімнадцят|восемнадцат|сімнадцят|семнадцат|шістнадцят|шестнадцат|чотирнадцят|четырнадцат|тринадцят|тринадцат|десят|дев['’]?ят|девят|восьм|восем|сьом|седьм|шост|шест|п['’]?ят|пят|четверт|чотир|трет|друг|втор|перш|перв)\p{L}*\b"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        subject = subject.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // Keep a bare event-type word as the user's actual title, but when it
        // prefixes a richer subject it is structural vocabulary, not payload.
        subject = subject.replacingOccurrences(
            of: #"^(?:зустріч\p{L}*|встреч\p{L}*)\s+(?=\S)"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let durationSeconds = command.entities["duration_seconds"].flatMap(TimeInterval.init) ?? duration(in: command.originalText)
        return .init(subject: subject.isEmpty ? nil : subject, dateTime: dateTime, durationSeconds: durationSeconds)
    }

    private func duration(in text: String) -> TimeInterval? {
        let pattern = "(?:\\bна|for)\\s+(\\d+)\\s*(годин(?:у|и)?|hours?|хвилин(?:у|и)?|хв|минут(?:у|ы)?|мин|minutes?|mins?)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let amountRange = Range(match.range(at: 1), in: text), let amount = Int(text[amountRange]),
              let unitRange = Range(match.range(at: 2), in: text) else { return nil }
        let unit = String(text[unitRange]).lowercased()
        return TimeInterval(amount * (unit.hasPrefix("год") || unit.hasPrefix("hour") ? 3600 : 60))
    }
}

actor ProductionEventKitCommandExecutor: EventKitCommandExecuting {
    private let calendar: any EventKitCalendarExecuting; private let reminders: any EventKitReminderExecuting
    private let history: ActionHistory
    private let now: @Sendable () -> Date; private let timeZone: TimeZone
    private var historyRestored = false
    init(calendar: any EventKitCalendarExecuting = EventKitCalendarService(), reminders: any EventKitReminderExecuting = EventKitReminderService(), history: ActionHistory = .init(), now: @escaping @Sendable () -> Date = { .now }, timeZone: TimeZone = .autoupdatingCurrent) { self.calendar = calendar; self.reminders = reminders; self.history = history; self.now = now; self.timeZone = timeZone }
    func execute(_ command: StructuredCommand) async throws -> EventKitExecutionResult {
        let diagnosticBoundary = [CommandIntent.calendarCreate, .calendarQuery, .calendarUpdate, .calendarDelete].contains(command.intent)
            ? "CALENDAR" : "REMINDER"
        LocalVoiceDiagnosticReport.shared.recordBoundaryPre(diagnosticBoundary, "capability=\(command.intent.rawValue)")
        defer { LocalVoiceDiagnosticReport.shared.recordBoundaryPost(diagnosticBoundary, "capability=\(command.intent.rawValue) status=returned") }
        try await restoreHistoryIfNeeded()
        let args = EventKitCommandArgumentExtractor().extract(command, now: now(), timeZone: timeZone)
        switch command.intent {
        case .calendarCreate:
            // A delete phrase may still be classified as "create"; never create a
            // second event when the user asked to remove one.
            if ["видали", "удали", "скасуй", "delete", "remove", "löschen", "supprime"].contains(where: command.normalizedText.contains) {
                return try await deleteCalendarEvent(command, args, calendar: calendar)
            }
            guard let title = args.subject else { throw EventKitExecutionError.missingSubject }
            guard let date = args.dateTime, date.precision == .minute else { throw EventKitExecutionError.unresolvedDateTime }
            try await calendar.requestFullAccessIfNeeded()
            let value = try await calendar.create(.init(title: title, start: date.instant, end: date.instant.addingTimeInterval(args.durationSeconds ?? 3600), notes: nil))
            await recordHistory(.init(kind: .calendarCreate, externalIdentifier: value.identifier))
            return result(.calendar, .created, value.draft.title, value.draft.start, 1)
        case .calendarQuery:
            try await calendar.requestFullAccessIfNeeded(); let interval = queryInterval(dayPeriod: command.entities["day_period"], instant: args.dateTime?.instant ?? now())
            let values = try await calendar.events(from: interval.start, to: interval.end)
            return .init(kind: .calendar, operation: .queried, title: String(localized: "eventkit_calendar"), detail: list(values.map { "\($0.draft.title) — \(format($0.draft.start))" }), itemCount: values.count)
        case .calendarUpdate:
            guard let date = args.dateTime, date.precision == .minute else { throw EventKitExecutionError.unresolvedDateTime }
            let old = try await match(identifier: command.entities["selected_item_id"], subject: args.subject); let duration = max(60, old.draft.end.timeIntervalSince(old.draft.start))
            let value = try await calendar.update(identifier: old.identifier, with: .init(title: old.draft.title, start: date.instant, end: date.instant.addingTimeInterval(duration), notes: old.draft.notes))
            await recordHistory(.init(kind: .calendarUpdate, externalIdentifier: old.identifier, undoPayload: try JSONEncoder().encode(old)))
            return result(.calendar, .updated, value.draft.title, value.draft.start, 1)
        case .calendarDelete:
            if let date = args.dateTime, date.precision == .minute {
                return try await deleteCalendarEvent(command, args, calendar: calendar)
            }
            let old = try await match(args.subject); try await calendar.delete(identifier: old.identifier)
            await MainActor.run { RuntimeDiagnostics.shared.log("calendar", "deleted by subject: \(old.draft.title)") }
            await recordHistory(.init(kind: .calendarUpdate, externalIdentifier: old.identifier, undoPayload: try JSONEncoder().encode(old)))
            return .init(kind: .calendar, operation: .deleted, title: old.draft.title, detail: String(localized: "eventkit_deleted"), itemCount: 1)
        case .reminderCreate:
            guard let title = args.subject else { throw EventKitExecutionError.missingSubject }
            guard let date = args.dateTime else { throw EventKitExecutionError.unresolvedDateTime }
            try await reminders.requestFullAccessIfNeeded()
            let value = try await reminders.create(.init(title: title, dueDate: date.instant, notes: nil, priority: 0, timeZoneIdentifier: date.timeZoneIdentifier, locationTrigger: nil))
            await recordHistory(.init(kind: .reminderCreate, externalIdentifier: value.identifier))
            return result(.reminder, .created, value.draft.title, value.draft.dueDate ?? date.instant, 1)
        case .reminderQuery:
            try await reminders.requestFullAccessIfNeeded(); let interval = args.dateTime.map { day($0.instant) }
            let values = try await reminders.incomplete(dueFrom: interval?.start, to: interval?.end)
            return .init(kind: .reminder, operation: .queried, title: String(localized: "eventkit_reminders"), detail: list(values.map { $0.draft.title }), itemCount: values.count)
        case .reminderComplete:
            let old = try await matchReminder(args.subject)
            let value = try await reminders.update(identifier: old.identifier, with: old.draft, isCompleted: true)
            await recordHistory(.init(kind: .reminderUpdate, externalIdentifier: old.identifier, undoPayload: try JSONEncoder().encode(old)))
            return .init(kind: .reminder, operation: .completed, title: value.draft.title, detail: String(localized: "eventkit_updated"), itemCount: 1)
        case .reminderDelete:
            let old = try await matchReminder(args.subject); try await reminders.delete(identifier: old.identifier)
            await recordHistory(.init(kind: .reminderUpdate, externalIdentifier: old.identifier, undoPayload: try JSONEncoder().encode(old)))
            return .init(kind: .reminder, operation: .deleted, title: old.draft.title, detail: String(localized: "eventkit_deleted"), itemCount: 1)
        case .shoppingList:
            return try await shoppingList(command, subject: args.subject)
        case .undo:
            guard let pending = await history.latestUndoable() else { throw ActionHistoryError.nothingToUndo }
            let handler: any ActionUndoing = switch pending.kind {
            case .calendarCreate, .calendarUpdate: CalendarActionUndoHandler(calendar: calendar)
            case .reminderCreate, .reminderUpdate: ReminderActionUndoHandler(reminders: reminders)
            default: throw ActionHistoryError.nothingToUndo
            }
            let undone = try await history.undoLast(using: handler)
            let kind: EventKitExecutionResult.Kind = switch undone.kind {
            case .calendarCreate, .calendarUpdate: .calendar
            default: .reminder
            }
            return .init(kind: kind, operation: .undone, title: String(localized: "undo"), detail: String(localized: "eventkit_updated"), itemCount: 1)
        default: throw EventKitExecutionError.unsupportedIntent
        }
    }
    private func restoreHistoryIfNeeded() async throws {
        guard !historyRestored else { return }
        try await history.restore(); historyRestored = true
    }
    private func recordHistory(_ record: ActionRecord) async {
        // EventKit is authoritative. A secondary local-history failure may remove
        // undo availability, but must never turn a completed system mutation into failure.
        try? await history.record(record)
    }
    private func shoppingList(_ command: StructuredCommand, subject: String?) async throws -> EventKitExecutionResult {
        try await reminders.requestFullAccessIfNeeded()
        let text = command.normalizedText
        if ["додай", "добав", "add "].contains(where: text.contains) {
            guard let title = shoppingSubject(command.originalText) else { throw EventKitExecutionError.missingSubject }
            let listID = command.entities["selected_list_id"]
            let value = try await reminders.create(.init(title: title, dueDate: nil, notes: nil, priority: 0, timeZoneIdentifier: nil, locationTrigger: nil, listIdentifier: listID))
            await recordHistory(.init(kind: .reminderCreate, externalIdentifier: value.identifier))
            return .init(kind: .reminder, operation: .created, title: value.draft.title, detail: String(localized: "eventkit_updated"), itemCount: 1)
        }
        if ["видали", "удали", "remove", "delete"].contains(where: text.contains) {
            guard let selectedID = command.entities["selected_item_id"] else { throw EventKitExecutionError.missingSubject }
            let old = try await exactReminder(identifier: selectedID)
            try await reminders.delete(identifier: old.identifier)
            await recordHistory(.init(kind: .reminderUpdate, externalIdentifier: old.identifier, undoPayload: try JSONEncoder().encode(old)))
            return .init(kind: .reminder, operation: .deleted, title: old.draft.title, detail: String(localized: "eventkit_deleted"), itemCount: 1)
        }
        let listID = command.entities["selected_list_id"]
        let allValues = try await reminders.incomplete(dueFrom: nil, to: nil)
        let values = listID.map { selected in allValues.filter { $0.draft.listIdentifier == selected } } ?? allValues
        return .init(kind: .reminder, operation: .queried, title: String(localized: "eventkit_reminders"), detail: list(values.map { $0.draft.title }), itemCount: values.count)
    }
    private func deleteCalendarEvent(
        _ command: StructuredCommand,
        _ args: EventKitCommandArguments,
        calendar: any EventKitCalendarExecuting
    ) async throws -> EventKitExecutionResult {
        guard let date = args.dateTime, date.precision == .minute else {
            throw EventKitExecutionError.unresolvedDateTime
        }
        try await calendar.requestFullAccessIfNeeded()
        let from = date.instant.addingTimeInterval(-60)
        let to = date.instant.addingTimeInterval(60)
        let events = try await calendar.events(from: from, to: to)
        guard let event = events.first else {
            await MainActor.run {
                RuntimeDiagnostics.shared.log("calendar", "delete at \(date.instant): not found")
            }
            throw EventKitExecutionError.missingSubject
        }
        do {
            try await calendar.delete(identifier: event.identifier)
            await MainActor.run {
                RuntimeDiagnostics.shared.log("calendar", "deleting event at \(date.instant), result: success")
            }
            await recordHistory(.init(kind: .calendarDelete, externalIdentifier: event.identifier))
        } catch {
            await MainActor.run {
                RuntimeDiagnostics.shared.log("calendar", "deleting event at \(date.instant), result: failed (\(error))")
            }
            throw error
        }
        return result(.calendar, .deleted, event.draft.title, event.draft.start, 1)
    }

    private func exactReminder(identifier: String) async throws -> ReminderSnapshot {
        let values = try await reminders.incomplete(dueFrom: nil, to: nil)
        guard let value = values.first(where: { $0.identifier == identifier }) else { throw EventKitExecutionError.itemNotFound }
        return value
    }
    private func shoppingSubject(_ value: String) -> String? {
        var result = value
        for token in ["додай", "добавь", "add", "видали", "удали", "remove", "delete", "до списку покупок", "у список покупок", "в список покупок", "shopping list"] {
            result = result.replacingOccurrences(of: token, with: " ", options: [.caseInsensitive, .diacriticInsensitive])
        }
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return result.isEmpty ? nil : result
    }
    private func match(identifier: String?, subject: String?) async throws -> CalendarEventSnapshot {
        guard let identifier else { return try await match(subject) }
        try await calendar.requestFullAccessIfNeeded()
        var cal = Calendar.autoupdatingCurrent; cal.timeZone = timeZone
        let values = try await calendar.events(from: cal.date(byAdding: .day, value: -1, to: now())!, to: cal.date(byAdding: .day, value: 90, to: now())!)
        guard let exact = values.first(where: { $0.identifier == identifier }) else { throw EventKitExecutionError.itemNotFound }
        return exact
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
    private func queryInterval(dayPeriod: String?, instant: Date) -> DateInterval {
        let wholeDay = day(instant)
        guard let dayPeriod else { return wholeDay }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let hours: (Int, Int)? = switch dayPeriod {
        case "morning": (6, 12)
        case "afternoon": (12, 18)
        case "evening": (18, 24)
        default: nil
        }
        guard let hours, let start = calendar.date(bySettingHour: hours.0, minute: 0, second: 0, of: instant),
              let end = hours.1 == 24 ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: instant)) : calendar.date(bySettingHour: hours.1, minute: 0, second: 0, of: instant) else { return wholeDay }
        return .init(start: start, end: end)
    }
    private func day(_ date: Date) -> DateInterval { var cal = Calendar.autoupdatingCurrent; cal.timeZone = timeZone; let start = cal.startOfDay(for: date); return .init(start: start, end: cal.date(byAdding: .day, value: 1, to: start)!) }
    private func format(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) }
    private func result(_ kind: EventKitExecutionResult.Kind, _ op: EventKitExecutionResult.Operation, _ title: String, _ date: Date, _ count: Int) -> EventKitExecutionResult { .init(kind: kind, operation: op, title: title, detail: format(date), itemCount: count) }
    private func list(_ values: [String]) -> String { values.isEmpty ? String(localized: "eventkit_empty") : values.prefix(10).joined(separator: "\n") }
}
