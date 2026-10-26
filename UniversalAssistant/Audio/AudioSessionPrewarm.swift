import AVFoundation

/// Prepares the audio pipeline once at launch so the first microphone tap does
/// not pay for session activation and hardware warm-up.
enum AudioSessionPrewarm {
    private static var didPrepare = false

    static func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setPreferredSampleRate(16_000)
            try session.setActive(true, options: [])
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            RuntimeDiagnostics.log("audio", "prewarm failed: \(error)")
        }
    }
}
