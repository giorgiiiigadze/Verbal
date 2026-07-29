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
    let title: String
    let subtitle: String
    let shareText: String
    /// Called when the quote is actually shared or copied (used to mark it Sent).
    var onShared: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showSystemShare = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Share quote")
                    .font(.robotoSlab(22, relativeTo: .title2))
                    .foregroundStyle(Color(.mainText))
                Spacer()
                Button(role: .close) { dismiss() }
            }

            // Quote preview.
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.royalBlue100))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: "doc.text")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color(.royalBlue600))
                    )
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
                actionButton(title: "Share via…", systemImage: "square.and.arrow.up") {
                    showSystemShare = true
                }
                actionButton(title: copied ? "Copied" : "Copy",
                             systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = shareText
                    withAnimation { copied = true }
                    onShared()
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.ultraThinMaterial)
        .sheet(isPresented: $showSystemShare) {
            ShareSheet(items: [shareText]) { completed in
                if completed {
                    onShared()
                    dismiss()
                }
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
    @ViewBuilder let leading: Leading

    var body: some View {
        HStack(spacing: 8) {
            leading
                .font(.body)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.mainText))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.surface), in: .capsule)
    }
}
