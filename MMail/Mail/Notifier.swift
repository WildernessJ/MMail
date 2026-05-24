import Foundation
import UserNotifications

// Local user notifications for new mail, with Archive / Trash actions.
enum Notifier {
    static let category = "NEW_MAIL"
    private static let actionDelegate = NotificationActionDelegate()

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Wire up the action buttons and route taps/actions to `handler(action, emailId)`.
    static func configure(handler: @escaping (String, String) -> Void) {
        actionDelegate.handler = handler
        let center = UNUserNotificationCenter.current()
        center.delegate = actionDelegate
        let archive = UNNotificationAction(identifier: "ARCHIVE", title: "Archive", options: [])
        let trash = UNNotificationAction(identifier: "TRASH", title: "Trash", options: [.destructive])
        let cat = UNNotificationCategory(identifier: category, actions: [archive, trash],
                                         intentIdentifiers: [], options: [])
        center.setNotificationCategories([cat])
    }

    static func notify(title: String, body: String, emailId: String? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let emailId {
                content.categoryIdentifier = category
                content.userInfo = ["emailId": emailId]
            }
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request, withCompletionHandler: nil)
        }
    }
}

private final class NotificationActionDelegate: NSObject, UNUserNotificationCenterDelegate {
    var handler: ((String, String) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let emailId = response.notification.request.content.userInfo["emailId"] as? String ?? ""
        if !emailId.isEmpty {
            DispatchQueue.main.async { self.handler?(action, emailId) }
        }
        completionHandler()
    }

    // Show banners even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
