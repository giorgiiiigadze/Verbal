import SwiftUI

struct OnboardingPageIndicator: View {
    let currentPage: Int
    let pageCount: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<pageCount, id: \.self) { page in
                Capsule(style: .continuous)
                    .fill(page == currentPage ? Color.black : Color.black.opacity(0.18))
                    .frame(width: page == currentPage ? 18 : 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.38), value: currentPage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentPage + 1) of \(pageCount)")
    }
}

struct OnboardingContinueButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.black, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}
