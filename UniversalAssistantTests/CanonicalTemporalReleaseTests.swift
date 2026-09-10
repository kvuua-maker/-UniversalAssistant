import Foundation
import Testing
@testable import UniversalAssistant

private actor Build31TemporalEventKitBoundary: EventKitCommandExecuting {
    private(set) var commands: [StructuredCommand] = []

    func execute(_ command: StructuredCommand) async throws -> EventKitExecutionResult {
        commands.append(command)
        let reminder = [.reminderCreate, .reminderQuery, .reminderComplete, .reminderDelete].contains(command.intent)
        let operation: EventKitExecutionResult.Operation =
            [.calendarQuery, .reminderQuery].contains(command.intent) ? .queried : .created
        return .init(
            kind: reminder ? .reminder : .calendar,
            operation: operation,
            title: reminder ? "Нагадування" : "Подія",
            detail: "typed-temporal-boundary",
            itemCount: 1
        )
    }

    func allCommands() -> [StructuredCommand] { commands }
}

@Suite("Build 31 typed temporal Release root", .serialized)
@MainActor
struct Build31TemporalReleaseTests {
    private func wait(_ predicate: @escaping @MainActor () async -> Bool) async throws {
        for _ in 0..<120 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Release-root request did not terminate")
    }

    @Test func typedTemporalRolesDistinguishDurationDeadlineDateAndClock() {
        let language = LanguageUnderstandingBlock()

        let timer = language.parse("Запусти таймер для настою на хвилину")
        #expect(timer.intent == .deviceAction)
        #expect(timer.entities["system_action"] == "timer")
        #expect(timer.entities["temporal_kind"] == "duration")
        #expect(timer.entities["duration_seconds"] == "60")
        #expect(timer.needsClarification == false)

        let reminder = language.parse("Нагадай через дев'яносто хвилин перевірити звіт")
        #expect(reminder.intent == .reminderCreate)
        #expect(reminder.entities["temporal_kind"] == "relative_deadline")
        #expect(reminder.entities["relative_interval_seconds"] == "5400")
        #expect(reminder.needsClarification == false)

        let event = language.parse("Створи подію наступної середи о 14:10 для огляду макета")
        #expect(event.intent == .calendarCreate)
        #expect(event.entities["temporal_kind"] == "date_time")
        #expect(event.entities["weekday"] == "4")
        #expect(event.entities["hour"] == "14")
        #expect(event.entities["minute"] == "10")
        #expect(event.needsClarification == false)

        let absolute = language.parse("Додай у календар на 21/10/2026 о 09:15 аудит релізу")
        #expect(absolute.intent == .calendarCreate)
        #expect(absolute.entities["calendar_year"] == "2026")
        #expect(absolute.entities["calendar_month"] == "10")
        #expect(absolute.entities["calendar_day"] == "21")
        #expect(absolute.needsClarification == false)

        let alarm = language.parse("Увімкни будильник на 7 35 ранкова зарядка")
        #expect(alarm.intent == .deviceAction)
        #expect(alarm.entities["system_action"] == "alarm")
        #expect(alarm.entities["hour"] == "07")
        #expect(alarm.entities["minute"] == "35")
        #expect(alarm.needsClarification == false)
    }

    @Test func incompatibleOrIncompleteTemporalRolesClarifyLocally() {
        let language = LanguageUnderstandingBlock()
        for input in [
            "Увімкни таймер",
            "Створи будильник",
            "Постав таймер на три хвилини о 12:00",
            "Створи подію завтра для огляду документа"
        ] {
            let command = language.parse(input)
            #expect(command.needsClarification, "Expected local clarification for: \(input)")
            #expect(command.intent != .webSearch && command.intent != .unknown)
            #expect(command.entities["clarification_role"] == "temporal")
        }

        let arithmetic = language.parse("Поділи сто двадцять на чотири, а результат помнож на три")
        #expect(arithmetic.intent == .localUtility)
        #expect(arithmetic.intent != .calendarCreate)
    }

