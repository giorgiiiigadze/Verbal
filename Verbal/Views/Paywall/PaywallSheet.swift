//
//  PaywallSheet.swift
//  Verbal
//
//  The one screen that asks for money.
//
//  Its tone is set by a fact about the free tier: two quotes a day is
//  permanent, not a trial. Someone who never pays keeps getting two tomorrow,
//  and the day after. So this is a wall that will be hit again and again and
//  will always come down at midnight — "your trial has ended" would be a lie,
//  and the panic it borrows would be spent on a user who is not, in fact,
//  locked out of anything.
//
//  Built on `MicPermissionSheet`'s shape rather than `AnnouncementSheet`,
//  despite that component having been written with this screen in mind. Three
//  things it can't do: it dismisses the moment its button is tapped, where a
//  purchase has to keep the sheet up until StoreKit answers; and it has no
//  in-flight state to show while a purchase runs.
//

import StoreKit
import SwiftUI

struct PaywallSheet: View {
    /// How many quotes they have left today, if the count is known. Only used
    /// for the line at the top — nil simply says less, rather than guessing.
    let remaining: Int?

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    @State private var selection: Plan = .yearly
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var toast: Toast?

    private enum Plan { case monthly, yearly }

    var body: some View {
        // The copy grows with Dynamic Type but the detent doesn't, so the case
        // scrolls and the buttons stay put — the same trade `MicPermissionSheet`
        // makes, and for the same reason.
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) { actions }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: restorePurchases) {
                            Text("Restore Purchases")
                        }
                        .disabled(isPurchasing || isRestoring)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Subscription options")
                }
            }
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.large])
        // No `presentationCornerRadius`: the system's own radius is the one
        // every other sheet on the phone has, and it follows the device's own
            // corners. 28 was a guess, and a squarer one than the real thing.
        .presentationBackground(Color(.systemBackground))
        .toast($toast)
        .task { await store.loadProducts() }
    }

    // MARK: - The case

    private var content: some View {
        VStack(spacing: 0) {
            proMark

            Text(headline)
                .font(.robotoSlab(26, relativeTo: .title2))
                .foregroundStyle(Color(.mainText))
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            Text("Keep quoting without waiting for tomorrow's free allowance.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 8)

            plans
                .padding(.top, 24)

            VStack(alignment: .leading, spacing: 17) {
                checkmark("Create unlimited AI-powered quotes")
                checkmark("Keep quoting after your two free quotes")
                checkmark("Send a professional PDF for every job")
                checkmark("Use your saved rates on every quote")
                checkmark("Keep every client and job in one place")
                checkmark("Plan visits and stay on top of reminders")
                checkmark("Your existing quotes always stay yours")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .background(benefitsBackground,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity)
    }

    /// A compact brand accent, intentionally not a competing hero illustration.
    private var proMark: some View {
        ZStack {
            Circle()
                .fill(Color(.royalBlue50))
                .frame(width: 68, height: 68)
            Image(systemName: "waveform")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(accent)
        }
        .accessibilityHidden(true)
    }

    private var headline: String {
        guard let remaining, remaining <= 0 else { return "Quote without the daily cap" }
        return "That's your two quotes for today"
    }

    private func checkmark(_ title: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(.mainText))
                .frame(width: 18)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.mainText))
            Spacer(minLength: 0)
        }
    }

    // MARK: - Plans

    @ViewBuilder
    private var plans: some View {
        if store.products.isEmpty {
            #if DEBUG
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    fallbackPlanRow(.monthly, price: "$19.00", caption: "per month")
                    fallbackPlanRow(.yearly, price: "$190.00", caption: "per year", badge: "Best value")
                }

                if !store.isLoadingProducts {
                    Button("Try StoreKit again") { Task { await store.reloadProducts() } }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(accent)
                        .padding(.top, 4)
                }

                if let reason = store.loadError, !store.isLoadingProducts {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            #else
            // Products come from the App Store, so this can genuinely fail —
            // offline, or a configuration that isn't there yet. Saying so beats
            // an empty space where two prices should be.
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    if store.isLoadingProducts { ProgressView() }
                    Text(store.isLoadingProducts ? "Loading plans..." : "Plans are unavailable right now.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !store.isLoadingProducts {
                    Button("Try again") { Task { await store.reloadProducts() } }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(accent)
                }
                #if DEBUG
                // Debug only: this is a sentence for whoever is building the
                // app, not for whoever is buying it.
                if let reason = store.loadError, !store.isLoadingProducts {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                #endif
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            #endif
        } else {
            HStack(spacing: 10) {
                if let monthly = store.monthly {
                    planRow(.monthly, product: monthly, caption: "per month")
                }
                if let yearly = store.yearly {
                    planRow(.yearly, product: yearly, caption: "per year", badge: "Best value")
                }
            }
        }
    }

    private func planRow(_ plan: Plan, product: Product, caption: String, badge: String? = nil) -> some View {
        let isSelected = selection == plan
        return Button {
            selection = plan
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(product.displayPrice)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color(.mainText))
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(.royalBlue50), in: Capsule())
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 14)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? accent : Color(.separator),
                                  lineWidth: isSelected ? 2.5 : 1.5)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    #if DEBUG
    private func fallbackPlanRow(_ plan: Plan, price: String, caption: String, badge: String? = nil) -> some View {
        let isSelected = selection == plan
        return Button {
            selection = plan
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(price)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color(.mainText))
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(.royalBlue50), in: Capsule())
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 14)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? accent : Color(.separator),
                                  lineWidth: isSelected ? 2.5 : 1.5)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
    #endif

    /// Matches the light blue used by the Share button in `QuoteDetailView`.
    /// This is deliberately separate from the darker home-recording blue.
    private var accent: Color {
        Color(red: 48 / 255, green: 92 / 255, blue: 222 / 255)
    }

    private var benefitsBackground: Color {
        colorScheme == .dark
            ? Color(red: 42 / 255, green: 42 / 255, blue: 44 / 255)
            : Color(red: 248 / 255, green: 248 / 255, blue: 247 / 255)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: buy) {
                Group {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(ctaTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(accent.opacity(canBuy ? 1 : 0.4),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canBuy)

            HStack(spacing: 3) {
                Text(billingNote)
                if let terms = AppInfo.termsURL {
                    Button { openURL(terms) } label: {
                        Text("Terms apply").underline()
                    }
                }
                Text("and")
                Button { openURL(AppInfo.privacyPolicyURL) } label: {
                    Text("Privacy Policy").underline()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .disabled(isPurchasing)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // Opaque, so the case scrolling underneath doesn't bleed through.
        .background(Color(.systemBackground))
    }

    private var selectedProduct: Product? {
        selection == .monthly ? store.monthly : store.yearly
    }

    private var canBuy: Bool {
        guard !isPurchasing, !isRestoring else { return false }
        if selectedProduct != nil { return true }
        #if DEBUG
        return store.products.isEmpty
        #else
        return false
        #endif
    }

    /// The free week is on the monthly plan only, so the button says so only
    /// there. Promising a trial on a button that doesn't grant one is the kind
    /// of thing App Review rejects, and rightly.
    private var ctaTitle: String {
        if selection == .monthly,
           store.monthly?.subscription?.introductoryOffer != nil {
            return "Start 7 days free"
        }
        guard let price = selectedProduct?.displayPrice else { return "Go unlimited" }
        return "Subscribe for \(price) / \(selection == .yearly ? "year" : "month")"
    }

    private var billingNote: String {
        let price = selectedProduct?.displayPrice ?? "Subscription"
        return "\(price) billed \(selection == .yearly ? "yearly" : "monthly")."
    }

    private func buy() {
        guard let product = selectedProduct else {
            #if DEBUG
            if store.products.isEmpty {
                store.unlockForDebug()
                dismiss()
            }
            #endif
            return
        }
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            do {
                // Only on success: a cancelled purchase should leave the sheet
                // exactly where it was, not close as if something happened.
                if try await store.purchase(product) { dismiss() }
            } catch let error as StoreError {
                toast = Toast(style: .error, message: error.localizedDescription)
            } catch {
                toast = Toast(style: .error, message: "Couldn't complete the purchase")
            }
        }
    }

    private func restorePurchases() {
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                switch SubscriptionFlow.restoreOutcome(isPro: try await store.restore()) {
                case .restored:
                    dismiss()
                case .noActiveSubscription:
                    toast = Toast(style: .error, message: "No active purchases were found")
                }
            } catch {
                toast = Toast(style: .error, message: "Couldn't restore purchases")
            }
        }
    }

}
