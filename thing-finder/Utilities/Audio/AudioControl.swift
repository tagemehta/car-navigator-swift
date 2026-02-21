import Foundation

enum AudioControl {
  static let pauseAllNotification = Notification.Name("AudioControl.pauseAll")
  static let resumeAllNotification = Notification.Name("AudioControl.resumeAll")

  static func pauseAll() {
    NotificationCenter.default.post(name: pauseAllNotification, object: nil)
  }

  static func resumeAll() {
    NotificationCenter.default.post(name: resumeAllNotification, object: nil)
  }
}
