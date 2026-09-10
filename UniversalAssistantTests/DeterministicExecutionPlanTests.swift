import Testing
@testable import UniversalAssistant

@Suite("Deterministic typed execution plans")
struct DeterministicExecutionPlanTests {
    @Test func simpleKnownCommandUsesFastPathWithZeroAI() throws {
        let command = LocalCommandEngine().parse("Відкрий Telegram")
        let plan = try DeterministicExecutionPlanBuilder().plan(for: command)
        #expect(plan.aiInvocationCount == 0)
        #expect(try plan.parallelGroups().count == 1)
        #expect(plan.steps.first?.capability == .directAction)
    }

    @Test func travelModulesFormIndependentParallelGroupWithZeroAI() throws {
        let command = StructuredCommand(originalText: "travel", normalizedText: "travel", language: .en, intent: .travelPlan)
        let plan = try DeterministicExecutionPlanBuilder().plan(for: command)
        let groups = try plan.parallelGroups()
        #expect(plan.aiInvocationCount == 0)
        #expect(groups.first?.map(\.capability).contains(.location) == true)
        let providerGroup = try #require(groups.first { Set($0.map(\.capability)) == [.weather, .transport, .hotel] })
        #expect(providerGroup.count == 3)
    }

    @Test func calendarDeadlineIsARealPrerequisiteForTravelAndHotel() throws {
        let command = StructuredCommand(originalText: "travel", normalizedText: "travel", language: .en, intent: .travelPlan)
        let plan = try DeterministicExecutionPlanBuilder().plan(for: command)
        #expect(plan.steps.first { $0.capability == .transport }?.dependencies.contains("calendar") == true)
        #expect(plan.steps.first { $0.capability == .hotel }?.dependencies.contains("calendar") == true)
    }

    @Test func unresolvedCommandDoesNotGuessOrInvokeAIInsidePlanner() {
        let command = LocalCommandEngine().parse("незрозумілий запит")
        #expect(throws: ExecutionPlanError.unresolvedCommand) { try DeterministicExecutionPlanBuilder().plan(for: command) }
    }

    @Test func cyclesAreRejected() {
        let plan = DeterministicExecutionPlan(commandID: .init(), intent: .multiStep, constraints: [], steps: [
            .init(id: "a", capability: .calendar, dependencies: ["b"]),
            .init(id: "b", capability: .location, dependencies: ["a"])
        ], completionStepID: "b", aiInvocationCount: 0)
        #expect(throws: ExecutionPlanError.cyclicDependencies) { try plan.parallelGroups() }
    }
}

private struct TypedCompoundParser: CommandParsing {
    let intents: [String: CommandIntent]
    func parse(_ text: String) -> StructuredCommand {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let intent = intents[key] ?? .unknown
        return .init(originalText: text, normalizedText: key, language: .en, intent: intent,
                     entities: intent == .cameraCapture && key.contains("ocr") ? ["capture_mode": "text_scan"] : [:])
    }
}

extension DeterministicExecutionPlanTests {
    private func compound(_ text: String) -> StructuredCommand {
        .init(originalText: text, normalizedText: text.lowercased(), language: .en, intent: .multiStep)
    }

    @Test func typedPlannerEmitsEveryEligibleParsedLocalIntentWithoutInventingSteps() throws {
        let intents: [CommandIntent] = [.calendarCreate, .calendarQuery, .calendarUpdate, .calendarDelete,
            .reminderCreate, .reminderQuery, .reminderComplete, .reminderDelete, .shoppingList, .undo,
            .contactLookup, .contactCall, .messageCompose, .photoSearch, .fileSearch, .cameraCapture, .translation,
            .audioRecord, .mediaSearch, .placeSearch, .navigation, .routeAwareSearch]
        let names = intents.enumerated().map { "op\($0.offset)" }
        let parser = TypedCompoundParser(intents: Dictionary(uniqueKeysWithValues: zip(names, intents)))
        let plan = try DeterministicExecutionPlanBuilder(parser: parser).plan(for: compound(names.joined(separator: "; ")))
        #expect(plan.steps.compactMap(\.command).map(\.intent) == intents)
        #expect(!plan.steps.contains { [.typedCommand, .deterministicCompose].contains($0.capability) })
        #expect(plan.steps.allSatisfy { $0.command != nil })
        #expect(plan.aiInvocationCount == 0)
    }

