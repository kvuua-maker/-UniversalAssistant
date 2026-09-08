import Foundation

/// A role-preserving interpretation produced before capability selection.
/// It intentionally describes the whole command instead of treating any one
/// noun (for example “document”) as an intent.
struct CanonicalSemanticFrame: Equatable, Sendable {
    enum Action: String, Sendable { case open, choose, search, show, create, call, message, scan, recognize, share, navigate, query, set, record }
    enum Object: String, Sendable { case file, photo, document, contact, calendar, reminder, timer, alarm, app, url, place, weather, text, code, note, audio, media }
    enum Source: String, Sendable { case files, photos, clipboard, camera, calendar, reminders }

    var action: Action?
    var object: Object?
    var source: Source?
    var service: String?
    var person: String?
    var app: String?
    var location: String?
    var modifiers: Set<String> = []
    var confidence: Double = 0
}

struct CanonicalSemanticFrameResult: Equatable, Sendable {
    let frame: CanonicalSemanticFrame
    let intent: CommandIntent?
    let entities: [String: String]
}

struct CanonicalSemanticFrameAnalyzer: Sendable {
    func analyze(original: String, normalized: String) -> CanonicalSemanticFrameResult {
        let tokens = lexicalTokens(normalized)
        var frame = CanonicalSemanticFrame()
        frame.action = action(in: tokens)
        frame.object = object(in: tokens)
        frame.source = source(in: tokens)
        frame.service = service(in: tokens)
        frame.app = application(in: tokens)
        frame.modifiers = modifiers(in: tokens)

        if frame.object == .contact || frame.action == .call || frame.action == .message {
            frame.person = trailingEntity(
                original,
                afterActionFamilies: [
                    ["контакт", "contact"], ["подзвон", "зателефон", "набер", "позвон", "call", "dial"],
                    ["напиш", "повідом", "сообщ", "message"]
                ],
                stoppingAt: [" через ", " у whatsapp", " в whatsapp", " via whatsapp", " по whatsapp"]
            )
        }
        frame.location = locationPhrase(in: original)

        let resolved = resolve(frame: frame, original: original, normalized: normalized)
        frame.confidence = resolved.0 == nil ? 0 : confidence(frame)
        return .init(frame: frame, intent: resolved.0, entities: resolved.1)
    }

    private func resolve(
        frame: CanonicalSemanticFrame,
        original: String,
        normalized: String
    ) -> (CommandIntent?, [String: String]) {
        var entities: [String: String] = [:]

        // SOURCE controls the domain. “documents in Photos” is a Photos query;
        // the object alone must never redirect it to Files.
        if frame.source == .photos {
            entities["query"] = frame.modifiers.contains("latest") ? "latest" : semanticPhotoSubject(original)
            if frame.action == .share { entities["requested_action"] = "share" }
            if frame.action == .recognize { entities["requested_action"] = "ocr" }
            return (.photoSearch, entities)
        }
        if frame.source == .files || frame.object == .file ||
            (frame.object == .document && frame.action.map { [.open, .choose].contains($0) } == true) {
            entities["query"] = frame.object == .file ? "file" : "document"
            return (.fileSearch, entities)
        }

        if frame.object == .photo {
            entities["query"] = frame.modifiers.contains("latest") ? "latest" : semanticPhotoSubject(original)
            if frame.action == .share { entities["requested_action"] = "share" }
            if frame.action == .recognize { entities["requested_action"] = "ocr" }
            return (.photoSearch, entities)
        }

        if frame.object == .contact && frame.action.map { [.search, .show, .query].contains($0) } == true {
            if let person = frame.person, !person.isEmpty { entities["contact"] = person }
            return (.contactLookup, entities)
        }
        if frame.action == .call {
            if let person = frame.person, !person.isEmpty { entities["contact"] = person }
            if let service = frame.service { entities["call_service"] = service }
            return (.contactCall, entities)
        }
        if frame.action == .message {
            if let person = frame.person, !person.isEmpty { entities["recipient"] = person }
            if let service = frame.service { entities["message_service"] = service }
            return (.messageCompose, entities)
        }

        if frame.object == .weather || weatherQuestion(normalized) {
            if frame.modifiers.contains("current_location") { entities["near_current_location"] = "true" }
            if let location = frame.location { entities["location"] = location }
            return (.weather, entities)
        }

        if frame.object == .calendar {
            return (frame.action == .create ? .calendarCreate : .calendarQuery, entities)
        }
        if frame.object == .reminder {
            return (frame.action == .create || frame.action == .set ? .reminderCreate : .reminderQuery, entities)
        }
        if frame.object == .timer || frame.object == .alarm {
            return (.deviceAction, ["system_action": frame.object == .timer ? "timer" : "alarm"])
        }

        if frame.action == .scan || frame.action == .recognize {
            if frame.object == .code {
                return (.cameraCapture, ["capture_mode": "code_scan"])
            }
            if frame.object == .document || frame.object == .text {
                return (.cameraCapture, ["capture_mode": "text_scan", "input_source": "document_camera"])
            }
        }

        if frame.action == .record && frame.object == .audio {
            return (.audioRecord, ["recorder_action": "start"])
        }

        if frame.object == .media, let app = frame.app {
            entities["app"] = app
            entities["query"] = mediaSubject(original, app: app)
            return (.mediaSearch, entities)
        }
        if frame.action == .open, let app = frame.app {
            return (.open, ["app": app])
        }

        if frame.action == .navigate {
            if let location = frame.location { entities["destination"] = location }
            return (.navigation, entities)
        }
        return (nil, [:])
    }

