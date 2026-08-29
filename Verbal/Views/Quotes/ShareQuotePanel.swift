//
//  ShareQuotePanel.swift
//  Verbal
//
//  Verbal's custom share panel for a quote — a preview plus Share / Copy actions —
//  and the UIActivityViewController wrapper it presents.
//

import SwiftUI
import UIKit

/// Verbal's custom share panel for a quote — a preview plus Share / Copy actions.
struct ShareQuotePanel: View {
    /// The quote a link would point at. Minting is deferred until the user asks
    /// for one, so a quote that is never shared never gets an address.
    let quoteId: UUID
    let title: String
    let subtitle: String
    let shareText: String
    /// The quote as a printable document. When present the panel previews the
    /// real page and sends the PDF; without it, it falls back to sharing text.
    var document: QuoteDocument?
    /// Called when the quote is actually shared or copied (used to mark it Sent).
    var onShared: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(NetworkMonitor.self) private var network
    @State private var showSystemShare = false
    @State private var copied = false
    @State private var toast: Toast?
    @State private var preview: UIImage?
    @State private var pdfURL: URL?
    @State private var isPreviewing = false
    @State private var failedToRender = false

    private var hasPDF: Bool { document != nil && !failedToRender }

    @State private var isLinking = false
    @State private var linkFailed = false

    private var linkTitle: String {
        if isLinking { return "Getting link…" }
        if linkFailed { return "Try again" }
        return copied ? "Link copied" : "Copy link"
    }

    /// Mints the link if this quote has never had one, then puts it on the
    /// pasteboard. Counted as a share: a link handed over is a quote sent, the
    /// same as attaching the PDF.
    private func copyLink() {
        guard requireInternetForSharing() else { return }
        guard !isLinking else { return }

        isLinking = true
        linkFailed = false
        Task {
            defer { isLinking = false }
            do {
                let url = try await QuoteService.shareLink(quoteId: quoteId)
                UIPasteboard.general.string = url.absoluteString
                withAnimation { copied = true }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onShared()
            } catch {
                // Minting needs the server. Say so on the button rather than
                // leaving a tap that quietly did nothing.
                withAnimation { linkFailed = true }
                toast = Toast(style: .error, message: "Couldn't create a share link. Try again.")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Quote preview — the real first page when we have one, so the user
                // sees exactly what the client will get before it goes out.
                HStack(spacing: 14) {
                    Group {
                        if let preview {
                            Image(uiImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.royalBlue25))
                                .overlay(
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(Color(.blueAccentText))
                                )
                        }
                    }
                    .frame(width: 46, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    )
                    .onTapGesture { if pdfURL != nil { isPreviewing = true } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Quote PDF preview")
                    .accessibilityHint(pdfURL == nil
                        ? "A preview is being prepared."
                        : "Double-tap to open the full quote preview.")
                    .accessibilityAddTraits(pdfURL == nil ? [] : .isButton)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Color(.mainText))
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                // Actions.
                HStack(spacing: 12) {
                    actionButton(title: hasPDF ? "Send quote" : "Share via…",
                                 systemImage: "square.and.arrow.up") {
                        // A rendered PDF is local. It can be shared through
                        // Messages, Mail or AirDrop without a connection; only
                        // creating a web link needs the server.
                        if !hasPDF, !requireInternetForSharing() { return }
                        showSystemShare = true
                    }
                    // A link rather than the quote's text, which this used to copy.
                    // The text was a snapshot that went stale the moment anything
                    // changed and gave the customer nothing to do; the link is
                    // always current, tells you when they've opened it, and lets
                    // them answer.
                    actionButton(title: linkTitle,
                                 systemImage: copied ? "checkmark" : "link") {
                        copyLink()
                    }
                    .disabled(isLinking)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .navigationTitle("Share quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.height(300)])
        .presentationBackground(.ultraThinMaterial)
        .toast($toast)
        .task {
            guard let document else { return }
            preview = QuotePDF.thumbnail(document)
            do {
                pdfURL = try QuotePDF.write(document)
            } catch {
                // Fall back to sharing text rather than blocking the send.
                failedToRender = true
            }
        }
        .sheet(isPresented: $showSystemShare) {
            ShareSheet(items: [pdfURL as Any? ?? shareText].compactMap { $0 }) { completed in
                if completed {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onShared()
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $isPreviewing) {
            if let pdfURL {
                QuickLookPreview(url: pdfURL)
                    .ignoresSafeArea()
            }
        }
        .onDisappear {
            cleanUpPDF()
        }
    }

    private func requireInternetForSharing() -> Bool {
        guard network.isOnline else {
            toast = Toast(style: .error, message: "Internet required for sharing")
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return false
        }
        return true
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title).fontWeight(.medium)
            }
            .foregroundStyle(Color(.mainText))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(systemImage == "link"
            ? "Creates a secure web link for this quote."
            : "Opens the system share sheet.")
    }

    private func cleanUpPDF() {
        guard let pdfURL else { return }
        try? FileManager.default.removeItem(at: pdfURL)
        self.pdfURL = nil
    }
}
