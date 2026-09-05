//
//  OnboardingConclusionSteps.swift
//  Verbal
//
//  The third act: what they came for, what it costs, and what happens next.
//
//  Nothing here collects anything the app needs. It exists because someone who
//  has just watched their own voice turn into a priced quote is about to be
//  handed a sign-in screen, and the gap between those two things is where the
//  reason for doing any of it gets forgotten.
//

import StoreKit
import SwiftUI

// MARK: - 15 · What they came for

/// Their answer from the second screen, handed back as a goal.
///
/// The app has now done the thing; this says what the thing was for, in the
/// words they picked rather than the ones marketing would pick. When they
/// skipped that question it says the general version — which is still true, it
/// is simply not theirs.
struct OnboardingGoalStep: View {
    let answers: OnboardingAnswers

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingHeading(title: "This is what\nchanges.")

            VStack(alignment: .leading, spacing: 12) {
                if let goal = answers.method?.goal {
                    promise(goal, icon: "checkmark.circle.fill")
                }
                promise("The quote goes out before you've left the drive.",
                        icon: "checkmark.circle.fill")
                promise("Your prices are already in it.",
                        icon: "checkmark.circle.fill")
                if let saved = answers.hoursSavedPerYear {
                    promise("About \(Int(saved.rounded())) hours a year back.",
                            icon: "checkmark.circle.fill")
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func promise(_ text: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(OnboardingStyle.action)
            Text(text)
                .font(.callout)
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 16 · The commitment check

/// A number they choose about themselves.
///
/// Nothing reads it. It is here because saying "four out of five" about your
/// own intention is a small, cheap act of consistency, and the screen after it
/// asks for money — which is a much easier question to answer having just
/// answered this one.
///
/// Five options and no default. A pre-selected answer would be the app telling
/// them how committed they are.
struct OnboardingCommitmentStep: View {
    @Bindable var model: OnboardingModel

    private static let scale = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeading(
                title: "How serious are\nyou about this?",
                subtitle: "No wrong answer. It just helps to say it."
            )

            HStack(spacing: 8) {
                ForEach(1...Self.scale, id: \.self) { value in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        model.answers.commitment = value
                    } label: {
                        Text("\(value)")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(model.answers.commitment == value
                                             ? .white : Color(.mainText))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(model.answers.commitment == value
                                        ? OnboardingStyle.action : Color(.cardSurface),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(model.answers.commitment == value
                                                  ? .clear : Color(.separator), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: model.answers.commitment)

            HStack {
                Text("Just having a look")
                Spacer()
                Text("Done with paperwork")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let reply = reply {
                Text(reply)
                    .font(.callout)
                    .foregroundStyle(Color(.mainText))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.2), value: model.answers.commitment)
    }

    /// Said back without flattery. A five is not congratulated and a one is not
    /// argued with — either would make the next answer worth less.
    private var reply: String? {
        switch model.answers.commitment {
        case 1, 2: return "Fair enough. Two quotes a day are free, for as long as you want them."
        case 3: return "That's most people. See what a week of it feels like."
        case 4, 5: return "Then the next screen is the honest bit: what it costs."
        default: return nil
        }
    }
}

// MARK: - 17 · What it costs

/// The app is paid, said plainly, before anything asks for a card.
///
/// The comparison is against their own charge-out rate rather than a cup of
/// coffee, because a tradesperson knows exactly what an hour of their time is
/// worth and does not need a barista to explain it. Skipping the rate question
/// leaves the plain sentence, which is still the honest one.
///
/// Nothing is purchased here. The free tier is permanent — two quotes a day,
/// tomorrow and the day after — so this is a statement, not a wall, and the
/// paywall proper waits until they actually hit the cap.
struct OnboardingExpectationsStep: View {
    let answers: OnboardingAnswers
    let monthlyPrice: Double?
    let monthlyDisplayPrice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingHeading(
                title: "What it costs.",
                subtitle: "Said now rather than at the moment you're trying to work."
            )

            OnboardingCard {
                VStack(alignment: .leading, spacing: 16) {
                    row(title: "Free, always",
                        detail: "Two quotes a day. Not a trial — they come back every morning, whether you ever pay or not.")
                    Divider()
                    row(title: priceTitle,
                        detail: "Unlimited quotes, and everything you just set up.")
                }
            }

            if let anchor {
                Text(anchor)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var priceTitle: String {
        guard let monthlyDisplayPrice else { return "Unlimited, monthly" }
        return "\(monthlyDisplayPrice) a month"
    }

    /// Their own rate, their own week. Both halves are optional and the
    /// sentence is assembled from whichever the user actually gave — an anchor
    /// with an invented number in it is worse than no anchor.
    private var anchor: String? {
        let labour = monthlyPrice.flatMap { answers.minutesOfLabour(matching: $0) }
        let hours = answers.hoursPerMonth
        switch (labour, hours) {
        case let (labour?, hours?):
            return "That's about \(labour) minutes of your own labour rate, against the \(OnboardingAnswers.spoken(hours: hours)) a month you said quoting costs you."
        case let (labour?, nil):
            return "That's about \(labour) minutes of your own labour rate."
        case let (nil, hours?):
            return "You said quoting costs you \(OnboardingAnswers.spoken(hours: hours)) a month."
        default:
            return nil
        }
    }

    private func row(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color(.mainText))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 18 · Notifications

/// The last ask, and the only one left.
///
/// It used to end the flow, which meant onboarding finished on a permission
/// dialog. Here it follows the commitment they just made and reads as the
/// mechanism for it rather than as an unrelated request: the reminders are how
/// the quote gets written in the drive instead of at nine at night.
struct OnboardingNotificationsStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .padding(.top, 8)

            Text("Getting your evenings\nback starts here.")
                .font(.robotoSlab(30, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 30)

            Text("A reminder when it's time to visit, and a nudge to record the quote before you drive off — while it's still fresh. You can change this anytime in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Spacer(minLength: 0)
        }
    }

    /// Deliberately visit reminders — useful work the app already does — rather
    /// than vague promises about updates.
    private var preview: some View {
        ZStack(alignment: .topTrailing) {
            notification(icon: "calendar", tint: Color(.royalBlue100),
                         title: "Visit in 15 minutes",
                         message: "Bathroom re-tiling · Marina Kapanadze")
                .padding(.trailing, 12)

            notification(icon: "mic.fill", tint: Color(.royalBlue25),
                         title: "Ready to record your quote",
                         message: "Turn the visit into a quote while it's fresh")
                .padding(.top, 82)
                .padding(.leading, 20)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .padding(18)
        .background(Color(.fieldFill), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func notification(icon: String, tint: Color,
                              title: String, message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color(.mainText))
                .frame(width: 42, height: 42)
                .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.mainText))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.cardSurface), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
