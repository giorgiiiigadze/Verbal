//
//  Toast.swift
//  Verbal
//
//  Small native liquid-glass toast shown at the top of the screen.
//
//  Top rather than bottom: the bottom edge is where the tab bar, the record
//  button and the recording screen's own controls live, and a toast landing
//  over them covered the thing the user had just reached for.
//

import SwiftUI

struct Toast: Equatable {
    enum Style {
        case success
        case error

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            }
        }
    }

    /// Distinct per toast, and part of equality on purpose. The modifier keys
    /// both its dismiss timer and its animation off this value, and without an
    /// identity two identical messages in a row are the same value — the timer
    /// wouldn't restart, so the second would inherit whatever was left of the
    /// first's and could vanish on sight. Duplicating two quotes in a row is
    /// enough to hit it.
    let id = UUID()
    var style: Style
    var message: String
}

private struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.style.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(toast.style.color)
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.mainText))
                // Nothing here is long today, but a capsule sized to a single
                // unbroken line runs off both edges of the screen rather than
                // wrapping, and it takes one wordy message to find that out.
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(in: .capsule)
        // Announced rather than left to be noticed. It is the only
        // confirmation some of these actions give, and it takes itself away.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    ToastView(toast: toast)
                        .padding(.top, 50)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: toast) {
                            try? await Task.sleep(for: .seconds(2.5))
                            // A replacing toast cancels this task, and a
                            // cancelled sleep returns rather than throwing past
                            // `try?` — so without this guard the outgoing
                            // toast's timer runs on and clears the one that
                            // just replaced it, seconds early.
                            guard !Task.isCancelled else { return }
                            withAnimation(.spring(duration: 0.35)) { self.toast = nil }
                        }
                }
            }
            .animation(.spring(duration: 0.35), value: toast)
    }
}

extension View {
    /// Presents a native liquid-glass toast at the top, auto-dismissing.
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
