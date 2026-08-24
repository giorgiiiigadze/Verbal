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
//  purchase has to keep the sheet up until StoreKit answers; it has room for
//  one action, where this needs Restore and the two legal links App Review
//  insists on; and it has no in-flight state to show while a purchase runs.
//

import StoreKit
import SwiftUI

struct PaywallSheet: View {
    /// How many quotes they have left today, if the count is known. Only used
    /// for the line at the top — nil simply says less, rather than guessing.
    let remaining: Int?

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var selection: Plan = .monthly
    @State private var isPurchasing = false
    @State private var toast: Toast?

    private enum Plan { case monthly, yearly }

    var body: some View {
        // The copy grows with Dynamic Type but the detent doesn't, so the case
        // scrolls and the buttons stay put — the same trade `MicPermissionSheet`
        // makes, and for the same reason.
        ScrollView {
            content
                .padding(.horizontal, 24)
                .padding(.top, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { actions }
        .presentationDetents([.height(560)])
        .presentationCornerRadius(28)
        .presentationBackground(Color(.surface))
        .toast($toast)
        .task { await store.loadProducts() }
    }

    // MARK: - The case

    private var content: some View {
        VStack(spacing: 0) {
            Image(systemName: "infinity")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Color(.blueAccentText))
                .frame(height: 46)

            Text(headline)
                .font(.robotoSlab(24, relativeTo: .title2))
                .foregroundStyle(Color(.mainText))
                .multilineTextAlignment(.center)
                .padding(.top, 18)

            Text("Back tomorrow for two more, or go unlimited and stop counting.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 16) {
                benefit(icon: "infinity",
                        title: "Unlimited quotes",
                        detail: "Quote every job you win, not just the first two of the day.")
                benefit(icon: "bolt.fill",
                        title: "Nothing else changes",
                        detail: "Same app, same quotes. The daily cap is simply gone.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 26)

            plans
                .padding(.top, 24)
        }
        .frame(maxWidth: .infinity)
    }

    private var headline: String {
        guard let remaining, remaining <= 0 else { return "Quote without the daily cap" }
        return "That's your two quotes for today"
    }

    private func benefit(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(Color(.blueAccentText))
                .frame(width: 26, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.mainText))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Plans

    @ViewBuilder
    private var plans: some View {
        if store.products.isEmpty {
            #if DEBUG
            VStack(spacing: 10) {
                fallbackPlanRow(.monthly, price: "$19.00", caption: "per month")
                fallbackPlanRow(.yearly, price: "$190.00", caption: "per year · two months free")

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
            VStack(spacing: 10) {
                if let monthly = store.monthly {
                    planRow(.monthly, product: monthly, caption: "per month")
                }
                if let yearly = store.yearly {
                    planRow(.yearly, product: yearly, caption: "per year · two months free")
                }
            }
        }
    }

    private func planRow(_ plan: Plan, product: Product, caption: String) -> some View {
        let isSelected = selection == plan
        return Button {
            selection = plan
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? accent : Color(.separator))
                VStack(alignment: .leading, spacing: 2) {
                    // Straight from StoreKit, so it is the price in the user's
                    // own currency as the App Store sells it — never $19
                    // converted by us into something the sheet can't charge.
                    Text(product.displayPrice)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color(.mainText))
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.fieldFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? accent : Color(.separator),
                                  lineWidth: isSelected ? 1.5 : 0.5)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    #if DEBUG
    private func fallbackPlanRow(_ plan: Plan, price: String, caption: String) -> some View {
        let isSelected = selection == plan
        return Button {
            selection = plan
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? accent : Color(.separator))
                VStack(alignment: .leading, spacing: 2) {
                    Text(price)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color(.mainText))
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.fieldFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? accent : Color(.separator),
                                  lineWidth: isSelected ? 1.5 : 0.5)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
    #endif

    /// `royalBlue600` carries a light appearance only, so in dark mode it stays
    /// a near-black navy that vanishes into the surface behind it. The house
    /// swap, as used by `ReadyToAddSheet` and four others.
    private var accent: Color {
        colorScheme == .dark ? .white : Color(.royalBlue600)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 6) {
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
                .frame(height: 54)
                .background(Color(.royalBlue600).opacity(canBuy ? 1 : 0.4),
                            in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canBuy)

            HStack(spacing: 18) {
                Button("Restore") { Task { await restore() } }
                if let terms = AppInfo.termsURL {
                    Button("Terms") { openURL(terms) }
                }
                Button("Privacy") { openURL(AppInfo.privacyPolicyURL) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .disabled(isPurchasing)

            Button("Not now") { dismiss() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .disabled(isPurchasing)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // Opaque, so the case scrolling underneath doesn't bleed through.
        .background(Color(.surface))
    }

    private var selectedProduct: Product? {
        selection == .monthly ? store.monthly : store.yearly
    }

    private var canBuy: Bool {
        guard !isPurchasing else { return false }
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
        guard selection == .monthly,
              store.monthly?.subscription?.introductoryOffer != nil
        else { return "Go unlimited" }
        return "Start 7 days free"
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
            } catch {
                toast = Toast(style: .error, message: "Couldn't complete the purchase")
            }
        }
    }

    private func restore() async {
        isPurchasing = true
        await store.restore()
        isPurchasing = false
        if store.isPro {
            dismiss()
        } else {
            toast = Toast(style: .error, message: "Nothing to restore on this Apple ID")
        }
    }
}
