//
//  OnboardingView.swift
//  Verbal
//
//  The screens after registering and before entering the app.
//
//  Five product pages lead into the existing business setup questions.
//  It runs after authentication; answers are saved on completion.
//

import SwiftUI

struct OnboardingView: View {
    /// Called after setup finishes, to enter the app.
    var onContinue: () -> Void

    @Environment(SessionStore.self) private var session
    @State private var model = OnboardingModel()
    @State private var step = 0
    @FocusState private var focusedField: OnboardingField?
    @State private var isTradeHeaderSeparated = false
    @State private var isTradeFooterSeparated = false
    /// A short handoff after the final choice gives setup a visible finish
    /// before the main app appears.
    @State private var isPreparing = false
    private typealias Step = OnboardingModel.Step

    /// Keep the active step valid if the model changes its step list.
    private var current: Step {
        let all = model.steps
        return all[min(step, all.count - 1)]
    }

    /// Asked of the list rather than compared against one case, so adding a
    /// screen to the end doesn't leave the finishing behaviour on the one
    /// before it.
    private var isLastStep: Bool { step >= model.steps.count - 1 }

    private var isFeatureStep: Bool { step < OnboardingFeaturePage.allCases.count }

    private var pageBackground: Color {
        step == OnboardingFeaturePage.quote.rawValue
            ? .white
            : Color(red: 252 / 255, green: 252 / 255, blue: 249 / 255)
    }

    var body: some View {
        Group {
            if isPreparing {
                OnboardingPreparationView(onFinished: onContinue)
                    .transition(.opacity)
            } else {
                NavigationStack {
                    content
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            if step > 0 {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button(action: goBack) {
                                        Label("Back", systemImage: "chevron.backward")
                                            .labelStyle(.iconOnly)
                                    }
                                }
                            }

                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Skip", action: completeOnboarding)
                            }
                        }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var content: some View {
        ZStack {
            pageBackground
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.55), value: step)

            GeometryReader { geometry in
                OnboardingStep2LowerSurface()
                    .frame(height: min(300, max(240, geometry.size.height * 0.36)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .opacity(step == OnboardingFeaturePage.speak.rawValue ? 1 : 0)
                    .animation(.easeInOut(duration: 0.55), value: step)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                if isFeatureStep {
                    OnboardingFeaturePager(currentPage: step)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, step == OnboardingFeaturePage.quote.rawValue ? 0 : 24)

                    OnboardingPageIndicator(
                        currentPage: step,
                        pageCount: OnboardingFeaturePage.allCases.count
                    )
                    .padding(.top, 18)
                    .padding(.bottom, 18)
                } else {
                    stepView
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 24)
                }

                OnboardingContinueButton(
                    title: isLastStep ? "Get started" : "Continue",
                    isEnabled: canAdvance,
                    action: advance
                )
                .padding(.top, 12)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var stepView: some View {
        switch current {
        case .businessName:
            OnboardingBusinessNameStep(model: model, focused: $focusedField)
                .padding(.horizontal, 24)
        case .trade:
            OnboardingTradeStep(
                model: model,
                focused: $focusedField,
                isProgressHeaderSeparated: $isTradeHeaderSeparated,
                isFooterSeparated: $isTradeFooterSeparated
            )
            .padding(.horizontal, 24)
        case .welcome, .speak, .quote, .organise, .followUp:
            EmptyView()
        }
    }

    private var canAdvance: Bool {
        switch current {
        case .businessName:
            !model.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .trade:
            !model.trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            true
        }
    }

    // MARK: - Moving

    private func goBack() {
        guard step > 0 else { return }
        focusedField = nil
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
            step -= 1
        }
    }

    private func advance() {
        guard canAdvance else { return }
        guard !isLastStep else {
            completeOnboarding()
            return
        }
        focusedField = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
            step += 1
        }
    }

    private func completeOnboarding() {
        guard !isPreparing else { return }
        // The end of the questions, not another step through them — the
        // heavier notification marks it as arriving somewhere.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        model.saveDraft()
        Task { await session.adoptPostAuthOnboarding() }
        withAnimation(.easeInOut(duration: 0.25)) {
            isPreparing = true
        }
    }
}

// The preview supplies its own session store because the real flow now follows
// authentication.
//
// The trade is stored in `UserDefaults`, which the canvas shares with whatever
// ran last, so each preview sets it explicitly rather than inheriting a chip
// somebody tapped an hour ago. Setting it also decides which steps exist.
#Preview("From the start") {
    UserDefaults.standard.removeObject(forKey: "pendingTrade")
    return OnboardingView(onContinue: {})
        .environment(Store())
}
