#if canImport(SwiftUI)
import SwiftUI

enum AudioCommandParseResult: Equatable, Sendable {
    case command(kind: AudioCommandKind, numericValue: Double?, textValue: String?)
    case clarification(String)
    case unsupported
}

struct AudioCommandParser: Sendable {
    func parse(_ text: String, knownRooms: Set<String>) -> AudioCommandParseResult {
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = value.range(of: #"(?:volume|гучність)\s*(\d{1,3})\s*%?"#, options: .regularExpression),
           let number = Int(value[match].filter(\.isNumber)), (0...100).contains(number) {
            return .command(kind: .setVolume, numericValue: Double(number) / 100, textValue: nil)
        }
        if value.contains("podcast") || value.contains("подкаст") {
            return .command(kind: .applyDSPProfile, numericValue: nil, textValue: "speech")
        }
        if value.contains("bass") || value.contains("бас") {
            let signed = value.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }.first
            return signed.map { .command(kind: .setBass, numericValue: $0, textValue: nil) } ?? .clarification("На скільки змінити бас?")
        }
        let rooms = knownRooms.filter { value.contains($0.lowercased()) }
        if rooms.count == 1 { return .command(kind: .selectSource, numericValue: nil, textValue: rooms.first) }
        if rooms.count > 1 { return .clarification("Який аудіопристрій обрати?") }
        return .unsupported
    }
}

struct AudioDevicesView: View {
    let records: [AudioDeviceCapabilityRecord]
    var body: some View {
        List {
            Section("Поточний аудіовихід") { SystemAudioRoutePicker().frame(height: 44) }
            ForEach(records, id: \.identity.scopeKey) { record in
                Section(record.identity.modelFamily ?? record.identity.vendor) {
                    Text(record.identity.roomID ?? "Аудіопристрій")
                    ForEach(record.capabilities.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { capability in
                        if let evidence = record.capabilities[capability], evidence.state != .unsupportedVerified,
                           evidence.state != .unknown {
                            HStack { Text(capability.rawValue); Spacer(); Text(label(evidence)) }
                                .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .navigationTitle("Аудіопристрої")
    }
    private func label(_ evidence: AudioCapabilityEvidence) -> String {
        switch evidence.state {
        case .systemHandoffOnly: "Системне налаштування"
        case .readOnly: "Лише стан"
        case .supportedLiveRequired: "Потребує пристрою"
        case .supportedVerifiedLocal: evidence.mechanism == .assistantDSP ? "DSP UniversalAssistant" : "Керування пристроєм"
        case .unsupportedVerified, .unknown: "Недоступно"
        }
    }
}

/// The system route picker is the only public authoritative UI for choosing
/// current AirPlay/system audio outputs. It does not pretend that a generic BLE
/// scan can enumerate or pair A2DP accessories.
struct AudioRouteSelectionView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "airplayaudio")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Вибрати аудіовихід")
                .font(.title2.bold())
            Text("iPhone покаже доступні системні та AirPlay-аудіовиходи.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            SystemAudioRoutePicker()
                .frame(width: 64, height: 52)
                .accessibilityLabel("Вибрати аудіовихід")
        }
        .padding(28)
        .navigationTitle("Вибрати аудіовихід")
    }
}
#endif
