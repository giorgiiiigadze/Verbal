//
//  MessageComposer.swift
//  Verbal
//
//  Native Messages composer for sending a local quote PDF to one customer.
//

import MessageUI
import SwiftUI

struct MessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let attachmentURL: URL
    let attachmentFilename: String
    var onFinished: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinished: onFinished) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = context.coordinator
        composer.recipients = recipients
        composer.body = body
        // A local file URL attaches the actual quote rather than a web link
        // that might later expire or require a sign-in.
        composer.addAttachmentURL(attachmentURL, withAlternateFilename: attachmentFilename)
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinished: (Bool) -> Void

        init(onFinished: @escaping (Bool) -> Void) {
            self.onFinished = onFinished
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true) {
                self.onFinished(result == .sent)
            }
        }
    }
}
