import Foundation
import SwiftUI
@preconcurrency import Translation

struct TranslationProductionResult: Equatable, Sendable {
    let sourceText: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
}

enum TranslationProductionError: Error, Equatable { case unsupportedLanguage, emptyResult, failed }

struct TranslationProductionBoundary: Sendable {
    func result(plan: LocalTranslationPlan, translatedText: String, sourceLanguage: Locale.Language, targetLanguage: Locale.Language) throws -> TranslationProductionResult {
        let translated = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translated.isEmpty else { throw TranslationProductionError.emptyResult }
        return .init(sourceText: plan.text, translatedText: translated, sourceLanguage: sourceLanguage.minimalIdentifier, targetLanguage: targetLanguage.minimalIdentifier)
    }
}

struct TranslationTargetPickerView: View {
    let text: String
    let onSelect: (String, String) -> Void
    var body: some View {
        NavigationStack {
            List {
                Button("Українська") { onSelect(text, "uk") }
                Button("English") { onSelect(text, "en") }
                Button("Deutsch") { onSelect(text, "de") }
                Button("Русский") { onSelect(text, "ru") }
            }.navigationTitle("Мова перекладу")
        }
    }
}

struct AppleTranslationExecutionView: View {
    let plan: LocalTranslationPlan
    let onResult: (TranslationProductionResult) -> Void
    let onFailure: () -> Void
    private var source: Locale.Language? { plan.sourceLanguage.map(Locale.Language.init(identifier:)) }
    private var target: Locale.Language { Locale.Language(identifier: plan.targetLanguage) }
    var body: some View {
        ProgressView("Перекладаю…")
            .translationTask(source: source, target: target) { session in
                do {
                    let availability = try await LanguageAvailability().status(for: plan.text, to: target)
                    guard availability != .unsupported else { onFailure(); return }
                    let response = try await session.translate(plan.text)
                    onResult(try TranslationProductionBoundary().result(plan: plan, translatedText: response.targetText, sourceLanguage: response.sourceLanguage, targetLanguage: response.targetLanguage))
                } catch { onFailure() }
            }
    }
}
