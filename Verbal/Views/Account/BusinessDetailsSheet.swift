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
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Image(systemName: "storefront")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Color(.blueAccentText))
                        .frame(height: 42)

                    Text("These print at the top of every quote you send, and tell the client how to say yes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)

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
                .padding(.top, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemBackground))
            .navigationTitle("Business details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { finish() }
                        .disabled(isSaving)
                }
            }
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
                        .frame(height: 52)
                        .background(canSave ? Color(.royalBlue600) : Color(.royalBlue600).opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .background(Color(.systemBackground))
            }
        }
        .presentationDetents([.height(520)])
        .presentationBackground(Color(.systemBackground))
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