    @Test func typedDateResolverConsumesSemanticEntitiesRatherThanReparsingRawText() throws {
        let zone = TimeZone(identifier: "Europe/Kyiv")!
        let reference = ISO8601DateFormatter().date(from: "2026-09-10T08:00:00Z")!
        let resolver = NaturalDateTimeResolver()

        let weekday = LanguageUnderstandingBlock().parse("Створи подію наступної середи о 14:10 огляд")
        let weekdayValue = try #require({
            if case let .resolved(value) = resolver.resolve(
                weekday, locale: Locale(identifier: "uk_UA"), timeZone: zone, relativeTo: reference
            ) { return value }
            return nil
        }())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let weekdayParts = calendar.dateComponents([.weekday, .hour, .minute], from: weekdayValue.instant)
        #expect(weekdayParts.weekday == 4)
        #expect(weekdayParts.hour == 14)
        #expect(weekdayParts.minute == 10)

        let absolute = LanguageUnderstandingBlock().parse("Додай у календар на 21/10/2026 о 09:15 аудит")
        let absoluteValue = try #require({
            if case let .resolved(value) = resolver.resolve(
                absolute, locale: Locale(identifier: "uk_UA"), timeZone: zone, relativeTo: reference
            ) { return value }
            return nil
        }())
        let absoluteParts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: absoluteValue.instant)
        #expect(absoluteParts.year == 2026)
        #expect(absoluteParts.month == 10)
        #expect(absoluteParts.day == 21)
        #expect(absoluteParts.hour == 9)
        #expect(absoluteParts.minute == 15)
    }

    @Test func releaseCompositionRoutesTypedTemporalFamiliesAndNeverUsesWeb() async throws {
        let eventKit = Build31TemporalEventKitBoundary()
        var alarmActions: [SystemQuickAction] = []
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [],
            compactResultDuration: .seconds(60),
            alarmExecute: { action in
                alarmActions.append(action)
                return "typed-alarm-boundary"
            },
            eventKit: eventKit
        )

        for input in [
            "Створи подію наступного вівторка о 13:25 технічний огляд",
            "Нагадай через сімдесят хвилин перевірити резервну копію"
        ] {
            model.input = input
            model.submit()
            try await wait { await eventKit.allCommands().count == (input.contains("подію") ? 1 : 2) }
            #expect({ if case .webHandoff = model.resultState { return false }; return true }())
        }

        for input in [
            "Запусти таймер для ферментації на хвилину",
            "Увімкни будильник на 6 45 ранкова прогулянка"
        ] {
            model.input = input
            model.submit()
            try await wait { alarmActions.count == (input.contains("таймер") ? 1 : 2) }
            #expect({ if case .webHandoff = model.resultState { return false }; return true }())
        }

        let commands = await eventKit.allCommands()
        #expect(commands.map(\.intent) == [.calendarCreate, .reminderCreate])
        #expect(commands[0].entities["weekday"] == "3")
        #expect(commands[1].entities["relative_interval_seconds"] == "4200")

        guard case let .startTimer(seconds, _) = alarmActions[0] else {
            Issue.record("Timer did not reach AlarmKit boundary")
            return
        }
        #expect(seconds == 60)
        guard case let .createAlarm(hour, minute, _) = alarmActions[1] else {
            Issue.record("Alarm did not reach AlarmKit boundary")
            return
        }
        #expect(hour == 6 && minute == 45)

        model.input = "Створи будильник"
        model.submit()
        try await wait { if case .clarification = model.resultState { return true }; return false }
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
        #expect(model.statusText != AppText.value("processing"))

        model.input = "Розділи дев'яносто шість на вісім, потім результат додай до п'яти"
        model.submit()
        try await wait { if case .deterministic = model.resultState { return true }; return false }
        guard case let .deterministic(arithmeticResult) = model.resultState else {
            Issue.record("Compound arithmetic did not reach the local Release executor")
            return
        }
        #expect(arithmeticResult.primaryAnswer == "17")
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }
}
