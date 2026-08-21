//
//  RecordingPreferencesView.swift
//  Verbal
//
//  Small controls for how the recording screen behaves.
//

import SwiftUI

enum RecordingPreferences {
    static let hapticsEnabledKey = "recordingHapticsEnabled"

    static var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: hapticsEnabledKey) as? Bool ?? true
    }
}

struct RecordingPreferencesView: View {
    @AppStorage(RecordingPreferences.hapticsEnabledKey) private var hapticsEnabled = true

    var body: some View {
        List {
            Section {
                Toggle("Haptic feedback", isOn: $hapticsEnabled)
                    .tint(.green)
            } footer: {
                Text("Feel a small tap when recording starts, so you know the microphone is live without looking at the screen.")
            }
            .listRowBackground(Color(.cardSurface))
        }
        .scrollContentBackground(.hidden)
        .background(Color(.homeBackground))
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
    }
}
