import SwiftUI

struct RecordingStatusPill: View {
    let state: AudioRecorderState
    var body: some View {
        if state == .recording || state == .paused {
            Label(state == .recording ? "recording_active" : "recording_paused", systemImage: state == .recording ? "record.circle.fill" : "pause.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(state == .recording ? .red : .orange)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .accessibilityIdentifier("recorder.state")
        }
    }
}
