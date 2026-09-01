//
//  RecordingIntroSheet.swift
//  Verbal
//
//  The first recording deserves a short explanation before iOS asks for the
//  microphone. After it is dismissed, recordings always open directly.
//

import SwiftUI

struct RecordingIntroSheet: View {
    var onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DictationLanguage.defaultsKey) private var languageIdentifier = ""

    private var languageName: String {
        let locale = languageIdentifier.isEmpty
            ? Locale.current
            : Locale(identifier: languageIdentifier)
        // Simulator locales can include an implementation-only region override
        // (for example `en_US@rg=gezzzz`). That identifier is useful to iOS but
        // is not a sentence a person should ever see in the intro.
        if let code = locale.language.languageCode?.identifier,
           let name = Locale.current.localizedString(forLanguageCode: code) {
            return name
        }
        return DictationLanguage.label(for: locale)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Image(.recordingIntro)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .foregroundStyle(Color(.mainText))
                    .padding(.top, 70)

                Text("Create quotes\nusing your voice.")
                    .font(.system(size: 38, design: .serif).weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(.mainText))
                    .padding(.top, 30)

                VStack(alignment: .center, spacing: 24) {
                    benefit("globe", "Choose a language to speak in")
                    benefit("waveform", "Describe the job naturally")
                    benefit(asset: "RecordingIntroReview", text: "Review your quote before sending")
                }
                .padding(.top, 42)
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 24)

                NavigationLink {
                    DictationLanguageView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Speech language")
                                .font(.footnote.weight(.medium))
                            Text(languageName)
                                .font(.body)
                        }
                        .foregroundStyle(Color(.mainText))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 90)
                    .background(Color(.cardSurface), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(colorScheme == .dark ? Color(.homeBackground) : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color(.mainText), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
            .background(Color(.homeBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(.homeBackground))
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.body.weight(.medium))
            .foregroundStyle(Color(.mainText))
            .labelStyle(.titleAndIcon)
    }

    private func benefit(asset: String, text: String) -> some View {
        HStack(spacing: 7) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Color(.mainText))
            Text(text)
        }
        .font(.body.weight(.medium))
        .foregroundStyle(Color(.mainText))
    }
}

#Preview {
    RecordingIntroSheet {}
}