    @Test func productionParserRoutesNaturalCompoundRequestIntoTypedPlan() throws {
        let text = "find contact Alice, then call Alice"
        let clauses = CompoundCommandClauses.split(text)
        #expect(clauses.count == 2)
        #expect(clauses.map { LocalCommandEngine().parse($0).intent } == [.contactLookup, .contactCall])
        #expect(LocalCommandEngine().classifiedCompoundIntent(for: text) == .multiStep)
        let command = LocalCommandEngine().parse(text)
        #expect(command.intent == .multiStep)
        let plan = try DeterministicExecutionPlanBuilder().plan(for: command)
        #expect(plan.steps.compactMap(\.command).map(\.intent) == [.contactLookup, .contactCall])
        let lookup = try #require(plan.steps.first { $0.command?.intent == .contactLookup })
        #expect(plan.steps.first { $0.command?.intent == .contactCall }?.dependencies == [lookup.id])
    }

    @Test func authoritativeLanguageBlockPreservesValidatedStructuralCompoundGraphs() throws {
        let samples: [(String, [CommandIntent])] = [
            ("Відскануй текст документа, потім переклади французькою", [.cameraCapture, .translation]),
            ("Знайди найближчу аптеку; проклади до неї маршрут", [.placeSearch, .navigation])
        ]
        for (text, expected) in samples {
            let command = LanguageUnderstandingBlock().parse(text)
            #expect(command.intent == .multiStep)
            let plan = try DeterministicExecutionPlanBuilder().plan(for: command)
            #expect(plan.steps.compactMap(\.command?.intent) == expected)
            #expect(!plan.steps.contains { [.typedCommand, .deterministicCompose].contains($0.capability) })
            #expect(plan.steps.dropFirst().allSatisfy { !$0.dependencies.isEmpty })
        }
    }

    @Test func contactsLookupIsHardDependencyForCall() throws {
        let parser = TypedCompoundParser(intents: ["lookup": .contactLookup, "call": .contactCall])
        let plan = try DeterministicExecutionPlanBuilder(parser: parser).plan(for: compound("lookup, then call"))
        let lookup = try #require(plan.steps.first { $0.command?.intent == .contactLookup })
        let call = try #require(plan.steps.first { $0.command?.intent == .contactCall })
        #expect(call.dependencies == [lookup.id])
    }

    @Test func contactsLookupIsHardDependencyForMessage() throws {
        let parser = TypedCompoundParser(intents: ["lookup": .contactLookup, "message": .messageCompose])
        let plan = try DeterministicExecutionPlanBuilder(parser: parser).plan(for: compound("lookup and then message"))
        let lookup = try #require(plan.steps.first { $0.command?.intent == .contactLookup })
        let message = try #require(plan.steps.first { $0.command?.intent == .messageCompose })
        #expect(message.dependencies == [lookup.id])
    }

    @Test func placesLookupIsHardDependencyForNavigation() throws {
        let parser = TypedCompoundParser(intents: ["places": .placeSearch, "navigate": .navigation])
        let plan = try DeterministicExecutionPlanBuilder(parser: parser).plan(for: compound("places; navigate"))
        let places = try #require(plan.steps.first { $0.command?.intent == .placeSearch })
        let navigation = try #require(plan.steps.first { $0.command?.intent == .navigation })
        #expect(navigation.dependencies == [places.id])
    }

    @Test func routeIsHardDependencyForRouteAwareSearch() throws {
        let parser = TypedCompoundParser(intents: ["navigate": .navigation, "detour": .routeAwareSearch])
        let plan = try DeterministicExecutionPlanBuilder(parser: parser).plan(for: compound("navigate; detour"))
        let route = try #require(plan.steps.first { $0.command?.intent == .navigation })
        let detour = try #require(plan.steps.first { $0.command?.intent == .routeAwareSearch })
        #expect(detour.dependencies == [route.id])
    }

