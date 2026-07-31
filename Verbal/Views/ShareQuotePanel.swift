//
//  ShareQuotePanel.swift
//  Verbal
//
//  Verbal's custom share panel for a quote — a preview plus Share / Copy actions —
//  and the UIActivityViewController wrapper it presents.
//

import SwiftUI
import UIKit
import QuickLook

/// Verbal's custom share panel for a quote — a preview plus Share / Copy actions.
struct ShareQuotePanel: View {
    let title: String
    let subtitle: String
    let shareText: String
    /// The quote as a printable document. When present the panel previews the
    /// real page and sends the PDF; without it, it falls back to sharing text.
    var document: QuoteDocument?
    /// Called when the quote is actually shared or copied (used to mark it Sent).
    var onShared: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showSystemShare = false
    @State private var copied = false
    @State private var preview: UIImage?
    @State private var pdfURL: URL?
    @State private var isPreviewing = false
    @State private var failedToRender = false

    private var hasPDF: Bool { document != nil && !failedToRender }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Share quote")
                    .font(.robotoSlab(22, relativeTo: .title2))
                    .foregroundStyle(Color(.mainText))
                Spacer()
                Button(role: .close) { dismiss() }
            }

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
                    showSystemShare = true
                }
                actionButton(title: copied ? "Copied" : "Copy text",
                             systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = shareText
                    withAnimation { copied = true }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onShared()
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.ultraThinMaterial)
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
    }
}

/// Full-screen PDF preview, so the user can read the document before sending.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

/// UIActivityViewController wrapper that reports whether the share completed,
/// so callers can react (e.g. marking a quote as Sent).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Small native rounded-rectangle chip with a leading icon/avatar and text.
struct QuoteChip<Leading: View>: View {
    let text: String
    /// Draws the chip in brand blue — used for an action still to be done,
    /// so it reads as inviting rather than as another piece of metadata.
    var tinted: Bool = false
    @ViewBuilder let leading: Leading

    var body: some View {
        HStack(spacing: 8) {
            leading
                .font(.body)
                .foregroundStyle(tinted ? Color(.blueAccentText) : .secondary)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tinted ? Color(.blueAccentText) : Color(.mainText))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tinted ? Color(.royalBlue25) : Color(.surface), in: .capsule)
    }
}
