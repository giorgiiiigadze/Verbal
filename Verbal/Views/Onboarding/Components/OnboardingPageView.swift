import SwiftUI

/// Product pages stay in model order; adding another case adds another pager slot.
enum OnboardingFeaturePage: Int, CaseIterable {
    case welcome, speak, quote, organise, followUp

    var title: String {
        switch self {
        case .welcome: "Welcome to Verbal"
        case .speak: "Speak naturally"
        case .quote: "Quotes in minutes"
        case .organise: "Everything in one place"
        case .followUp: "Stay one step ahead"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: "Turn the work you do into a clear quote."
        case .speak: "Describe the job as you would to a customer."
        case .quote: "Review the work, add prices, and send it on."
        case .organise: "Keep clients, quotes, and every detail together."
        case .followUp: "Follow up on the work that matters."
        }
    }
}

struct OnboardingFeaturePager: View {
    let currentPage: Int

    private let motion = Animation.spring(response: 0.55, dampingFraction: 0.9)

    var body: some View {
        GeometryReader { geometry in
            let isStep3 = currentPage == OnboardingFeaturePage.quote.rawValue
            let previewHeight = isStep3
                ? max(300, geometry.size.height - 100)
                : min(OnboardingPhonePreviewMeasurements.displayedFrameHeight,
                      max(300, geometry.size.height - 130))

            VStack(spacing: 0) {
                if !isStep3 {
                    Spacer(minLength: 12)
                }

                OnboardingPreviewContainer(
                    currentPage: currentPage,
                    height: previewHeight,
                    availableWidth: geometry.size.width
                )

                Spacer(minLength: 22)

                HStack(spacing: 0) {
                    ForEach(OnboardingFeaturePage.allCases, id: \.rawValue) { page in
                        pageView(for: page)
                            .frame(width: geometry.size.width)
                    }
                }
                .offset(x: -CGFloat(currentPage) * geometry.size.width)
                .animation(motion, value: currentPage)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(motion, value: currentPage)
        }
    }

    @ViewBuilder
    private func pageView(for page: OnboardingFeaturePage) -> some View {
        switch page {
        case .welcome: OnboardingStep1View()
        case .speak: OnboardingStep2View()
        case .quote: OnboardingStep3View()
        case .organise, .followUp: OnboardingPageView(page: page)
        }
    }
}

/// Only page copy moves horizontally. The phone has its own continuous animation.
struct OnboardingPageView: View {
    let page: OnboardingFeaturePage

    var body: some View {
        VStack(spacing: 8) {
            Text(page.title)
                .font(.robotoSlab(25, relativeTo: .title))
                .foregroundStyle(.black)

            Text(page.subtitle)
                .font(.callout)
                .foregroundStyle(Color.black.opacity(0.58))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .background(alignment: .bottom) {
            if page != .welcome {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.white.opacity(0.8))
                    .opacity(0.75)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.6), location: 0.08),
                                .init(color: .white, location: 0.18),
                                .init(color: .white, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .frame(height: 340)
                    .offset(y: 210)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// The artwork remains mounted while its screen, scale and position change.
struct OnboardingPreviewContainer: View {
    let currentPage: Int
    let height: CGFloat
    let availableWidth: CGFloat

    private let motion = Animation.spring(response: 0.55, dampingFraction: 0.9)

    private var normalScale: CGFloat {
        height / OnboardingPhonePreviewMeasurements.displayedFrameHeight
    }

    private var enlargedScale: CGFloat {
        min(1.45, max(1.15,
            (availableWidth + 20) / OnboardingPhonePreviewMeasurements.displayedFrameWidth))
    }

    /// Step 3 keeps the phone large, but lifts it enough to show its rounded bottom.
    private var step3Scale: CGFloat {
        min(1.24, max(1,
            (availableWidth - 60) / OnboardingPhonePreviewMeasurements.displayedFrameWidth))
    }

    private var step3Offset: CGFloat {
        height - OnboardingPhonePreviewMeasurements.displayedFrameHeight * step3Scale - 14
    }

    private var presentationPhase: CGFloat { CGFloat(min(currentPage, 3)) }

    var body: some View {
        DevicePreview {
            ZStack {
                Step1PhonePreview()
                    .opacity(currentPage == 0 ? 1 : 0)
                Step2PhonePreview()
                    .opacity(currentPage == 1 ? 1 : 0)
                Step3PhonePreview()
                    .opacity(currentPage == 2 ? 1 : 0)
                if currentPage > 2 {
                    OnboardingPlaceholderPhonePreview(page: OnboardingFeaturePage(rawValue: currentPage) ?? .quote)
                }
            }
            .animation(.easeInOut(duration: 0.24), value: currentPage)
        }
        .frame(width: OnboardingPhonePreviewMeasurements.displayedFrameWidth,
               height: OnboardingPhonePreviewMeasurements.displayedFrameHeight)
        .modifier(OnboardingPhonePresentation(
            phase: presentationPhase,
            normalScale: normalScale,
            enlargedScale: enlargedScale,
            step3Scale: step3Scale,
            step3Offset: step3Offset,
            height: height
        ))
        .animation(motion, value: presentationPhase)
    }
}

/// One interpolated value drives every phone state and the fade between them.
private struct OnboardingPhonePresentation: AnimatableModifier {
    var phase: CGFloat
    let normalScale: CGFloat
    let enlargedScale: CGFloat
    let step3Scale: CGFloat
    let step3Offset: CGFloat
    let height: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func body(content: Content) -> some View {
        let toStep2 = min(1, max(0, phase))
        let toStep3 = min(1, max(0, phase - 1))
        let toLaterPages = min(1, max(0, phase - 2))
        let scale = normalScale
            + (enlargedScale - normalScale) * toStep2
            + (step3Scale - enlargedScale) * toStep3
            + (normalScale - step3Scale) * toLaterPages
        let verticalOffset = -10 * toStep2
            + (step3Offset + 10) * toStep3
            - step3Offset * toLaterPages
        let fadeProgress = phase <= 1 ? toStep2 : max(0, 1 - toStep3)
        let edgeFade = phase <= 1 ? min(1, fadeProgress * 100) : fadeProgress

        content
            .scaleEffect(scale, anchor: .top)
            .offset(y: verticalOffset)
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.78),
                        .init(color: .white.opacity(1 - fadeProgress * 0.05), location: 0.83),
                        .init(color: .white.opacity(1 - fadeProgress * 0.23), location: 0.88),
                        .init(color: .white.opacity(1 - fadeProgress * 0.50), location: 0.93),
                        .init(color: .white.opacity(1 - fadeProgress * 0.80), location: 0.97),
                        .init(color: .white.opacity(1 - edgeFade), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: height)
    }
}

struct OnboardingPlaceholderPhonePreview: View {
    let page: OnboardingFeaturePage

    var body: some View {
        Text("Step \(page.rawValue + 1)")
            .font(.title2.weight(.semibold))
            .foregroundStyle(Color(.mainText))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.homeBackground))
    }
}
