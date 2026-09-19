import Foundation

enum ProductionTerminalOutcome: Sendable {
    case capability(CapabilityExecutionOutcome)
    case weather(WeatherSnapshot)
    case eventKit(EventKitExecutionResult)
    case audioRecorder(AudioRecorderCommand, AudioRecorderState, URL?)
    case exactWeb(WebHandoffResult)
    case clarify(ResultSummary)
    case choices([String])
    case contactChoices([ContactCandidate])
    case confirm(StructuredCommand)
    case systemInstruction(String)
}

/// The sole production execution corridor after routing. It dispatches a
/// frozen RoutePlan to one room and never parses or routes the command again.
@MainActor
final class ProductionExecutionRoomOrchestrator {
    private let weather: any WeatherCommandExecuting
    private let eventKit: any EventKitCommandExecuting
    private let capabilities: any CanonicalCapabilityExecuting
    private let recorder: AudioRecorderController
    private let web: ControlledWebSearchHandoff

    init(
        weather: any WeatherCommandExecuting,
        eventKit: any EventKitCommandExecuting,
        capabilities: any CanonicalCapabilityExecuting,
        recorder: AudioRecorderController,
        web: ControlledWebSearchHandoff
    ) {
        self.weather = weather
        self.eventKit = eventKit
        self.capabilities = capabilities
        self.recorder = recorder
        self.web = web
    }

    func execute(_ plan: RoutePlan) async -> ProductionTerminalOutcome {
        let command = plan.command
        if plan.terminalStrategy == .clarify || command.needsClarification {
            return .clarify(.init(request: command.originalText, intent: command.intent, risk: command.risk))
        }
        if plan.terminalStrategy == .exactWeb {
            return exactWeb(plan)
        }
        if plan.terminalStrategy == .systemInstruction {
            if ["cancel", "modify"].contains(command.entities["reservation_operation"] ?? "") {
                return .systemInstruction("Немає підтвердженого бронювання, яке UniversalAssistant може змінити. Відкрийте сервіс, де було зроблено бронювання.")
            }
            return .systemInstruction("iPhone або зовнішній сервіс не надає публічного способу виконати цю дію автоматично.")
        }
        do {
            switch plan.room {
            case .location where command.intent == .weather:
                return .weather(try await weather.execute(command))
            case .personal where Self.eventKitIntents.contains(command.intent):
                return .eventKit(try await eventKit.execute(command))
            case .media where command.intent == .audioRecord:
                let action = AudioRecorderCommand(rawValue: command.entities["recorder_action"] ?? "start") ?? .start
                await recorder.execute(action)
                return .audioRecorder(action, recorder.state, recorder.recordingURL)
            default:
                return .capability(try await capabilities.execute(plan))
            }
        } catch let error as CanonicalCapabilityExecutionError {
            switch error {
            case .missingParameter:
                return .clarify(.init(request: command.originalText, intent: command.intent, risk: command.risk))
            case let .ambiguous(values):
                return .choices(values)
            case let .ambiguousContacts(values):
                return .contactChoices(values)
            case let .confirmationRequired(prepared):
                return .confirm(prepared)
            case let .systemRestricted(reason):
                return .systemInstruction(Self.systemRestrictionMessage(reason))
            case let .unavailable(reason):
                return .systemInstruction(Self.usefulUnavailableMessage(reason))
            case let .externalProviderRequired(provider), let .providerRequiredNoFallback(provider):
                return .systemInstruction("Для цієї дії потрібне офіційне підключення сервісу: \(provider).")
            }
        } catch let error as EventKitExecutionError {
            switch error {
            case .unresolvedDateTime, .missingSubject, .ambiguousItem:
                return .clarify(.init(request: command.originalText, intent: command.intent, risk: command.risk))
            default:
                return .systemInstruction("iPhone не дозволив виконати цю дію в Календарі або Нагадуваннях. Перевірте доступ у Налаштуваннях.")
            }
        } catch {
            return .systemInstruction("Дію не вдалося завершити через помилку системного механізму. Спробуйте ще раз.")
        }
    }

    private func exactWeb(_ plan: RoutePlan) -> ProductionTerminalOutcome {
        let command = plan.command
        var query = command.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let providerID = plan.providerID,
           let provider = OfficialPublicProviderHandoffRegistry.records.first(where: { $0.id == providerID }) {
            let candidate = command.entities["query"] ?? command.entities["product"] ?? command.originalText
            if let destination = provider.destination(query: candidate), provider.preservesQuery {
                return .exactWeb(.init(query: candidate, destination: destination, kind: .provider))
            }
            if let host = provider.officialEvidence.host {
                query = "site:\(host) \(query)"
            }
        }
        let safe = StructuredCommand(
            originalText: query,
            normalizedText: query.lowercased(),
            language: command.language,
            intent: .webSearch
        )
        do {
            let destination = try web.destination(for: safe, structuredCapabilityAvailable: false)
            return .exactWeb(.init(query: command.originalText, destination: destination))
        } catch {
            return .systemInstruction("Не вдалося створити безпечний точний веб-запит.")
        }
    }

    private static let eventKitIntents: Set<CommandIntent> = [
        .calendarCreate, .calendarQuery, .calendarUpdate, .calendarDelete,
        .reminderCreate, .reminderQuery, .reminderComplete, .reminderDelete,
        .shoppingList, .undo
    ]

    private static func systemRestrictionMessage(_ reason: String) -> String {
        if reason.contains("settings") { return "iPhone не дозволяє сторонньому застосунку відкрити цей системний розділ. Відкрийте Налаштування вручну." }
        if reason.contains("voice_memos") { return "iPhone не надає публічного способу запустити системний Диктофон. UniversalAssistant може записати аудіо власним рекордером." }
        if reason.contains("viber") || reason.contains("telegram") || reason.contains("signal") {
            return "Цей месенджер не надає підтвердженого публічного переходу для прямого виконання цієї дії. Відкрито найглибший доступний контекст, якщо він підтримується."
        }
        return "Ця дія обмежена публічними можливостями iPhone."
    }

    private static func usefulUnavailableMessage(_ reason: String) -> String {
        if reason.contains("notes_database") { return "iPhone не надає стороннім застосункам доступу до всієї бази Нотаток. Можна створити нову нотатку через системне меню поширення." }
        if reason.contains("music") { return "Відтворення не почалося. Відкрийте Apple Music або перевірте підписку й медіатеку." }
        if reason.contains("no_") { return "За цим точним запитом нічого не знайдено." }
        return "Системний механізм не завершив дію. Спробуйте ще раз або перевірте потрібний доступ у Налаштуваннях."
    }
}
