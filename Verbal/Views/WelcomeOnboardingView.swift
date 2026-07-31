//
//  WelcomeOnboardingView.swift
//  Verbal
//
//  First-launch welcome shown once after the user first signs in — a single
//  bottom sheet with five horizontally-paged panels (Granola-style). The last
//  panel drops the user straight into the voice-recording screen.
//

import SwiftUI

struct WelcomeOnboardingView: View {
    /// Called from the final panel — dismiss the sheet and open the recorder.
    var onGetStarted: () -> Void

    @State private var page = 0

    private let panels: [Panel] = [
        Panel(symbol: "mic.fill",
              headline: "Just say the job",
              body: "Describe the work like you'd tell a mate. That's all Verbal needs.",
              button: "Continue"),
        Panel(symbol: "doc.text.fill",
              headline: "We do the paperwork",
              body: "Your words become a proper itemized quote in seconds. Labour, materials, the lot.",
              button: "Continue"),
        Panel(symbol: "list.bullet.rectangle.fill",
              headline: "Priced how you price",
              body: "Set your rates once and Verbal uses them on every quote.",
              button: "Continue"),
        Panel(symbol: "slider.horizontal.3",
              headline: "You have the final say",
              body: "Tweak any price, add or bin a line. Nothing sends until you're happy.",
              button: "Continue"),
        Panel(symbol: "paperplane.fill",
              headline: "Send it, win the job",
              body: "Fire off a professional quote before you've left the driveway.",
              button: "Get started"),
    ]

    private var isLastPage: Bool { page == panels.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(panels.indices, id: \.self) { index in
                    panelView(panels[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: page)

            dots
                .padding(.bottom, 20)

            Button {
                if isLastPage {
                    onGetStarted()
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        page += 1
                    }
                }
            } label: {
                Text(panels[page].button)
                    .font(.headline)
                    .foregroundStyle(Color(.surface))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(.mainText), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        // A light tick as each panel lands, and a firmer press on the final
        // "Get started" — the tactile tone is set in the first minute.
        .sensoryFeedback(trigger: page) { oldPage, newPage in
            guard newPage != oldPage else { return nil }
            return newPage == panels.count - 1 ? .impact(weight: .medium) : .selection
        }
        .presentationDetents([.height(520)])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.surface))
    }

    // MARK: - Panel

    private func panelView(_ panel: Panel) -> some View {
        VStack(spacing: 20) {
            illustration(for: panel)

            VStack(spacing: 10) {
                Image(systemName: panel.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(.mainText))
                    .padding(.bottom, 2)
                Text(panel.headline)
                    .font(.robotoSlab(26, relativeTo: .title))
                    .foregroundStyle(Color(.mainText))
                    .multilineTextAlignment(.center)
                Text(panel.body)
                    .font(.callout)
                    .foregroundStyle(Color(.mainText).opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 0)
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity)
    }

    /// The illustration slot — a soft tinted panel with a placeholder SF Symbol.
    /// Swap the inner content here when real artwork is ready.
    private func illustration(for panel: Panel) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(.royalBlue100))
            .frame(height: 200)
            .overlay(
                Image(systemName: panel.symbol)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Color(.mainText))
            )
            .padding(.horizontal, 24)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(panels.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color(.mainText) : Color(.separator))
                    .frame(width: index == page ? 20 : 7, height: 7)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: page)
            }
        }
    }

    private struct Panel {
        let symbol: String
        let headline: String
        let body: String
        let button: String
    }
}
