import Foundation

enum GoldenJourneyVerification: String, Codable, Sendable { case executableLocal, readyForLiveVerification }
enum GoldenJourneyExpectedStatus: String, Codable, Sendable { case pass, fail, readyForLiveVerification }

struct GoldenJourneyDefinition: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let input: String
    let language: CommandLanguage
    let expectedIntent: CommandIntent
    let requiredCapabilities: [String]
    let truthAndSourceRequirement: String
    let sideEffectRule: String
    let expectedUIResult: String
    let failureBehavior: String
    let evidenceTest: String
    let verification: GoldenJourneyVerification
    let manualBaselineSteps: Int
    let genericAIBaselineSteps: Int?
}

struct GoldenJourneyExecution: Equatable, Sendable {
    let journeyID: String
    let recognizedText: String
    let parsedIntent: CommandIntent
    let parsedEntities: [String: String]
    let providerOrSource: String
    let actualResultOrAction: String
    let latencyMilliseconds: Double
    let taps: Int
    let confirmations: Int
    let status: GoldenJourneyExpectedStatus
    let failureReason: String?
}

struct GoldenJourneyRunner: Sendable {
    private let parser = LanguageUnderstandingBlock()
    private let planner = DeterministicExecutionPlanBuilder()

    func execute(_ journey: GoldenJourneyDefinition) -> GoldenJourneyExecution {
        let start = ContinuousClock.now
        let command = parser.parse(journey.input)
        let correct = command.intent == journey.expectedIntent
        let action: String
        var failure: String?
        if correct && command.intent != .unknown {
            do { action = try planner.plan(for: command).completionStepID }
            catch { action = "unavailable"; failure = "typed_plan_rejected" }
        } else if correct && command.needsClarification {
            action = "bounded_interpretation_candidate"
        } else {
            action = "unavailable"; failure = "intent_mismatch"
        }
        let elapsed = start.duration(to: .now)
        let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
        return .init(journeyID: journey.id, recognizedText: command.normalizedText, parsedIntent: command.intent,
                     parsedEntities: command.entities, providerOrSource: journey.requiredCapabilities.joined(separator: "+"),
                     actualResultOrAction: action, latencyMilliseconds: milliseconds, taps: command.intent == .unknown ? 1 : 0,
                     confirmations: command.risk == .consequential ? 1 : 0,
                     status: failure == nil ? (journey.verification == .executableLocal ? .pass : .readyForLiveVerification) : .fail,
                     failureReason: failure)
    }
}

enum GoldenUserJourneyCatalog {
    private struct Family {
        let slug: String; let inputs: [String]; let intent: CommandIntent; let capabilities: [String]
        let truth: String; let safety: String; let ui: String; let failure: String; let evidence: String
        let verification: GoldenJourneyVerification; let manual: Int; let ai: Int?
    }

    static let journeys: [GoldenJourneyDefinition] = families.flatMap { family in
        zip(CommandLanguage.allGoldenLanguages, family.inputs).map { language, input in
            .init(id: "GJ-\(family.slug.uppercased())-\(language.rawValue.uppercased())", input: input, language: language,
                  expectedIntent: family.intent, requiredCapabilities: family.capabilities,
                  truthAndSourceRequirement: family.truth, sideEffectRule: family.safety,
                  expectedUIResult: family.ui, failureBehavior: family.failure, evidenceTest: family.evidence,
                  verification: family.verification, manualBaselineSteps: family.manual, genericAIBaselineSteps: family.ai)
        }
    }

