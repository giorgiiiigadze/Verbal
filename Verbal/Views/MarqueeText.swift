//
//  MarqueeText.swift
//  Verbal
//
//  A single-line label that scrolls its text horizontally, on a gentle
//  continuous loop, when the text is wider than the space it's given.
//  Short text that fits is rendered static (no pointless motion).
//

import SwiftUI

struct MarqueeText: View {
    let text: String
    var font: Font = .headline
    var color: Color = Color(.mainText)
    /// Gap between the repeated copies while scrolling.
    var gap: CGFloat = 44
    /// Scroll speed in points per second.
    var pointsPerSecond: CGFloat = 28

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var animate = false

    private var isOverflowing: Bool { textWidth > containerWidth + 0.5 }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            // Measure the width we have to work with.
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { containerWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, w in containerWidth = w }
                }
            )
            // Measure the text's natural width (hidden probe).
            .background(
                label
                    .fixedSize()
                    .hidden()
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { textWidth = proxy.size.width }
                                .onChange(of: text) { _, _ in textWidth = proxy.size.width }
                        }
                    )
            )
    }

    @ViewBuilder
    private var content: some View {
        if isOverflowing {
            scrolling
        } else {
            label
        }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var scrolling: some View {
        let distance = textWidth + gap
        let duration = Double(distance / max(pointsPerSecond, 1))
        return HStack(spacing: gap) {
            label.fixedSize()
            label.fixedSize()
        }
        .offset(x: animate ? -distance : 0)
        .frame(width: containerWidth, alignment: .leading)
        .clipped()
        .mask(edgeFade)
        .onAppear {
            animate = false
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
        // Restart the loop cleanly if the text (and thus distance) changes.
        .id(text)
    }

    /// Soft fade at both edges so text slides in/out instead of hard-clipping.
    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.06),
                .init(color: .black, location: 0.94),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
