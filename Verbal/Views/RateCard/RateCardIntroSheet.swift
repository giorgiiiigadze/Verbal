//
//  RateCardIntroSheet.swift
//  Verbal
//
//  Shown once, the first time someone opens the rate card. The tag button in
//  the Home header gives no clue what is behind it, and the rate card only pays
//  off later — in a recording that prices itself — so it is worth one screen of
//  explanation before the empty list.
//
//  A full sheet rather than the fitted `AnnouncementSheet`: this one is
//  introducing a place they are about to be taken to, not delivering a notice,
//  and it wants room for a picture of that place at the top.
//
//  Placeholder copy: the headline and the three points are meant to be
//  rewritten.
//

import SwiftUI

struct RateCardIntroSheet: View {
    /// Runs when they choose to go on. The sheet dismisses itself either way;
    /// this is what opens the rate card behind it.
    var onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                copy
                    .padding(.horizontal, 28)
                    .padding(.top, 28)

                Spacer(minLength: 24)

                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
            // The band runs to the very top, under the status bar and the
            // toolbar, so the picture is the edge of the sheet rather than a
            // tile sitting on a white page.
            .ignoresSafeArea(edges: .top)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // The system's own close, on the left as asked. Ink rather
                    // than the system blue: leaving is not one of the app's
                    // actions, and blue here pulls the eye to the way out
                    // before the sheet has said anything.
                    Button(role: .close) { dismiss() }
                        .tint(Color(.mainText))
                }
            }
            // No bar material over the picture — the toolbar is only here to
            // hold the close button.
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        }
        // Literally white, in both appearances, and the sheet's contents are
        // pinned to the light palette to match — `mainText` inverts, and ink
        // that turns pale on a white page in the dark is unreadable.
        .presentationBackground(.white)
        .environment(\.colorScheme, .light)
    }

    // MARK: - Picture

    /// Empty, and waiting for the artwork that goes here. Everything below is
    /// laid out around a band of this height, so dropping an `Image` in — with
    /// `.resizable().scaledToFill()` — is the whole change.
    private var header: some View {
        Color(.royalBlue25)
            .frame(height: 300)
            .clipped()
    }

    // MARK: - Words

    private var copy: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The payoff, not the feature. "Your prices, ready to quote"
            // described the rate card; this says what happens because of it,
            // which is the only reason anyone would fill one in.
            Text("Say the job.\nIt's already priced.")
                .font(.robotoSlab(34, relativeTo: .largeTitle))
                // Slab at this size sets its lines too far apart for a
                // two-line headline — they stop reading as one sentence.
                .lineSpacing(-2)
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                point("tag", "Save the prices you charge, once, and stop working them out on the doorstep.")
                point("waveform", "Speak a job and every rate you've saved is found and totalled for you.")
                point("pencil", "Put your prices up and every quote after it follows, on its own.")
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Left-aligned rows, no dividers. The list is three short sentences about
    /// one thing, and ruling between them makes it read as a settings screen.
    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Outline weight, not filled. At this size a filled glyph is a
            // blot beside the sentence. Medium, to carry the same weight as
            // the text beside it — a hairline icon next to medium type reads
            // as a mistake rather than a lighter touch.
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color(.mainText))
                .frame(width: 26)
                // Nudged onto the first line's baseline rather than its top.
                .padding(.top, 2)
            Text(text)
                .font(.body.weight(.medium))
                // Two- and three-line points need air inside them, or the gap
                // between rows and the gap between lines look the same and the
                // three sentences run together.
                .lineSpacing(3)
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
    }

    // MARK: - Action

    /// Onboarding's Get Started, in ink: this is the decision the sheet exists
    /// to ask for. No second button — the only thing behind Continue is the
    /// rate card, and the close above already covers backing out.
    private var footer: some View {
        Button {
            onContinue()
            dismiss()
        } label: {
            Text("Continue")
                .font(.headline)
                .foregroundStyle(Color(.surface))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Color(.mainText), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    Color(.homeBackground)
        .sheet(isPresented: .constant(true)) {
            RateCardIntroSheet {}
        }
}
