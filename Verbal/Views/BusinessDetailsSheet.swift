//
//  BusinessDetailsSheet.swift
//  Verbal
//
//  Asked once, the first time a quote is shared with no business details saved.
//
//  Without them the PDF goes out headed "Quote" with no phone number, and the
//  acceptance line reads "To accept this quote, reply to this message" — a
//  document that looks like nobody sent it. The quote is the product; this is
//  the last moment before a customer sees it.
//
//  The fields are here rather than behind a link to the Profile tab: two inputs
//  is less work than a navigation trip, and anything longer gets skipped while
//  the user is mid-send.
//

import SwiftUI

/// Whether the share flow should stop to collect business details first.
enum BusinessPrompt {
    private static let askedKey = "hasPromptedBusinessDetails"

    /// True when nothing identifies the business yet and we haven't already
    /// asked. Asked once per install — a second nag would just be in the way.
    static func shouldAsk(_ profile: BusinessProfile?) -> Bool {
        guard !UserDefaults.standard.bool(forKey: askedKey) else { return false }
        let name = profile?.businessName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty
    }

    static func markAsked() {
        UserDefaults.standard.set(true, forKey: askedKey)
    }
}

struct BusinessDetailsSheet: View {
    /// Called after saving or skipping — the share continues either way.
    var onFinish: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var businessName = ""
    @State private var phone = ""
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool

    private var canSave: Bool {
        !businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "storefront")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(Color(.blueAccentText))
                    .frame(height: 46)

                Text("Put your name on it")
                    .font(.robotoSlab(24, relativeTo: .title2))
                    .foregroundStyle(Color(.mainText))
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)

                Text("These print at the top of every quote you send, and tell the client how to say yes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                VStack(spacing: 10) {
                    field("Business name", text: $businessName)
                        .focused($nameFocused)
                        .textInputAutocapitalization(.words)
                    field("Phone", text: $phone)
                        .keyboardType(.phonePad)
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button {
                    save()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Save and continue").font(.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(canSave ? Color(.royalBlue600) : Color(.royalBlue600).opacity(0.4),
                                in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSave || isSaving)

                Button("Not now") { finish() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .disabled(isSaving)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(.surface))
        }
        .presentationDetents([.height(520)])
        .presentationCornerRadius(28)
        .presentationBackground(Color(.surface))
        .task {
            // Prefill anything already saved, so this is never a retype.
            businessName = session.businessProfile?.businessName ?? ""
            phone = session.businessProfile?.phone ?? ""
            try? await Task.sleep(for: .seconds(0.35))
            nameFocused = true
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(Color(.mainText))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.cardSurface), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
    }

    private func save() {
        isSaving = true
        Task {
            // Start from the saved row so this never wipes a field it doesn't show.
            var profile = session.businessProfile ?? .empty
            profile.businessName = trimmedOrNil(businessName)
            profile.phone = trimmedOrNil(phone)
            try? await BusinessService.save(profile)
            session.cacheBusinessProfile(profile)
            isSaving = false
            finish()
        }
    }

    /// Skipping counts as asked. Someone who declined once shouldn't meet this
    /// again every time they send a quote.
    private func finish() {
        BusinessPrompt.markAsked()
        onFinish()
        dismiss()
    }

    private func trimmedOrNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
