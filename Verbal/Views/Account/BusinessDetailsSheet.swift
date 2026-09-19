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
//  The fields are here rather than behind a link to the Profile tab: a few inputs
//  is less work than a navigation trip, and anything longer gets skipped while
//  the user is mid-send.
//

import SwiftUI

struct BusinessDetailsSheet: View {
    /// Called after saving or skipping — the share continues either way.
    var onFinish: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var showsForm = false
    @State private var businessName = ""
    @State private var phone = ""
    @State private var isTaxRegistered = false
    @State private var taxRate = ""
    @State private var isSaving = false
    @State private var saveFailed = false

    private enum Field: Hashable {
        case businessName, phone, taxRate
    }
    @FocusState private var focus: Field?

    private var canSave: Bool {
        !businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            introduction
                .navigationDestination(isPresented: $showsForm) {
                    detailsForm
                }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(.homeBackground))
        .alert("Couldn't save business details", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again, or tap Not now to continue without saving.")
        }
        .task {
            // Prefill anything already saved, so this is never a retype.
            businessName = session.businessProfile?.businessName ?? ""
            phone = session.businessProfile?.phone ?? ""
            let savedTaxRate = session.businessProfile?.defaultTaxRate ?? 0
            isTaxRegistered = savedTaxRate > 0
            taxRate = savedTaxRate > 0
                ? savedTaxRate.formatted(.number.precision(.fractionLength(0...2)))
                : ""
        }
    }

    private var introduction: some View {
        VStack(spacing: 0) {
            Image(systemName: "storefront")
                .font(.system(size: 74, weight: .medium))
                .foregroundStyle(Color(.mainText))
                .frame(width: 150, height: 150)
                .padding(.top, 70)

            Text("Put your business\non every quote.")
                .font(.scaledSystem(38, relativeTo: .largeTitle, weight: .medium, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(.mainText))
                .padding(.top, 30)

            VStack(alignment: .center, spacing: 24) {
                benefit("building.2", "Show clients who the quote is from")
                benefit("phone", "Make it easy for them to get in touch")
                benefit("doc.text", "Print your details on every quote")
            }
            .padding(.top, 42)
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 24)

            Button {
                showsForm = true
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(colorScheme == .dark ? Color(.homeBackground) : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(.mainText), in: Capsule())
            }
            .buttonStyle(.plain)

            Button("Not now") { finish() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .background(Color(.homeBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .close) { finish() }
            }
        }
    }

    private var detailsForm: some View {
        ZStack {
            Color(.accountBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your business information")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(.mainText))

                        Text("These details appear at the top of every quote you send.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        field(
                            "Business name",
                            placeholder: "Your business name",
                            text: $businessName,
                            focus: .businessName,
                            isRequired: true
                        )
                        .textInputAutocapitalization(.words)

                        field(
                            "Phone",
                            placeholder: "Phone number",
                            text: $phone,
                            focus: .phone
                        )
                        .keyboardType(.phonePad)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Tax")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(.mainText))

                        Toggle("I'm tax registered", isOn: $isTaxRegistered)
                            .font(.body)
                            .foregroundStyle(Color(.mainText))
                            .tint(Color(.royalBlue600))
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color(.cardSurface))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(.separator), lineWidth: 1)
                            }

                        if isTaxRegistered {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Tax rate")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(focus == .taxRate ? Color(.blueAccentText) : .secondary)

                                HStack(spacing: 8) {
                                    TextField("20", text: $taxRate)
                                        .keyboardType(.decimalPad)
                                        .focused($focus, equals: .taxRate)
                                    Spacer()
                                    Text("%")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.body.monospacedDigit())
                                .foregroundStyle(Color(.mainText))
                                .tint(Color(.blueAccentText))
                                .padding(.horizontal, 16)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color(.cardSurface))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            focus == .taxRate ? Color(.blueAccentText) : Color(.separator),
                                            lineWidth: 1
                                        )
                                }
                            }
                        }

                        Text("Tax is added to the quote total and shown as a separate line.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Business details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button {
                    focus = nil
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Hide keyboard")
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
            .background(Color(.accountBackground))
        }
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(0.35))
                focus = .businessName
            }
        }
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.body.weight(.medium))
            .foregroundStyle(Color(.mainText))
            .labelStyle(.titleAndIcon)
    }

    private func field(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        focus field: Field,
        isRequired: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label + (isRequired ? " *" : ""))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(focus == field ? Color(.blueAccentText) : .secondary)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(Color(.mainText))
                .tint(Color(.blueAccentText))
                .focused($focus, equals: field)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(Color(.cardSurface))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            focus == field ? Color(.blueAccentText) : Color(.separator),
                            lineWidth: 1
                        )
                }
        }
    }

    private func save() {
        focus = nil
        isSaving = true
        Task {
            defer {
                isSaving = false
            }

            // Start from the saved row so this never wipes a field it doesn't show.
            var profile = session.businessProfile ?? .empty
            profile.businessName = businessName.trimmedOrNil
            profile.phone = phone.trimmedOrNil
            profile.defaultTaxRate = isTaxRegistered
                ? max(0, OnboardingModel.number(from: taxRate) ?? 0)
                : 0

            do {
                try await BusinessService.save(profile)
            } catch {
                saveFailed = true
                return
            }

            session.cacheBusinessProfile(profile)
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
}