    private func lexicalTokens(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private func action(in tokens: [String]) -> CanonicalSemanticFrame.Action? {
        let families: [(CanonicalSemanticFrame.Action, [String])] = [
            (.choose, ["вибер", "обер", "выбер", "select", "choose"]),
            (.share, ["поділ", "подел", "надішл", "відправ", "отправ", "share", "send"]),
            (.recognize, ["розпіз", "распозн", "прочит", "recogn", "read"]),
            (.scan, ["скан", "оцифр", "digitiz"]),
            (.record, ["аудіозап", "аудиозап", "запис", "розпоч", "начн", "record"]),
            (.call, ["подзвон", "зателефон", "набер", "позвон", "call", "dial"]),
            (.message, ["напиш", "повідом", "сообщ", "message"]),
            (.navigate, ["маршрут", "вед", "проклад", "їхат", "ехать", "navigat", "route"]),
            (.create, ["створ", "дод", "созд", "добав", "create", "add", "schedule"]),
            (.set, ["постав", "встанов", "установ", "set"]),
            (.open, ["відкр", "откр", "open", "перейд"]),
            (.search, ["знайд", "пошук", "найд", "search", "find"]),
            (.show, ["покаж", "show", "display"]),
            (.query, ["чи", "який", "яка", "що", "есть", "which", "what"])
        ]
        return families.first { _, roots in tokens.contains { token in roots.contains { token.hasPrefix($0) } } }?.0
    }

    private func object(in tokens: [String]) -> CanonicalSemanticFrame.Object? {
        let families: [(CanonicalSemanticFrame.Object, [String])] = [
            (.contact, ["контакт"]),
            (.audio, ["аудіозап", "аудиозап", "voice", "recording"]),
            (.reminder, ["нагадув", "напомин", "reminder"]),
            (.calendar, ["календар", "поді", "зустр", "событ", "event", "appointment"]),
            (.timer, ["таймер", "timer"]),
            (.alarm, ["будильник", "alarm"]),
            (.code, ["qr", "barcode", "штрихкод", "код"]),
            (.text, ["текст", "text"]),
            (.weather, ["погод", "температур", "дощ", "дожд", "weather", "rain"]),
            (.photo, ["фото", "світлин", "знім", "сним", "photo", "image", "picture"]),
            (.file, ["файл", "file"]),
            (.document, ["документ", "document", "pdf"]),
            (.note, ["нотат", "замет", "note"]),
            (.url, ["url", "посилан", "ссылк", "link"]),
            (.media, ["плейлист", "playlist", "пісн", "песн", "song", "трек", "track"]),
            (.app, ["програм", "застос", "прилож", "app"])
        ]
        return families.first { _, roots in tokens.contains { token in roots.contains { token.hasPrefix($0) } } }?.0
    }

    private func source(in tokens: [String]) -> CanonicalSemanticFrame.Source? {
        if tokens.contains(where: { ["фото", "photos", "photolibrary"].contains($0) }) { return .photos }
        if tokens.contains(where: { ["файлів", "файлах", "files", "icloud", "drive"].contains($0) }) { return .files }
        if tokens.contains(where: { ["буфер", "clipboard"].contains($0) }) { return .clipboard }
        if tokens.contains(where: { token in ["камер", "camera"].contains(where: token.hasPrefix) }) { return .camera }
        return nil
    }

    private func service(in tokens: [String]) -> String? {
        if tokens.contains(where: { $0 == "whatsapp" || $0 == "вотсап" || $0 == "ватсап" }) { return "whatsapp" }
        if tokens.contains("telegram") { return "telegram" }
        if tokens.contains("viber") { return "viber" }
        return nil
    }

    private func application(in tokens: [String]) -> String? {
        if tokens.contains("spotify") { return "Spotify" }
        if tokens.contains("youtube") { return "YouTube" }
        if tokens.contains("whatsapp") { return "WhatsApp" }
        if tokens.contains("telegram") { return "Telegram" }
        if tokens.contains("диктофон") || (tokens.contains("voice") && tokens.contains("memos")) { return "Voice Memos" }
        if tokens.contains("apple") && tokens.contains("music") { return "Apple Music" }
        return nil
    }

    private func modifiers(in tokens: [String]) -> Set<String> {
        var output: Set<String> = []
        if tokens.contains(where: { token in ["остан", "найнов", "найсвіж", "щойно", "послед", "latest", "newest", "recent"].contains(where: token.hasPrefix) }) {
            output.insert("latest")
        }
        if tokens.contains(where: { ["тут", "поруч", "зараз", "моє", "моему", "current", "here"].contains($0) }) {
            output.insert("current_location")
        }
        return output
    }

    private func trailingEntity(_ original: String, afterActionFamilies: [[String]], stoppingAt stops: [String]) -> String? {
        let folded = original.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let allRoots = afterActionFamilies.flatMap { $0 }
        guard let tokenRange = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first(where: { token in
            allRoots.contains { token.hasPrefix($0) }
        }).flatMap({ folded.range(of: String($0)) }) else { return nil }
        var tail = String(original[tokenRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for stop in stops {
            if let range = tail.range(of: stop, options: [.caseInsensitive, .diacriticInsensitive]) {
                tail = String(tail[..<range.lowerBound])
            }
        }
        tail = tail.replacingOccurrences(of: #"^(?:мені|мне|будь ласка|please|чи є в мене)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        tail = tail.replacingOccurrences(of: #"^(?:контакт|повідомлення|сообщение|message)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        return tail.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func locationPhrase(in original: String) -> String? {
        let markers = [" до ", " у ", " в ", " біля ", " поруч із ", " near ", " to "]
        return markers.compactMap { marker -> String? in
            guard let range = original.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
            let value = original[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return value.isEmpty ? nil : value
        }.first
    }

    private func weatherQuestion(_ text: String) -> Bool {
        ["температур", "чи буде дощ", "будет дождь", "weather", "rain"].contains(where: text.contains)
    }

    private func semanticPhotoSubject(_ original: String) -> String {
        original.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mediaSubject(_ original: String, app: String) -> String {
        original.replacingOccurrences(of: app, with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func confidence(_ frame: CanonicalSemanticFrame) -> Double {
        let filled = [frame.action != nil, frame.object != nil, frame.source != nil, frame.person != nil, frame.service != nil, frame.app != nil, frame.location != nil].filter { $0 }.count
        return min(1, 0.55 + Double(filled) * 0.08)
    }
}