    private static let families: [Family] = [
        .init(slug:"app-open", inputs:["Відкрий Telegram","Открой Telegram","Open Telegram","Öffne Telegram","Ouvre Telegram"], intent:.open, capabilities:["app-routing"], truth:"Installed-app registry only", safety:"No confirmation", ui:"Immediate app handoff", failure:"Explain unavailable app", evidence:"LocalActionRouterTests", verification:.executableLocal, manual:2, ai:3),
        .init(slug:"weather", inputs:["Покажи погоду","Покажи погоду","Show weather","Zeige Wetter","Montre météo"], intent:.weather, capabilities:["weather"], truth:"Fresh provider result only", safety:"Read-only", ui:"Weather card with source/time", failure:"Unavailable, never invent", evidence:"WeatherContextTests", verification:.readyForLiveVerification, manual:3, ai:3),
        .init(slug:"navigation", inputs:["Веди додому","Маршрут до дома","Navigate home","Route to home","Itinéraire vers maison"], intent:.navigation, capabilities:["location","navigation"], truth:"Validated location and route provider", safety:"Explicit route handoff", ui:"Route card/action", failure:"Request missing destination/location", evidence:"RouteNavigationTests", verification:.readyForLiveVerification, manual:4, ai:4),
        .init(slug:"calendar", inputs:["Додай зустріч завтра","Создай встреч завтра","Add event tomorrow","Termin erstellen morgen","Ajoute un rendez-vous demain"], intent:.calendarCreate, capabilities:["calendar","relative-date"], truth:"EventKit result", safety:"Confirm resolved time before mutation", ui:"Event confirmation", failure:"No fake event", evidence:"CalendarServiceTests", verification:.readyForLiveVerification, manual:4, ai:4),
        .init(slug:"reminder", inputs:["Нагадай завтра","Напомни завтра","Remind tomorrow","Erinnere morgen","Rappelle demain"], intent:.reminderCreate, capabilities:["reminders","relative-date"], truth:"EventKit identifier", safety:"Reversible mutation", ui:"Reminder status", failure:"No fake reminder", evidence:"ReminderServiceTests", verification:.readyForLiveVerification, manual:4, ai:4),
        .init(slug:"email-action", inputs:["Напиши мамі","Отправь сообщение маме","Message Mum","Schreib Mama","Écris à maman"], intent:.messageCompose, capabilities:["contacts","messaging"], truth:"Resolved contact plus system composer", safety:"User confirms send", ui:"Composer", failure:"Keep draft/unavailable", evidence:"MessagingIntegrationTests", verification:.readyForLiveVerification, manual:4, ai:5),
        .init(slug:"call", inputs:["Подзвони мамі","Позвони маме","Call Mum","Ruf Mama","Appelle maman"], intent:.contactCall, capabilities:["contacts","calling"], truth:"Exact resolved contact", safety:"Consequential call confirmation", ui:"Call action", failure:"Clarify ambiguous contact", evidence:"UniversalDeviceCommandRouterTests", verification:.readyForLiveVerification, manual:3, ai:4),
        .init(slug:"commerce", inputs:["Знайди чорні кросівки","Найди черные кроссовки","Find black shoes","Finde schwarze Schuhe","Trouve chaussures noires"], intent:.productSearch, capabilities:["commerce-search"], truth:"Provider price/availability freshness", safety:"Purchase is handoff only", ui:"Ranked offer cards", failure:"Partial verified alternatives", evidence:"CommerceSearchEngineTests", verification:.readyForLiveVerification, manual:5, ai:5),
        .init(slug:"grocery", inputs:["Кошик продуктів","Корзина продуктов","Grocery basket","Warenkorb Lebensmittel","Panier courses"], intent:.groceryBasket, capabilities:["grocery","commerce"], truth:"Exact delivered cost where available", safety:"No silent order", ui:"Comparable basket cards", failure:"Disclose incomplete basket", evidence:"GroceryBasketEngineTests", verification:.readyForLiveVerification, manual:6, ai:6),
        .init(slug:"appointment", inputs:["Знайди стоматолога","Найди стоматолога","Find dentist","Finde Zahnarzt","Trouve dentiste"], intent:.serviceSearch, capabilities:["appointments","places"], truth:"Fresh authoritative slots", safety:"Explicit booking confirmation", ui:"Verified slot cards", failure:"Handoff is not confirmed booking", evidence:"AppointmentEngineTests", verification:.readyForLiveVerification, manual:6, ai:6),
        .init(slug:"ticket", inputs:["Квиток до Львова","Билет до Львова","Ticket to London","Fahrkarte nach Berlin","Billet pour Paris"], intent:.ticketSearch, capabilities:["ticket-search","transport"], truth:"Provider schedule/fare", safety:"Purchase handoff", ui:"Ticket options", failure:"Unknown price remains unknown", evidence:"TicketEngineTests", verification:.readyForLiveVerification, manual:5, ai:5),
        .init(slug:"hotel", inputs:["Готель у Львові","Отель во Львове","Hotel in London","Hotel in Berlin","Hôtel à Paris"], intent:.hotelSearch, capabilities:["hotel-search"], truth:"Fresh availability/total price", safety:"Booking handoff", ui:"Hotel cards", failure:"Truthful partial coverage", evidence:"HotelSearchEngineTests", verification:.readyForLiveVerification, manual:5, ai:5),
        .init(slug:"parcel", inputs:["Покажи посилку","Покажи посылку","Show parcel","Zeige Paket","Montre colis"], intent:.show, capabilities:["parcel-tracking"], truth:"Carrier-authoritative state", safety:"Read-only", ui:"Tracking timeline", failure:"Carrier unavailable, no guessed status", evidence:"ParcelDeliveryEngineTests", verification:.readyForLiveVerification, manual:4, ai:4),
        .init(slug:"government", inputs:["Відкрий Дію","Открой Дию","Open Diia","Öffne Diia","Ouvre Diia"], intent:.open, capabilities:["official-government-handoff"], truth:"Official allowlisted endpoint/app", safety:"User completes protected action", ui:"Official handoff", failure:"Reject private/third-party access", evidence:"GovernmentLocalServicesEngineTests", verification:.readyForLiveVerification, manual:3, ai:4),
        .init(slug:"routine", inputs:["Коли я кажу додому, відкривай маршрут","Когда я говорю домой, открой маршрут","When I say home, open route","Wenn ich Zuhause sage, öffne Route","Quand je dis maison, ouvre itinéraire"], intent:.multiStep, capabilities:["routine-macro","navigation"], truth:"Typed capability graph", safety:"Per-action permission/confirmation", ui:"Routine review", failure:"Clarify unsupported wording", evidence:"RoutineMacroEngineTests", verification:.executableLocal, manual:6, ai:5),
        .init(slug:"accounts", inputs:["Налаштування акаунтів","Настройки аккаунтов","Account settings","Kontoeinstellungen","Réglages du compte"], intent:.settings, capabilities:["connected-accounts"], truth:"Actual connection state", safety:"OAuth/revoke boundary", ui:"Account hub", failure:"No fake connected state", evidence:"ConnectedAccountsHubTests", verification:.executableLocal, manual:3, ai:4),
        .init(slug:"partial-failure", inputs:["Покажи погоду зараз","Покажи погоду сейчас","Show weather now","Zeige Wetter jetzt","Montre météo maintenant"], intent:.weather, capabilities:["provider-fanout","weather"], truth:"Only successful provider facts", safety:"Read-only", ui:"Partial result plus warning", failure:"One provider cannot block others", evidence:"ProviderFanoutEngineTests", verification:.executableLocal, manual:3, ai:3),
        .init(slug:"offline", inputs:["Відкрий нотатки","Открой заметки","Open Notes","Öffne Notizen","Ouvre Notes"], intent:.noteQuery, capabilities:["local-action"], truth:"Truthful local public-API boundary", safety:"No network", ui:"Local limitation when Notes data is unavailable", failure:"Never fabricate Notes access or use web", evidence:"LocalActionRouterTests", verification:.executableLocal, manual:2, ai:3),
        .init(slug:"consequential-cancel", inputs:["Скасуй запис","Отмени запись","Cancel booking","Storniere Buchung","Annule réservation"], intent:.cancel, capabilities:["interaction-safety","appointments"], truth:"Exact authoritative object", safety:"Mandatory confirmation", ui:"Confirmation then status", failure:"No mutation without confirmation", evidence:"InteractionDecisionEngineTests", verification:.executableLocal, manual:4, ai:5),
        .init(slug:"bounded-ai", inputs:["Підбери щось атмосферне","Подбери что-то атмосферное","Something atmospheric, please","Etwas Atmosphärisches bitte","Quelque chose d'atmosphérique"], intent:.unknown, capabilities:["deterministic-router","bounded-ai-interpretation"], truth:"AI supplies constraints only, never facts", safety:"Exactly one schema-validated fallback", ui:"Clarification or deterministic result", failure:"Timeout returns deterministic fallback", evidence:"BoundedAIInterpretationTests", verification:.executableLocal, manual:5, ai:2)
    ]
}

private extension CommandLanguage {
    static let allGoldenLanguages: [Self] = [.uk, .ru, .en, .de, .fr]
}
