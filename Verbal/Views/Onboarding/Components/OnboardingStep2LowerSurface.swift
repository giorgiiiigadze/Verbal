import SwiftUI

/// A quiet full-width surface behind Step 2 copy and controls.
struct OnboardingStep2LowerSurface: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.blue.opacity(0.035), location: 0.16),
                    .init(color: .white.opacity(0.96), location: 0.58),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Ellipse()
                .fill(Color.blue.opacity(0.045))
                .frame(width: 300, height: 52)
                .blur(radius: 30)
                .offset(y: 4)

            LinearGradient(
                colors: [.clear, Color.blue.opacity(0.11), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 0.5)
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
    }
}
