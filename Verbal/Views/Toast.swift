//
//  Toast.swift
//  Verbal
//
//  Small native liquid-glass toast shown at the bottom of the screen.
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
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(in: .capsule)
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastView(toast: toast)
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: toast) {
                            try? await Task.sleep(for: .seconds(2.5))
                            withAnimation(.spring(duration: 0.35)) { self.toast = nil }
                        }
                }
            }
            .animation(.spring(duration: 0.35), value: toast)
    }
}

extension View {
    /// Presents a native liquid-glass toast at the bottom, auto-dismissing.
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
