//
//  OnboardingKit.swift
//  Verbal
//
//  The parts every onboarding screen is built from.
//
//  There are eighteen screens now and they have to look like one thing. When
//  the flow was seven, a heading was a `Text` with a font on it in each file;
//  at eighteen that is eighteen chances for one screen to be two points off
//  every other.
//

import SwiftUI

enum OnboardingStyle {
    /// Matches the lighter blue used by the paywall and the quote-share action.
    static let action = Color(.royalBlue600)
}

/// A quiet separation between white onboarding surfaces and the warm page in
/// light mode. Dark mode already has enough contrast, and selected blue
/// controls should stay crisp rather than float above the page.
private extension View {
    @ViewBuilder
    func onboardingSurfaceElevation(_ isElevated: Bool) -> some View {
        if isElevated {
            self.shadow(color: Color.black.opacity(0.07), radius: 8, y: 3)
        } else {
            self
        }
    }
}

/// The question, and the line under it that says why it is being asked.
///
/// Every screen in the flow opens with one of these. The subtitle is optional
/// because two screens are statements rather than questions, and a sentence
/// invented to fill the slot reads worse than the gap.
struct OnboardingHeading: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A tappable capsule, which is how nearly every question in this flow is
/// answered. Tapping, not typing: these screens get answered standing up, with
/// one hand, and a keyboard is the slowest way to say a word the app could
/// have offered.
struct OnboardingChip: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    let isPicked: Bool
    var action: () -> Void

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isPicked ? .white : Color(.mainText))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(isPicked ? OnboardingStyle.action : Color(.cardSurface),
                            in: Capsule())
                .overlay(
                    Capsule().strokeBorder(isPicked ? .clear : Color(.separator),
                                           lineWidth: 0.5)
                )
                .onboardingSurfaceElevation(colorScheme == .light && !isPicked)
        }
        .buttonStyle(.plain)
    }
}

/// A full-width answer, for questions whose options are sentences rather than
/// words. The chip grid is right for "Plumber" and wrong for "On my phone, at
/// night" — four of those wrapped into a paragraph of capsules.
struct OnboardingOptionRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    let isPicked: Bool
    /// Drawn, not an SF Symbol, and stored as a template image so it takes the
    /// row's own ink — white on the picked row, `mainText` on the others.
    /// Optional because a row without one still has to lay out correctly.
    var icon: ImageResource?
    var action: () -> Void

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            HStack(spacing: 14) {
                if let icon {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        // Fixed, so four drawings of different proportions sit
                        // on one optical line rather than each finding its own.
                        .frame(width: 30, height: 30)
                        .foregroundStyle(isPicked ? .white : Color(.mainText))
                        .accessibilityHidden(true)
                }
                Text(text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isPicked ? .white : Color(.mainText))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                // Only ever on the picked row. An empty circle on the other
                // three turns a list of answers into a form of checkboxes.
                if isPicked {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            // Method rows have a 30-point illustration; the newer estimate
            // rows do not. A shared floor keeps every full-width choice the
            // same tap target and visual rhythm either way.
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(isPicked ? OnboardingStyle.action : Color(.cardSurface),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isPicked ? .clear : Color(.separator), lineWidth: 0.5)
            )
            .onboardingSurfaceElevation(colorScheme == .light && !isPicked)
        }
        .buttonStyle(.plain)
    }
}

/// The card every statement screen sits in — the stat, the summary, the
/// milestone. One fill, one hairline, the same radius as the line-item card, so
/// a screen with nothing to tap still belongs to the app.
struct OnboardingCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    var tinted = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(tinted ? Color(.royalBlue25) : Color(.cardSurface),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: tinted ? 0 : 0.5)
            )
            .onboardingSurfaceElevation(colorScheme == .light && !tinted)
    }
}

/// How far through they are.
///
/// The flow is minutes long now rather than seconds, and a run of questions
/// with no end in sight is the shape people abandon. Deliberately a hairline
/// and not a percentage: it should be readable in the corner of the eye and
/// never worth stopping to study.
struct OnboardingProgressBar: View {
    /// 0...1.
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.separator).opacity(0.5))
                Capsule()
                    .fill(OnboardingStyle.action)
                    .frame(width: max(3, geometry.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 3)
        .animation(.easeInOut(duration: 0.3), value: progress)
        .accessibilityHidden(true)
    }
}

/// Every field in the flow that can hold the keyboard.
///
/// One enum for all of them, owned by `OnboardingView`, because the keyboard
/// accessory and the step transitions both need to be able to let go of the
/// focus — and a focus state living in each screen would leave the keyboard up
/// as that screen slid off.
enum OnboardingField: Hashable {
    case customTrade
    case price(String)
    case hourlyRate
    case businessName
    case taxRate
}

/// The bordered container the typed answers sit in — one rounded rectangle,
/// `cardSurface`, hairline border. It was written out five times.
struct OnboardingFieldBox<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.cardSurface),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
            .onboardingSurfaceElevation(colorScheme == .light)
    }
}