    @Test func ocrIsHardDependencyForTranslation() throws {
        let parser = TypedCompoundParser(intents: ["ocr": .cameraCapture, "translate": .translation])
        let plan = try DeterministicExecutionPlanBuilder(parser: parser).plan(for: compound("ocr; translate"))
        let ocr = try #require(plan.steps.first { $0.command?.intent == .cameraCapture })
        let translation = try #require(plan.steps.first { $0.command?.intent == .translation })
        #expect(translation.dependencies == [ocr.id])
    }

    @Test func calendarAndReminderMutationsDependOnAuthoritativeQueries() throws {
        let parser = TypedCompoundParser(intents: ["calendar": .calendarQuery, "move": .calendarUpdate,
                                                   "reminders": .reminderQuery, "complete": .reminderComplete])
        let plan = try DeterministicExecutionPlanBuilder(parser: parser).plan(for: compound("calendar; move; reminders; complete"))
        let calendar = try #require(plan.steps.first { $0.command?.intent == .calendarQuery })
        let move = try #require(plan.steps.first { $0.command?.intent == .calendarUpdate })
        let reminders = try #require(plan.steps.first { $0.command?.intent == .reminderQuery })
        let complete = try #require(plan.steps.first { $0.command?.intent == .reminderComplete })
        #expect(move.dependencies == [calendar.id])
        #expect(complete.dependencies == [reminders.id])
    }

    @Test func independentTypedStepsRemainParallelWithStableIDs() throws {
        let parser = TypedCompoundParser(intents: ["record": .audioRecord, "photos": .photoSearch, "music": .mediaSearch])
        let command = compound("record; photos; music")
        let first = try DeterministicExecutionPlanBuilder(parser: parser).plan(for: command)
        let second = try DeterministicExecutionPlanBuilder(parser: parser).plan(for: command)
        let concrete = first.steps.filter { $0.command != nil }
        #expect(concrete.allSatisfy { $0.dependencies.isEmpty })
        #expect(!concrete.contains { [.typedCommand, .deterministicCompose].contains($0.capability) })
        #expect(first.steps.map(\.id) == second.steps.map(\.id))
        #expect(try first.parallelGroups().first?.count == 3)
    }

    @Test func unknownClauseIsNotFabricatedIntoOperation() throws {
        let parser = TypedCompoundParser(intents: ["known": .audioRecord])
        let command = compound("known; unsupported; known")
        let plan = try DeterministicExecutionPlanBuilder(parser: parser).plan(for: command)
        #expect(plan.steps.compactMap(\.command).map(\.intent) == [.audioRecord, .audioRecord])
    }

    @Test func naturalPlaceNavigationAndSimpleProductUseConcretePlans() throws {
        for phrase in [
            "Знайди магазин Nike у Києві і покажи, як до нього доїхати",
            "Покажи магазин Nike у Києві та проклади маршрут до нього"
        ] {
            let command = LocalCommandEngine().parse(phrase)
            #expect(command.intent == .multiStep)
            let plan = try DeterministicExecutionPlanBuilder().plan(for: command)
            #expect(!plan.steps.contains { [.typedCommand, .deterministicCompose].contains($0.capability) })
            #expect(plan.steps.contains { $0.capability == .places })
            #expect(plan.steps.contains { $0.capability == .route })
        }
        let product = LocalCommandEngine().parse("Знайди iPhone 17 Pro")
        #expect(product.intent == .productSearch)
        let productPlan = try DeterministicExecutionPlanBuilder().plan(for: product)
        #expect(productPlan.steps.count == 1)
        #expect(productPlan.steps.first?.capability == .directAction)
        #expect(!productPlan.steps.contains { [.typedCommand, .deterministicCompose].contains($0.capability) })
    }
}
