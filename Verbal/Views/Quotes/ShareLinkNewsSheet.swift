//
//  ShareLinkNewsSheet.swift
//  Verbal
//
//  Says that a quote can now be sent as a link. Shown once, to people who were
//  already using the app when it arrived — a new user never knew the absence and
//  shouldn't be told about the cure.
//

import SwiftUI

struct ShareLinkNewsSheet: View {
    var body: some View {
        AnnouncementSheet(
            badge: "New",
            title: "Send a link,\nnot a PDF",
            points: [
                .init(icon: "eye.fill", text: "See the moment your customer opens it"),
                .init(icon: "checkmark.circle.fill", text: "They accept or decline in one tap"),
                .init(icon: "arrow.triangle.2.circlepath", text: "Always shows your latest prices"),
            ],
            actionTitle: "Got it",
            preview: { linkPreview }
        )
        // A plain fixed-height sheet. `.presentationSizing(.fitted)` was tried
        // here to spare the guesswork and made a mess of it on iPhone.
        .presentationDetents([.height(580)])
    }

    /// The link above, and beneath it the row it turns into on Home once the
    /// customer opens it.
    ///
    /// Drawn to `QuoteRow`'s geometry on purpose — title over subtitle on the
    /// left, total over the status pill on the right, with no card around it.
    /// Someone should recognise this as their own list before they
    /// have read a word of it, and that recognition is what makes "Viewed" mean
    /// something. Deliberately not a screenshot: one goes stale the first time
    /// anything on that row moves.
    private var linkPreview: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.footnote.weight(.semibold))
                Text("verbal.app/q/…")
                    .font(.footnote.monospaced())
                Spacer(minLength: 0)
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .foregroundStyle(Color(.blueAccentText))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(.royalBlue25),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Image(systemName: "arrow.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(.blueAccentText).opacity(0.5))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bathroom re-tiling")
                        .font(.headline)
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                    Text("Marina Kapanadze · 2 days ago")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(AppCurrency.format(1240))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color(.mainText))
                    // Exactly the real row's viewed treatment.
                    HStack(spacing: 4) {
                        Image(systemName: "eye.fill")
                            .font(.caption2)
                        Text("Viewed")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(.statusViewedText))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.statusViewedFill), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
        }
    }
}
