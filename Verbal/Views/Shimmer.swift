//
//  Shimmer.swift
//  Verbal
//
//  A highlight sweeping across a view — the app's "working on it" motion,
//  used on the live transcript, the generating banner, and sign-in.
//

import SwiftUI

private struct ShimmerModifier: ViewModifier {
    var active: Bool
    /// Color of the travelling highlight. Defaults to `.primary`, which reads
    /// as a sweep over text; pass white to make a gleam over a dark mark.
    var highlight: Color = .primary
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    LinearGradient(
                        colors: [.clear, highlight.opacity(0.35), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 0.5)
                    .offset(x: -width * 0.5 + phase * (width + width * 0.5))
                }
                .mask(content)
                .allowsHitTesting(false)
                .opacity(active ? 1 : 0)
                .animation(.easeInOut(duration: 0.45), value: active)
            }
            // Start on appear too: a view born already shimmering (the
            // generating banner) never sees a change to react to.
            .onAppear { if active { startSweep() } }
            .onChange(of: active) { _, isActive in
                if isActive {
                    startSweep()
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) { phase = 0 }
                }
            }
    }

    private func startSweep() {
        phase = 0
        withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }
}

extension View {
    func shimmer(active: Bool, highlight: Color = .primary) -> some View {
        modifier(ShimmerModifier(active: active, highlight: highlight))
    }
}
