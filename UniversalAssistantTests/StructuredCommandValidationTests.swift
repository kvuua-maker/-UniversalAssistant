import Testing
@testable import UniversalAssistant

struct StructuredCommandValidationTests {
    private let validator = StructuredCommandValidator()
    private let gate = ConsequentialCommandGate()

    @Test func rejectsEveryUnresolvedExecutionInputBeforeConsequentialAction() throws {
        let command = StructuredCommand(originalText: "Скасуй запис", normalizedText: "скасуй запис", language: .uk, intent: .cancel, risk: .consequential)
        #expect(throws: CommandValidationIssue.ambiguousTarget) { try validator.validate(command, context: .init(isAmbiguous: true)) }
        #expect(throws: CommandValidationIssue.missingTarget) { try validator.validate(command, context: .init(targetResolved: false)) }
        #expect(throws: CommandValidationIssue.permissionDenied) { try validator.validate(command, context: .init(permissionGranted: false)) }
        #expect(throws: CommandValidationIssue.invalidRisk) { try gate.prepare(command, context: .init(), confirmed: false) }
        #expect(try gate.prepare(command, context: .init(), confirmed: true).command == command)
    }

    @Test func validatesDateLocationAndUnknownIntent() throws {
        let parser = LocalCommandEngine()
        #expect(throws: CommandValidationIssue.unresolvedIntent) { try validator.validate(parser.parse("???")) }
        #expect(throws: CommandValidationIssue.missingDateTime) {
            try validator.validate(parser.parse("Сплануй подорож"), context: .init(dateTimeResolved: false))
        }
        #expect(throws: CommandValidationIssue.missingLocation) {
            try validator.validate(parser.parse("Ресторан поруч"), context: .init(locationAvailable: false))
        }
    }
}
