import MessageUI
import SwiftUI

struct FeedbackView: View {
  @State private var isShowingMailComposer = false
  @State private var mailResult: Result<MFMailComposeResult, Error>? = nil
  @State private var showEmailCopiedAlert = false
  @State private var showEmailNotConfiguredAlert = false

  private let feedbackEmail = "assistivetech@mit.edu"

  var body: some View {
    VStack(spacing: 24) {
      VStack(spacing: 16) {
        Image(systemName: "envelope.fill")
          .font(.system(size: 60))
          .foregroundColor(.blue)
          .accessibilityHidden(true)

        Text("Send Feedback")
          .font(.largeTitle)
          .fontWeight(.bold)
      }
      .padding(.top, 40)

      VStack(spacing: 20) {
        Text(
          "Please share your thoughts, report issues, or suggest features. Your input helps us make the app better for everyone."
        )
        .font(.body)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)

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
        .padding(.horizontal)
        .accessibilityLabel("Send feedback email")
        .accessibilityHint("Opens email composer to send feedback to the development team")

        VStack(spacing: 8) {
          Text("Can't send email? You can also reach us at:")
            .font(.caption)
            .foregroundColor(.secondary)

          Button(action: copyEmailToClipboard) {
            Text(feedbackEmail)
              .font(.system(.body, design: .monospaced))
              .foregroundColor(.blue)
              .underline()
          }
          .accessibilityLabel("Copy email address \(feedbackEmail)")
          .accessibilityHint("Copies email address to clipboard")
        }
        .padding(.horizontal)
      }

      Spacer()

      VStack(spacing: 8) {
        Text("MIT Assistive Technology Club")
          .font(.caption)
          .foregroundColor(.secondary)

        Text("Thank you for using our app!")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
      .padding(.bottom, 20)
    }
    .navigationTitle("Feedback")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isShowingMailComposer) {
      MailComposer(
        isShowing: $isShowingMailComposer,
        result: $mailResult,
        recipients: [feedbackEmail],
        subject: "CurbToCar App Feedback"
      )
    }
    .alert(
      "Email Status",
      isPresented: Binding(
        get: { mailResult != nil },
        set: { _ in mailResult = nil }
      )
    ) {
      Button("OK") {}
    } message: {
      if let result = mailResult {
        switch result {
        case .success(let mailResult):
          switch mailResult {
          case .sent:
            Text("Thank you! Your feedback has been sent successfully.")
          case .saved:
            Text("Your feedback has been saved to drafts.")
          case .cancelled:
            Text("Feedback email was cancelled.")
          case .failed:
            Text("Failed to send feedback. Please try again.")
          @unknown default:
            Text("Unknown result.")
          }
        case .failure(let error):
          Text("Error: \(error.localizedDescription)")
        }
      }
    }
    .alert("Email Not Configured", isPresented: $showEmailNotConfiguredAlert) {
      Button("OK") {}
    } message: {
      Text(
        "Email is not configured on this device. The email address has been copied to your clipboard. Please paste it in your email app."
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
      showEmailNotConfiguredAlert = true
    }
  }

  private func copyEmailToClipboard() {
    UIPasteboard.general.string = feedbackEmail
    showEmailCopiedAlert = true
  }
}

struct MailComposer: UIViewControllerRepresentable {
  @Binding var isShowing: Bool
  @Binding var result: Result<MFMailComposeResult, Error>?
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
      if let error = error {
        parent.result = .failure(error)
      } else {
        parent.result = .success(result)
      }
      parent.isShowing = false
    }
  }
}

struct FeedbackView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationStack {
      FeedbackView()
    }
  }
}
