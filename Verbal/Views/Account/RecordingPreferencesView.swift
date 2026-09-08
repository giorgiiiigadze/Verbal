//
//  RecordingPreferencesView.swift
//  Verbal
//
//  Small controls for how the recording screen behaves.
//

import SwiftUI

enum RecordingPreferences {
    static let hapticsEnabledKey = "recordingHapticsEnabled"
    static let cloudTranscriptCheckEnabledKey = "cloudTranscriptCheckEnabled"

    static var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: hapticsEnabledKey) as? Bool ?? true
    }
}

struct RecordingPreferencesView: View {
    @AppStorage(RecordingPreferences.hapticsEnabledKey) private var hapticsEnabled = true
    @AppStorage(RecordingPreferences.cloudTranscriptCheckEnabledKey)
    private var cloudTranscriptCheckEnabled = true

    var body: some View {
        List {
            Section {
                Toggle("Haptic feedback", isOn: $hapticsEnabled)
                    .tint(.green)
            } footer: {
                Text("Feel a small tap when recording starts, so you know the microphone is live without looking at the screen.")
            }
            .listRowBackground(Color(.cardSurface))

            Section {
                Toggle("Accuracy check", isOn: $cloudTranscriptCheckEnabled)
                    .tint(.green)
            } footer: {
                Text("Verbal can temporarily send a recording to AssemblyAI for a second pass at the transcript, which helps with names, measurements and noisy sites. It is deleted after the check. With this off, everything stays on your phone.")
            }
            .listRowBackground(Color(.cardSurface))
        }
        .scrollContentBackground(.hidden)
        .background(Color(.accountBackground))
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
    }
}
