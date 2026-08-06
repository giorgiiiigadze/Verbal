//
//  TranscriptSheet.swift
//  Verbal
//
//  Sheet showing the raw transcript a quote was generated from, optionally
//  editable in place with Share / Copy / Regenerate actions.
//

import SwiftUI
import UIKit

struct TranscriptSheet: View {
    let text: String?
    /// The server couldn't be reached and there's no copy on this phone. Only
    /// meaningful when there's nothing to show: "none exists" and "I can't get
    /// to it" look identical on screen otherwise, and telling someone their
    /// recording wasn't saved when it is, is the worse of the two to get wrong.
    var unreachable: Bool = false
    /// When provided, the transcript is editable in place and an Edit button appears.
    var editable: Binding<String>?
    /// When provided, a Regenerate button appears that re-runs the AI on the transcript.
    var onRegenerate: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var toast: Toast?
    @FocusState private var editorFocused: Bool

    private var displayText: String { editable?.wrappedValue ?? text ?? "" }
    private var hasText: Bool { !displayText.isEmpty }

    /// "Saved" is a claim about the server, and offline there's no way to make
    /// it. The recording is almost certainly there — saying it isn't reads as
    /// lost work.
    private var emptyMessage: String {
        unreachable
            ? "Can't reach this transcript. Check your connection and try again."
            : "No transcript saved."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Transcript")
                            .font(.robotoSlab(34, relativeTo: .largeTitle))
                            .foregroundStyle(Color(.mainText))
                        // Only when there is something to review or share.
                        // Above an empty screen it was describing actions that
                        // weren't available.
                        if hasText {
                            Text("Review or share the full transcript.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if isEditing, let editable {
                        TextField("Transcript", text: editable, axis: .vertical)
                            .font(.callout)
                            .foregroundStyle(Color(.mainText))
                            .focused($editorFocused)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(hasText ? displayText : emptyMessage)
                            .font(.callout)
                            .foregroundStyle(hasText ? Color(.mainText) : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Nothing to copy, share or regenerate from, so the row was
                    // three dead controls under a message saying as much.
                    if hasText { actionBar }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            .background(Color(.homeBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: displayText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(!hasText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toast($toast)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            Button {
                UIPasteboard.general.string = displayText
                toast = Toast(style: .success, message: "Transcript copied")
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .disabled(!hasText)

            if editable != nil {
                Button {
                    isEditing.toggle()
                    editorFocused = isEditing
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                }
            }

            if let onRegenerate {
                Button {
                    dismiss()
                    onRegenerate()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(!hasText)
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Color(.mainText))
        .padding(.top, 4)
    }
}
