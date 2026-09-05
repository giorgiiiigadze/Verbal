//
//  OnboardingClimaxSteps.swift
//  Verbal
//
//  The second act: the app, in their hands, before anyone has paid for it.
//
//  This is the part the introduction was buying. Everything before it was a
//  question; here they speak a job and watch it come back priced off the rate
//  card they filled in four screens ago.
//
//  What it is not: the real extraction. That runs behind a signed-in user and
//  reads quantities, materials and the customer's name. This matches their
//  words against their own rates on the phone, and the result screen says so
//  plainly — a demo that oversells itself is a promise the first real quote
//  has to break.
//

import StoreKit
import SwiftUI

// MARK: - 10 · Why the microphone

/// A reason before the system takes over.
///
/// iOS gets one dialog, ever, and a refusal is permanent. Spending it cold, on
/// a screen someone hasn't been told the purpose of, is how an app ends up with
/// a recording button that can never work again.
struct OnboardingMicReasonStep: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(.recordingIntro)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 168)
                .padding(.vertical, 8)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Now say one\nout loud.")
                    .font(.robotoSlab(32, relativeTo: .largeTitle))
                    .foregroundStyle(Color(.mainText))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Verbal needs the microphone to hear the job. The audio is transcribed on this phone and never leaves it — only the words do, and only when you make a quote.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 11 · Their first quote, spoken

/// The screen the whole flow exists to reach.
///
/// It suggests a line built out of their own rates, because "say a job" in the
/// abstract is a hard thing to do into a phone held by a stranger's app, and a
/// first recording that comes back empty is worse than no recording at all.
struct OnboardingRecordStep: View {
    @Bindable var model: OnboardingModel

