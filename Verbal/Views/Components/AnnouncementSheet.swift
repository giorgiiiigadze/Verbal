//
//  AnnouncementSheet.swift
//  Verbal
//
//  A bottom sheet that introduces something: a badge, a headline, a short list
//  of what it does for you, and one button.
//
//  Built generic rather than as one screen's copy, because the paywall wants
//  exactly this shape — a claim, three reasons, a decision — and the only thing
//  that should differ is the words and what the button does.
//

import SwiftUI

struct AnnouncementSheet<Preview: View>: View {
    struct Point: Identifiable {
        let icon: String
        let text: String
        var id: String { text }
    }

    /// Small pill above the headline: "NEW", "LIMITED PREVIEW".
    let badge: String
    let title: String
    let points: [Point]
    let actionTitle: String
    /// A glimpse of the thing being announced, shown above the badge. Optional
    /// because a claim can stand on its own; a screenshot of nothing cannot.
    @ViewBuilder var preview: Preview
    var onAction: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // The same close the rate sheets use: `Button(role: .close)` laid
            // out by hand, which renders as the word rather than a glyph. No
            // navigation bar, because there is nothing to navigate.
            HStack {
                Spacer()
                // Ink rather than the system's blue: dismissing is not one of
                // the app's actions, and blue here would pull the eye to the
                // way out before the sheet has said anything.
                Button(role: .close) { dismiss() }
                    .tint(Color(.mainText))
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            preview
                .padding(.horizontal, 24)
                .padding(.top, 12)

            Text(badge)
                .font(.caption2.weight(.semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color(.blueAccentText))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.royalBlue25), in: Capsule())
                .padding(.top, 24)

            Text(title)
                .font(.robotoSlab(26, relativeTo: .title2))
                .foregroundStyle(Color(.mainText))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 12)

            VStack(spacing: 0) {
                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    if index > 0 {
                        Divider().padding(.leading, 38)
                    }
                    HStack(spacing: 14) {
                        // Bare glyph, no tile behind it. Three tinted squares
                        // stacked down the sheet read as chrome; the icons are
                        // punctuation for the sentences beside them.
                        Image(systemName: point.icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color(.mainText))
                            .frame(width: 24)
                        Text(point.text)
                            .font(.subheadline)
                            .foregroundStyle(Color(.mainText))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 13)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            // Flexible, so the button stays pinned to the bottom of the sheet.
            // A fixed gap here lets the whole stack centre itself instead, which
            // leaves space above and below and reads as a broken layout.
            Spacer(minLength: 20)

            // A capsule, not the 16pt rectangle the form sheets use: nothing is
            // being saved here. This is an acknowledgement, which is the shape
            // the permission sheet already wears.
            //
            // Ink rather than blue: royal blue is the colour of the app's own
            // actions, and this button acknowledges a message rather than doing
            // anything. It also stops the button competing with the Viewed pill
            // in the card above, which is the thing worth looking at.
            Button {
                onAction()
                dismiss()
            } label: {
                Text(actionTitle)
                    .font(.headline)
                    .foregroundStyle(Color(.surface))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(.mainText), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color(.homeBackground))
        // No `presentationCornerRadius`: the system's own radius is the one
        // every other sheet on the phone has, and it follows the device's own
        // corners. 28 was a guess, and a squarer one than the real thing.
        // Feature introductions use the same warm white ground as the
        // recording intro, rather than the cooler generic sheet surface.
        .presentationBackground(Color(.homeBackground))
    }
}

extension AnnouncementSheet where Preview == EmptyView {
    init(badge: String, title: String, points: [Point], actionTitle: String,
         onAction: @escaping () -> Void = {}) {
        self.init(badge: badge, title: title, points: points,
                  actionTitle: actionTitle, preview: { EmptyView() },
                  onAction: onAction)
    }
}
