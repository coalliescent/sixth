#if !TESTING
import Foundation
import UserNotifications
import os

private let logger = Logger(subsystem: "com.sixth.app", category: "Notifications")

class NotificationManager {
    var isEnabled = true
    private var hasPermission = false

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            DispatchQueue.main.async {
                self.hasPermission = granted
                if let error = error {
                    logger.error("permission error: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func showNowPlaying(song: String, artist: String, album: String) {
        guard isEnabled, hasPermission else { return }

        let content = UNMutableNotificationContent()
        content.title = song
        content.subtitle = artist
        content.body = album

        let request = UNNotificationRequest(
            identifier: "nowPlaying",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("failed to post: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
#endif
