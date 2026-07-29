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
    /// When provided, the transcript is editable in place and an Edit button appears.
    var editable: Binding<String>?
    /// When provided, a Regenerate button appears that re-runs the AI on the transcript.
    var onRegenerate: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @FocusState private var editorFocused: Bool

    private var displayText: String { editable?.wrappedValue ?? text ?? "" }
    private var hasText: Bool { !displayText.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Transcript")
                            .font(.robotoSlab(34, relativeTo: .largeTitle))
                            .foregroundStyle(Color(.mainText))
                        Text("Review or share the full transcript.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if isEditing, let editable {
                        TextField("Transcript", text: editable, axis: .vertical)
                            .font(.callout)
                            .foregroundStyle(Color(.mainText))
                            .focused($editorFocused)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(hasText ? displayText : "No transcript saved.")
                            .font(.callout)
                            .foregroundStyle(hasText ? Color(.mainText) : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    actionBar
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
        }
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            Button {
                UIPasteboard.general.string = displayText
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
