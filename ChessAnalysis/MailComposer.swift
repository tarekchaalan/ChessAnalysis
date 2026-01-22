import SwiftUI
import MessageUI

struct MailAttachment {
    let data: Data
    let mimeType: String
    let fileName: String
}

struct MailComposer: UIViewControllerRepresentable {
    static var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }

    let recipients: [String]
    let subject: String
    let body: String
    let attachment: MailAttachment?

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.setToRecipients(recipients)
        composer.setSubject(subject)
        composer.setMessageBody(body, isHTML: false)
        if let attachment {
            composer.addAttachmentData(attachment.data, mimeType: attachment.mimeType, fileName: attachment.fileName)
        }
        composer.mailComposeDelegate = context.coordinator
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
        }
    }
}
