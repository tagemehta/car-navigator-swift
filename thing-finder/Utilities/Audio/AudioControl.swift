import Foundation

enum AudioControl {
  static let pauseAllNotification = Notification.Name("AudioControl.pauseAll")

  static func pauseAll() {
    NotificationCenter.default.post(name: pauseAllNotification, object: nil)
  }
}
