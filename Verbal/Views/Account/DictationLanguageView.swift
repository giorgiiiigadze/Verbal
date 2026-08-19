//
//  DictationLanguageView.swift
//  Verbal
//
//  Settings → Dictation language. Picking one downloads its model right here,
//  with progress, rather than leaving it to stall the first recording — a
//  silent minute on "Preparing" is where a tradesperson decides the mic is
//  broken.
//

import SwiftUI
import Speech
// For the KVO publisher on the download's `Progress`.
import Combine

struct DictationLanguageView: View {
    @AppStorage(DictationLanguage.defaultsKey) private var selected = ""

    @State private var supported: [Locale] = []
    @State private var installed: Set<String> = []
    @State private var automaticLabel = ""
    @State private var isLoading = true

    /// The language being fetched and how far along it is, so one row can show
    /// its own progress instead of the screen showing a spinner over everything.
    @State private var downloadingIdentifier: String?
    @State private var downloadFraction: Double = 0
    @State private var toast: Toast?

    var body: some View {
        List {
            Section {
                row(title: "Automatic",
                    // Naming what automatic landed on is the whole point: a user
                    // with a mis-heard transcript learns nothing from the word
                    // "Automatic" by itself.
                    subtitle: automaticLabel.isEmpty
                        ? "No speech model is available on this iPhone"
                        : "Matches your iPhone — \(automaticLabel)",
                    isSelected: selected.isEmpty) {
                    choose(nil)
                }
            } footer: {
                Text("Verbal listens in this language. Your voice is transcribed on this iPhone — the recording never leaves it.")
            }
            .listRowBackground(Color(.cardSurface))

            Section {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading languages…").foregroundStyle(.secondary)
                    }
                } else if supported.isEmpty {
                    // Reachable for real: a device (or a Simulator) where Apple
                    // ships no speech models at all. An empty section under a
                    // "Languages" heading reads as a bug in the app rather than
                    // an absence on the device.
                    Text("No languages are available on this iPhone. Speech recognition needs iOS to have a model for your language.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(supported, id: \.identifier) { locale in
                        row(title: DictationLanguage.label(for: locale),
                            subtitle: subtitle(for: locale),
                            isSelected: selected == locale.identifier) {
                            choose(locale)
                        }
                    }
                }
            } header: {
                Text("Languages")
            } footer: {
                Text("A language downloads once, then works with no signal at all.")
            }
            .listRowBackground(Color(.cardSurface))
        }
        .scrollContentBackground(.hidden)
        .background(Color(.homeBackground))
        .navigationTitle("Dictation language")
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
        .task { await load() }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(title: String,
                     subtitle: String?,
                     isSelected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Color(.mainText))
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(.royalBlue600))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// What a language row says under its name: the download in progress, then
    /// whether it is ready to use offline.
    private func subtitle(for locale: Locale) -> String? {
        if downloadingIdentifier == locale.identifier {
            return downloadFraction > 0
                ? "Downloading… \(Int(downloadFraction * 100))%"
                : "Downloading…"
        }
        return installed.contains(locale.identifier) ? "Downloaded" : "Downloads when you pick it"
    }

    // MARK: - Choosing

    /// Nil means automatic.
    private func choose(_ locale: Locale?) {
        let previous = DictationLanguage.storedIdentifier
        selected = locale?.identifier ?? ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        guard let locale else { return }
        Task { await install(locale, replacing: previous) }
    }

    /// Fetches the model for a freshly chosen language, and asks the system to
    /// keep it. The choice is already saved before any of this: a download that
    /// fails offline should leave the setting made, because `QuoteRecorder`
    /// downloads what it needs anyway when recording starts.
    private func install(_ locale: Locale, replacing previous: String?) async {
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [],
                                            attributeOptions: [])
        do {
            // A reserved locale is one the system won't reclaim behind the
            // user's back. Releasing the old one keeps us inside the allowance;
            // both are best-effort, so a failure here isn't worth a word.
            if let previous, previous != locale.identifier {
                await AssetInventory.release(reservedLocale: Locale(identifier: previous))
            }
            _ = try? await AssetInventory.reserve(locale: locale)

            guard let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) else {
                // Nil means it's already on the device.
                installed.insert(locale.identifier)
                return
            }

            downloadingIdentifier = locale.identifier
            downloadFraction = 0
            let progress = request.progress
            let watcher = Task { @MainActor in
                for await fraction in progress.publisher(for: \.fractionCompleted).values {
                    downloadFraction = fraction
                }
            }
            defer {
                watcher.cancel()
                downloadingIdentifier = nil
            }

            try await request.downloadAndInstall()
            installed.insert(locale.identifier)
            toast = Toast(style: .success,
                          message: "\(DictationLanguage.label(for: locale)) ready")
        } catch {
            toast = Toast(style: .error,
                          message: "Couldn't download \(DictationLanguage.label(for: locale)). It'll try again when you record.")
        }
    }

    // MARK: - Data

    private func load() async {
        async let locales = DictationLanguage.supportedLocales()
        async let downloaded = DictationLanguage.installedLocales()
        async let automatic = DictationLanguage.automatic()

        supported = await locales
        installed = await downloaded
        automaticLabel = await automatic.map(DictationLanguage.label(for:)) ?? ""
        isLoading = false
    }
}
