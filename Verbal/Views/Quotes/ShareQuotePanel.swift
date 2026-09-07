//
//  ShareQuotePanel.swift
//  Verbal
//
//  Verbal's custom share panel for a quote — a preview plus Share / Copy actions —
//  and the UIActivityViewController wrapper it presents.
//

import SwiftUI
import UIKit
import MessageUI

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
    /// A direct Messages option belongs here only when the quote has a client
    /// number and this device can send Messages.
    var messageRecipient: String?
    var messageBody: String?
    /// Called when the quote is actually shared or copied (used to mark it Sent).
    var onShared: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(NetworkMonitor.self) private var network
    @Environment(SessionStore.self) private var session
    @State private var showSystemShare = false
    @State private var copied = false
    @State private var toast: Toast?
    @State private var preview: UIImage?
    @State private var pdfURL: URL?
    @State private var isPreviewing = false
    @State private var failedToRender = false
    @State private var messageDraft: MessageDraft?

    /// A new identity on every tap prevents SwiftUI from trying to reuse a
    /// Messages controller that the system previously declined to initialize.
    private struct MessageDraft: Identifiable {
        let id = UUID()
    }

    private var hasPDF: Bool { document != nil && !failedToRender }
    private var canMessageClient: Bool {
        messageRecipient != nil && MFMessageComposeViewController.canSendText()
    }
    private var messageIsAvailable: Bool { canMessageClient && pdfURL != nil }

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
            VStack(alignment: .leading, spacing: 22) {
                // Quote preview — the real first page when we have one, so the user
                // sees exactly what the client will get before it goes out.
                HStack(spacing: 14) {
                    previewArtwork
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

                Divider()

                // Each route is present at once — the decision is how to hand
                // over this particular quote, not whether it can be sent.
                HStack(alignment: .top, spacing: 0) {
                    shareAction(title: "Message", icon: .messageSketch,
                                isDisabled: !messageIsAvailable) {
                        messageDraft = MessageDraft()
                    }
                    shareAction(title: hasPDF ? "Share via" : "Share via…",
                                icon: .shareSketch) {
                        // A rendered PDF is local. It can be shared through
                        // Messages, Mail or AirDrop without a connection; only
                        // creating a web link needs the server.
                        if !hasPDF, !requireInternetForSharing() { return }
                        showSystemShare = true
                    }
                    shareAction(title: linkTitle, systemImage: copied ? "checkmark" : "link",
                                isDisabled: isLinking) {
                        copyLink()
                    }
                    shareAction(title: "View PDF", systemImage: "doc.text") {
                        if pdfURL != nil { isPreviewing = true }
                    }
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
        .presentationDetents([.height(360)])
        .presentationBackground(.ultraThinMaterial)
        .toast($toast)
        .task {
            guard let renderedDocument = document else { return }
            guard !Task.isCancelled else { return }

            preview = QuotePDF.thumbnail(renderedDocument)
            do {
                pdfURL = try QuotePDF.write(renderedDocument)
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
        .sheet(item: $messageDraft) { _ in
            if let recipient = messageRecipient, let pdfURL, let document {
                MessageComposer(recipients: [recipient],
                                body: messageBody ?? "Here's your quote.",
                                attachmentURL: pdfURL,
                                attachmentFilename: document.fileName) { sent in
                    messageDraft = nil
                    guard sent else { return }
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

    @ViewBuilder
    private var previewArtwork: some View {
        if let preview {
            Image(uiImage: preview)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.royalBlue25))
                .overlay {
                    Image(systemName: "doc.text")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(.blueAccentText))
                }
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

    private func shareAction(title: String,
                             systemImage: String? = nil,
                             icon: ImageResource? = nil,
                             isDisabled: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Group {
                    if let icon {
                        Image(icon)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                    } else if let systemImage {
                        Image(systemName: systemImage)
                            .font(.title3.weight(.medium))
                    }
                }
                    .frame(width: 74, height: 74)
                    .glassEffect(.regular.interactive(), in: Circle())
                Text(title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(Color(.mainText))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.38 : 1)
        .accessibilityLabel(title)
        .accessibilityHint(shareActionHint(for: title))
    }

    private func shareActionHint(for title: String) -> String {
        switch title {
        case "Message": return "Opens Messages with this quote PDF attached."
        case "Copy link", "Link copied", "Getting link…", "Try again":
            return "Creates a secure link to this quote."
        case "View PDF": return "Opens the PDF preview."
        default: return "Opens the system share sheet."
        }
    }

    private func cleanUpPDF() {
        guard let pdfURL else { return }
        try? FileManager.default.removeItem(at: pdfURL)
        self.pdfURL = nil
    }
}
