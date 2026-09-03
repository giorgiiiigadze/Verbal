//
//  CalendarIntroSheet.swift
//  Verbal
//

import SwiftUI

/// A one-time introduction shown only after someone chooses the empty
/// Calendar tab. It explains the complete visit-to-quote loop, then hands the
/// primary action straight to the existing visit editor.
struct CalendarIntroSheet: View {
    var onBookVisit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // The same visual rhythm as the recording and rate-card
                // intros, using Calendar's existing asset rather than an SF
                // Symbol that belongs to a different illustration family.
                Image("VisitsEmpty")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .foregroundStyle(Color(.mainText))
                    .padding(.top, 70)

                Text("Plan the work.\nQuote it while it’s fresh.")
                    .font(.system(size: 38, design: .serif).weight(.medium))
                    .foregroundStyle(Color(.mainText))
                    .multilineTextAlignment(.center)
                    .padding(.top, 30)

                VStack(alignment: .center, spacing: 24) {
                    benefit(asset: "VisitClock", text: "Keep every visit in one place")
                    benefit("bell", "Get a reminder when it’s time to go")
                    benefit(asset: "RecordingIntro", text: "Turn the visit into a quote")
                }
                .padding(.top, 42)
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 24)

                Button(action: onBookVisit) {
                    Text("Book a visit")
                        .font(.headline)
                        .foregroundStyle(colorScheme == .dark ? Color(.homeBackground) : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color(.mainText), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
            .background(Color(.homeBackground))
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
    CalendarIntroSheet {}
}
