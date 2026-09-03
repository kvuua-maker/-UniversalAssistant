import Foundation

enum JobsGoldenOutcome: String, Sendable {
  case nativeResults, internalApplication, externalHandoff, published, candidateSearch, invitation,
    watch, interviewProposal, complaintRecorded, protectiveReview, attributedCommercial,
    truthfulFallback, partialResults
}
struct JobsGoldenJourney: Identifiable, Equatable, Sendable {
  let id, request: String
  let expected: JobsGoldenOutcome
  let requiresConfirmation: Bool
}
enum JobsGoldenJourneyCatalog {
  static let canonical: [JobsGoldenJourney] = [
    .init(
      id: "A", request: "Знайди роботу водієм у Києві від 50 000 грн без нічних змін",
      expected: .nativeResults, requiresConfirmation: false),
    .init(
      id: "B", request: "Той самий пошук із достатніми нашими вакансіями", expected: .nativeResults,
      requiresConfirmation: false),
    .init(
      id: "C", request: "Той самий пошук із недостатніми нашими вакансіями",
      expected: .truthfulFallback, requiresConfirmation: false),
    .init(
      id: "D", request: "Подати заявку без необов’язкового CV", expected: .internalApplication,
      requiresConfirmation: true),
    .init(
      id: "E", request: "Подати заявку з обов’язковим CV", expected: .internalApplication,
      requiresConfirmation: true),
    .init(
      id: "F", request: "Опублікувати вакансію перевіреного роботодавця", expected: .published,
      requiresConfirmation: true),
    .init(
      id: "G", request: "Знайти discoverable кандидата", expected: .candidateSearch,
      requiresConfirmation: false),
    .init(
      id: "H", request: "Надіслати кандидату запрошення", expected: .invitation,
      requiresConfirmation: true),
    .init(
      id: "I", request: "Стежити за новими вакансіями водія", expected: .watch,
      requiresConfirmation: true),
    .init(
      id: "J", request: "Запропонувати співбесіду", expected: .interviewProposal,
      requiresConfirmation: true),
    .init(
      id: "K", request: "Поскаржитися: мене не взяли", expected: .complaintRecorded,
      requiresConfirmation: true),
    .init(
      id: "L", request: "Повідомити про вимогу оплати кандидатом", expected: .protectiveReview,
      requiresConfirmation: true),
    .init(
      id: "M", request: "Відкрити вакансію активного комерційного партнера",
      expected: .attributedCommercial, requiresConfirmation: false),
    .init(
      id: "N", request: "Відкрити зовнішню вакансію без revenue evidence",
      expected: .externalHandoff, requiresConfirmation: false),
    .init(
      id: "O", request: "Продовжити пошук коли один provider недоступний",
      expected: .partialResults, requiresConfirmation: false),
  ]
}
