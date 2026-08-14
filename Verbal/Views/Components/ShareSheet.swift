//
//  ShareSheet.swift
//  Verbal
//

import SwiftUI
import UIKit

/// UIActivityViewController wrapper that reports whether the share completed,
/// so callers can react (e.g. marking a quote as Sent).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
