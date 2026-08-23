//
//  DeleteAccountSheet.swift
//  Verbal
//
//  Deleting an account is permanent, so it gets a considered screen rather
//  than a one-tap alert: pick a reason, optionally say more, then confirm.
//

import SwiftUI

struct DeleteAccountSheet: View {
    /// Called with the chosen reason once confirmed.
    var onConfirm: (_ reason: String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var reason: String?
    @State private var showFinalConfirmation = false

    private let reasons = [
        "I don't need it anymore",
        "The quotes weren't accurate",
        "Missing features I need",
        "Too hard to use",
        "It's too expensive",
        "I was just trying it out",
        "Something else"
    ]

    private var selectedIconColor: Color {
        colorScheme == .dark ? .white : Color(.blueAccentText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Before you go, what made you decide to leave? It helps us fix what isn't working.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        ForEach(reasons, id: \.self) { option in
                            reasonRow(option)
                        }
                    }

                }
                .padding(24)
            }
            .background(Color(.homeBackground))
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Text("This permanently deletes your account, quotes, and rate card. It can't be undone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        showFinalConfirmation = true
                    } label: {
                        Text("Delete my account")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(reason == nil ? Color.red.opacity(0.4) : Color.red,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(reason == nil)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) { dismiss() }
                }
            }
            .alert("Delete your account?", isPresented: $showFinalConfirmation) {
                Button("Delete", role: .destructive) {
                    if let reason { onConfirm(reason) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every quote, rate, and business detail will be removed. This can't be undone.")
            }
        }
    }

    private func reasonRow(_ option: String) -> some View {
        let selected = reason == option
        return Button {
            reason = option
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? selectedIconColor : Color(.separator))
                Text(option)
                    .font(.callout)
                    .foregroundStyle(Color(.mainText))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(selected ? Color(.royalBlue25) : Color(.cardSurface),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color(.blueAccentText).opacity(0.35) : Color(.separator),
                                  lineWidth: selected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}
