import Foundation
#if canImport(MoonshineVoice)
import MoonshineVoice
#endif

/// Reports whether the Moonshine Voice package is actually linked into the app.
/// The ASR swap is staged: build 52 proves the dependency compiles, links and
/// resolves its binary framework on a real device before the controller is
/// replaced.
enum MoonshineEngineProbe {
    static var isLinked: Bool {
        #if canImport(MoonshineVoice)
        return true
        #else
        return false
        #endif
    }

    static var status: String {
        isLinked ? "MoonshineVoice: linked" : "MoonshineVoice: NOT linked"
    }

    /// Model architectures exposed by the package; logged so the next step can
    /// pick streaming vs batch without guessing.
    static var supportedArchitectures: String {
        #if canImport(MoonshineVoice)
        return ModelArch.allCasesDescription
        #else
        return "n/a"
        #endif
    }
}

#if canImport(MoonshineVoice)
extension ModelArch {
    static var allCasesDescription: String { "tiny, base, tinyStreaming, baseStreaming, smallStreaming, mediumStreaming" }
}
#endif
