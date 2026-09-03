//
//  MicPermissionSheet.swift
//  Verbal
//
//  Asks for the microphone before iOS does. The system dialog appears exactly
//  once per install and gives no room to explain itself — a cold "Verbal would
//  like to access the microphone" on a recording app reads as surveillance, and
//  a denial is effectively permanent. This makes the case first: the audio is
//  transcribed on the phone and never leaves it.
//
//  Also covers the other half of that one-shot: once denied, iOS will not ask
//  again, so the sheet switches to pointing at Settings rather than tapping a
//  button that can no longer do anything.
//

import SwiftUI
import UIKit

struct MicPermissionSheet: View {
    /// True when permission was already refused. iOS won't prompt a second
    /// time, so the only route back is Settings.
    let isBlocked: Bool
    /// Called when the user agrees to be asked, just before this sheet closes.
    /// Not called in the blocked case — there the sheet opens Settings itself.
    var onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        // The copy grows with Dynamic Type but the detent doesn't, so the
        // explanation scrolls and the buttons stay put. Fixed height alone
        // clips the icon clean off the top at the larger accessibility sizes.
        ScrollView {
            content
                .padding(.horizontal, 24)
                .padding(.top, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { actions }
        .presentationDetents([.height(500)])
        // No `presentationCornerRadius`: the system's own radius is the one
        // every other sheet on the phone has, and it follows the device's own
        // corners. 28 was a guess, and a squarer one than the real thing.
        .presentationBackground(Color(.surface))
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Keep the permission sheet in the same illustration family as
            // the recording introduction, rather than switching to an SF
            // Symbol just before the user begins recording.
            Image(.recordingIntro)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(.royalBlue600))
                .frame(width: 52, height: 52)

            Text(isBlocked ? "Microphone is off" : "Let Verbal hear the job")
                .font(.robotoSlab(24, relativeTo: .title2))
                .foregroundStyle(Color(.mainText))
                .multilineTextAlignment(.center)
                .padding(.top, 18)

            Text(isBlocked
                 ? "Verbal needs the microphone to turn a spoken job into a quote. You can switch it back on in Settings."
                 : "Describe the work out loud and Verbal writes it up as a priced, itemized quote.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 16) {
                benefit(icon: "iphone.gen3",
                        title: "Transcribed on your phone",
                        detail: "Your voice becomes text on-device. The audio never leaves it.")
                benefit(icon: "text.quote",
                        title: "Only the words are kept",
                        detail: "The transcript is saved with the quote so you can redo it. The recording isn't.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 26)
        }
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        VStack(spacing: 6) {
            Button(action: primaryAction) {
                Text(isBlocked ? "Open Settings" : "Turn on microphone")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(.royalBlue600), in: Capsule())
            }
            .buttonStyle(.plain)

            Button("Not now") { dismiss() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // Opaque, so text scrolling underneath doesn't bleed through.
        .background(Color(.surface))
    }

    /// One reason to say yes: what it is, then why it's safe.
    private func benefit(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(Color(.royalBlue600))
                .frame(width: 26, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.mainText))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func primaryAction() {
        if isBlocked {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
            dismiss()
        } else {
            // Hand back before closing; the caller starts recording once the
            // sheet is gone, so the system dialog isn't presented mid-dismissal.
            onContinue()
            dismiss()
        }
    }
}