    /// Their first two rates, said the way someone would say them. Falls back
    /// to the plumbing line the opening screen uses when they priced nothing —
    /// an example that prices nothing still shows the shape of the thing.
    private var suggestion: String {
        let names = model.draftRates.prefix(2).map { $0.name.lowercased() }
        switch names.count {
        case 0: return "Replace the toilet, ninety. Three mixer taps."
        case 1: return "\(names[0].capitalizedFirst), and the materials from the supplier."
        default: return "\(names[0].capitalizedFirst), and two \(names[1])."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeading(
                title: "Say a job you'd\nquote today.",
                subtitle: "The way you'd say it to a customer. Ten seconds is plenty."
            )

            OnboardingCard(tinted: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Try something like")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("“\(suggestion)”")
                        .font(.callout)
                        .italic()
                        .foregroundStyle(Color(.mainText))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            transcriptPane

            Spacer(minLength: 0)

            recordControl
                .frame(maxWidth: .infinity)
        }
        // Nothing starts on its own. A screen that is already listening when it
        // appears is a screen nobody agreed to.
        .onChange(of: model.recorder.audioLevel) { _, level in
            guard model.recorder.isRecording else { return }
            model.levels.append(level)
            if model.levels.count > LevelTrace.barCount {
                model.levels.removeFirst(model.levels.count - LevelTrace.barCount)
            }
        }
        .onDisappear {
            // Stepping back out of this screen has to take the audio session
            // with it, or the microphone stays live behind a screen with no
            // sign of it.
            guard model.recorder.isSessionActive else { return }
            Task { await model.recorder.stop() }
        }
    }

    /// What they said, as it lands. Volatile text is dimmer than finalised
    /// text: the recogniser changes its mind mid-phrase, and watching a
    /// confident sentence rewrite itself reads as the app getting it wrong.
    private var transcriptPane: some View {
        OnboardingCard {
            Group {
                if model.recorder.transcript.isEmpty {
                    Text(model.recorder.isRecording
                         ? "Listening…"
                         : "Your words will appear here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .shimmer(active: model.recorder.isRecording)
                } else {
                    Text(spokenText)
                        .font(.callout)
                        .foregroundStyle(Color(.mainText))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        }
    }

    private var spokenText: AttributedString {
        var settled = AttributedString(model.recorder.finalizedText)
        settled.foregroundColor = Color(.mainText)
        var guessing = AttributedString(model.recorder.volatileText)
        guessing.foregroundColor = .secondary
        return settled + guessing
    }

    private var recordControl: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    if model.recorder.isRecording {
                        await model.finishRecording()
                    } else {
                        model.levels.removeAll()
                        await model.recorder.start()
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(model.recorder.isRecording
                              ? Color(.statusDeclinedText) : OnboardingStyle.action)
                        .frame(width: 76, height: 76)
                    Image(systemName: model.recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.recorder.state == .preparing)
            .accessibilityLabel(model.recorder.isRecording ? "Stop recording" : "Start recording")

            if model.recorder.isRecording {
                HStack(spacing: 10) {
                    LevelTrace(levels: model.levels)
                    Text(model.recorder.elapsedText)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else if let message = model.recorder.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(LineItemRow.amber)
                    .multilineTextAlignment(.center)
            } else {
                Text(model.recorder.hasContent ? "Tap to record again" : "Tap and speak")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.recorder.isRecording)
    }
}

// MARK: - 12 · What it turned into

/// Their words, priced.
///
/// Two versions of this screen. When they recorded something it is genuinely
/// theirs — their sentence at the top, their rates in the rows, their currency
/// and tax underneath — and the footnote is honest about the matching being
/// done on the phone rather than by the real extraction.
///
/// When they skipped, or the microphone was already refused, it falls back to
/// the canned card the flow used to end on: still built from their own rates
/// where there are any, and still showing both halves of what the app does —
/// filling prices in, and flagging the ones nobody said.
struct OnboardingResultStep: View {
    let model: OnboardingModel
    let currencyCode: String

    private var title: String {
        if model.hasRecording { return "That's your\nquote." }
        return model.hasAnyRate
            ? "Your first quote is\nhalf-written already."
            : "This is what a job\nturns into."
    }

    private var spokenLine: String {
        if model.hasRecording { return "“\(model.recordedTranscript)”" }
        guard let first = model.draftRates.first else {
            return "“Replace the toilet, ninety. Three mixer taps.”"
        }
        return "“\(first.name.lowercased()), and the materials from the supplier — I'll price those tomorrow.”"
    }

    /// Two of their own rates and one they didn't price, so the sample shows
    /// both halves of what the app does. With nothing saved it falls back to
    /// the same example the first screen used, which is an illustration rather
    /// than a claim.
    private var lines: [OnboardingQuoteDraft.Line] {
        if let draft = model.quoteDraft, !draft.isEmpty { return draft.lines }
        guard !model.draftRates.isEmpty else {
            return [
                .init(description: "Remove old toilet and fit new toilet",
                      quantity: 1, unit: "each", price: 90),
                .init(description: "Mixer taps", quantity: 3, unit: "each", price: nil),
            ]
        }
        var sample = model.draftRates.prefix(2).map {
            OnboardingQuoteDraft.Line(description: $0.name, quantity: 1,
                                      unit: $0.unit, price: $0.price)
        }
        sample.append(.init(description: "Materials from the supplier",
                            quantity: 1, unit: "job", price: nil))
        return sample
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeading(title: title)

            Text(spokenLine)
                .font(.callout)
                .italic()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingStyle.action.opacity(0.5))
                .frame(maxWidth: .infinity)

            LineItemsCard {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    if index > 0 { Divider() }
                    LineItemRow(description: line.description,
                                quantityText: "\(line.quantity) \(line.unit)",
                                isMissingPrice: line.price == nil,
                                lineTotal: line.price.map { $0 * Double(line.quantity) },
                                currencyCode: currencyCode)
                }
            }

            Text(footnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private var footnote: String {
        if model.hasRecording {
            return "Matched against your own rates, on this phone. Once you're signed in, the full extraction reads quantities, materials and the customer's name too."
        }
        return model.hasAnyRate
            ? "Saved to your rate card. Speak a job and these fill themselves in."
            : "Your rate card is a tab away whenever you want to fill it in."
    }
}

// MARK: - 13 · The milestone

/// Setup finished, and the first quote counted.
///
/// The one moment in the flow where the app is allowed to be pleased with
/// itself. It is also where the time saved stops being a projection about a
/// year and becomes a thing that just happened, on their phone, in the last
/// forty seconds.
struct OnboardingMilestoneStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingHeading(title: model.hasRecording
                              ? "One quote in,\nno paperwork."
                              : "You're set up.")

            OnboardingCard(tinted: true) {
                VStack(alignment: .leading, spacing: 18) {
                    tally(value: model.hasRecording ? "1" : "\(model.draftRates.count)",
                          label: model.hasRecording
                            ? "quote written by speaking"
                            : (model.draftRates.count == 1 ? "rate on your card" : "rates on your card"))

                    if model.hasRecording, let saved = model.minutesSavedOnFirstQuote {
                        Divider()
                        tally(value: "\(saved) min", label: "you didn't spend on it")
                    }
                }
            }

            Text(closing)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private var closing: String {
        guard let saved = model.answers.hoursSavedPerYear, model.hasRecording else {
            return "Everything you've set up is waiting on the other side of this."
        }
        return "Do that instead of the paperwork and it's about \(Int(saved.rounded())) hours a year that stop being your evenings."
    }

    private func tally(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(value)
                .font(.robotoSlab(34, relativeTo: .largeTitle))
                .foregroundStyle(OnboardingStyle.action)
            Text(label)
                .font(.callout)
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 14 · The ask

/// The review prompt, at the only point in the flow where it isn't rude.
///
/// Asked here it follows the app doing the thing it claims to do, with their
/// own words on the screen behind it. Asked on launch, or after a paywall, it
/// is a request for a favour from someone who has received nothing.
///
/// iOS decides whether the dialog actually appears — `requestReview` is rate
/// limited and silently does nothing when Apple says so. That is why this is a
/// screen with its own Continue rather than a modal the flow waits on: the
/// step has to work identically when nothing happens.
struct OnboardingReviewStep: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(.recordingIntroReview)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .padding(.vertical, 8)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Worth a\nword?")
                    .font(.robotoSlab(32, relativeTo: .largeTitle))
                    .foregroundStyle(Color(.mainText))
                    .multilineTextAlignment(.center)

                Text("Verbal is built by a very small team. A rating from someone who works in the trade is worth more than any advert we could buy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
    }
}

private extension String {
    /// Capitalises the first letter and leaves the rest alone —
    /// `capitalized` would turn "fit downlights" into "Fit Downlights".
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
