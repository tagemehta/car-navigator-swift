import MessageUI
import SwiftUI

struct FeedbackSection: View {
  @State private var isShowingMailComposer = false
  @State private var showEmailCopiedAlert = false

  private let feedbackEmail = "assistivetech@mit.edu"

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(
        "Please share your thoughts, report issues, or suggest features. Your input helps us make the app better for everyone."
      )
      .font(.body)
      .foregroundColor(.secondary)

      Button(action: sendFeedbackEmail) {
        HStack {
          Image(systemName: "envelope")
          Text("Email Feedback")
        }
        .font(.headline)
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.blue)
        .cornerRadius(12)
      }
      .accessibilityLabel("Send feedback email")
      .accessibilityHint("Opens email composer to send feedback to the development team")
      .listRowInsets(EdgeInsets())

      Text("MIT Assistive Technology Club")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.top, 8)
    }
    .padding(.vertical, 8)
    .sheet(isPresented: $isShowingMailComposer) {
      MailComposer(
        isShowing: $isShowingMailComposer,
        recipients: [feedbackEmail],
        subject: String(localized: "CurbToCar App Feedback", comment: "Email subject for feedback")
      )
    }
    .alert("Email Copied", isPresented: $showEmailCopiedAlert) {
      Button("OK") {}
    } message: {
      Text("\(feedbackEmail) has been copied to your clipboard.")
    }
  }

  private func sendFeedbackEmail() {
    if MFMailComposeViewController.canSendMail() {
      isShowingMailComposer = true
    } else {
      UIPasteboard.general.string = feedbackEmail
      showEmailCopiedAlert = true
    }
  }
}

struct MailComposer: UIViewControllerRepresentable {
  @Binding var isShowing: Bool
  let recipients: [String]
  let subject: String

  func makeUIViewController(context: Context) -> MFMailComposeViewController {
    let composer = MFMailComposeViewController()
    composer.mailComposeDelegate = context.coordinator
    composer.setToRecipients(recipients)
    composer.setSubject(subject)
    return composer
  }

  func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
    let parent: MailComposer

    init(_ parent: MailComposer) {
      self.parent = parent
    }

    func mailComposeController(
      _ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult,
      error: Error?
    ) {
      parent.isShowing = false
    }
  }
}
