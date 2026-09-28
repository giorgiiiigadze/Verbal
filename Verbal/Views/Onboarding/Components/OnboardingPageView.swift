import SwiftUI

/// Product pages stay in model order; adding another case adds another pager slot.
enum OnboardingFeaturePage: Int, CaseIterable {
    case welcome, speak, quote, organise

    var title: String {
        switch self {
        case .welcome: "Welcome to Verbal"
        case .speak: "Speak naturally"
        case .quote: "Quotes in minutes"
        case .organise: "All your work, in one place"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: "Turn the work you do into a clear quote."
        case .speak: "Describe the job as you would to a customer."
        case .quote: "Review the work, add prices, and send it on."
        case .organise: "Keep every client, quote, and job detail together."
        }
    }
}

struct OnboardingFeaturePager: View {
    let currentPage: Int
    let onPageChange: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.9)
    }

    var body: some View {
        GeometryReader { geometry in
            // Keep the phone anchored near the top; reserve the flexible space below it for copy.
            let topMargin = min(22, max(10, geometry.size.height * 0.025))
            let copyReserve = dynamicTypeSize.isAccessibilitySize
                ? min(220, geometry.size.height * 0.35)
                : min(135, max(110, geometry.size.height * 0.18))
            let previewHeight = min(
                OnboardingPhonePreviewMeasurements.displayedFrameHeight * 1.05,
                max(0, geometry.size.height - topMargin - copyReserve)
            )

            VStack(spacing: 0) {
                OnboardingPreviewContainer(
                    currentPage: currentPage,
                    height: previewHeight,
                    availableWidth: geometry.size.width,
                    topOverflow: geometry.safeAreaInsets.top + topMargin + 125
                )
                .frame(height: previewHeight)
                .padding(.top, topMargin)
                .accessibilityHidden(true)

                Spacer(minLength: 16)

                HStack(spacing: 0) {
                    ForEach(OnboardingFeaturePage.allCases, id: \.rawValue) { page in
                        pageView(for: page)
                            .frame(width: geometry.size.width)
                    }
                }
                .frame(width: geometry.size.width, alignment: .leading)
                .offset(x: -CGFloat(currentPage) * geometry.size.width)
                .animation(motion, value: currentPage)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(motion, value: currentPage)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.3,
                              abs(value.translation.width) > 55 else { return }
                        let nextPage = currentPage + (value.translation.width < 0 ? 1 : -1)
                        guard OnboardingFeaturePage.allCases.indices.contains(nextPage) else { return }
                        onPageChange(nextPage)
                    }
            )
        }
    }

    @ViewBuilder
    private func pageView(for page: OnboardingFeaturePage) -> some View {
        switch page {
        case .welcome: OnboardingStep1View()
        case .speak: OnboardingStep2View()
        case .quote: OnboardingStep3View()
        case .organise: OnboardingPageView(page: page)
        }
    }
}

/// The copy and phone screen move horizontally while the device frame stays put.
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
    }
}

/// Steps 2 and 3 enlarge the phone; Step 3 also extends above the screen.
struct OnboardingPreviewContainer: View {
    let currentPage: Int
    let height: CGFloat
    let availableWidth: CGFloat
    let topOverflow: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.9)
    }

    private var scale: CGFloat {
        let regularScale = height / OnboardingPhonePreviewMeasurements.displayedFrameHeight
        guard currentPage == OnboardingFeaturePage.speak.rawValue ||
              currentPage == OnboardingFeaturePage.quote.rawValue else { return regularScale }
        return max(regularScale, availableWidth * 0.88 / OnboardingPhonePreviewMeasurements.displayedFrameWidth)
    }

    var body: some View {
        DevicePreview {
            GeometryReader { screen in
                HStack(spacing: 0) {
                    Step1PhonePreview()
                        .frame(width: screen.size.width, height: screen.size.height)
                    Step2PhonePreview()
                        .frame(width: screen.size.width, height: screen.size.height)
                    Step3PhonePreview()
                        .frame(width: screen.size.width, height: screen.size.height)
                    OnboardingPlaceholderPhonePreview(page: .organise)
                        .frame(width: screen.size.width, height: screen.size.height)
                }
                .frame(height: screen.size.height)
                .frame(width: screen.size.width, alignment: .leading)
                .offset(x: -CGFloat(currentPage) * screen.size.width)
                .animation(motion, value: currentPage)
            }
        }
        .frame(width: OnboardingPhonePreviewMeasurements.displayedFrameWidth,
               height: OnboardingPhonePreviewMeasurements.displayedFrameHeight)
            .scaleEffect(scale, anchor: .top)
            .offset(y: currentPage == OnboardingFeaturePage.quote.rawValue ? -topOverflow : 0)
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.985),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height + (currentPage == OnboardingFeaturePage.quote.rawValue ? topOverflow : 0))
                .frame(height: height, alignment: .bottom)
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
