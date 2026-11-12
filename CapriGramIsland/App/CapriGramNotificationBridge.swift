import Foundation
import UserNotifications

/// Bridges CapriGram's notification handling into the Dynamic Island.
///
/// The client already receives notifications through its own path. This bridge
/// extracts the relevant fields (sender, message text, peer ID) and forwards
/// them to `IslandBackgroundKeeper`, which raises the island and shows the
/// content there.
///
/// Installation:
/// Call `CapriGramNotificationBridge.install()` from `+load` to swizzle the
/// notification center delegate method that fires when a notification arrives
/// while the app is in foreground or background.
@objc(CapriGramNotificationBridge)
public final class CapriGramNotificationBridge: NSObject {
    private static var didInstall = false

    @objc public static func install() {
        guard !didInstall else { return }
        didInstall = true

        // The client's notification center delegate is set dynamically at
        // runtime, so swizzling the delegate's class directly won't work.
        // Instead, wrap `UNUserNotificationCenter.setDelegate(_:)` to
        // capture the real delegate and proxy it.
        swizzleSetDelegate()
    }

    private static func swizzleSetDelegate() {
        let center = UNUserNotificationCenter.self
        let original = #selector(UNUserNotificationCenter.setDelegate(_:))
        let swizzled = #selector(UNUserNotificationCenter.caprigram_setDelegate(_:))

        guard
            let originalMethod = class_getInstanceMethod(center, original),
            let swizzledMethod = class_getInstanceMethod(center, swizzled)
        else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    /// Extracts a notification from the client's own payload format and raises
    /// the island if the settings allow it.
    fileprivate static func handle(
        _ notification: UNNotification,
        center: UNUserNotificationCenter,
        completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        // CapriGram's notification payload contains these keys (may vary by build):
        // - "from_id" or "peer_id": numeric peer ID
        // - "text" or "message": message body
        // - "title" or "name": sender display name
        // - "call": true for incoming calls
        // - "mention": true for @mentions

        let fromID = userInfo["from_id"] as? Int64
            ?? userInfo["peer_id"] as? Int64
            ?? 0
        let text = userInfo["text"] as? String
            ?? userInfo["message"] as? String
            ?? notification.request.content.body
        let title = userInfo["title"] as? String
            ?? userInfo["name"] as? String
            ?? notification.request.content.title
        let isCall = userInfo["call"] as? Bool ?? false
        let isMention = userInfo["mention"] as? Bool ?? false

        // Build a peer identifier for reply URLs. The client's internal peer
        // format is numeric, but reply URLs need a username or `user?id=123`.
        // If the notification includes a username field, use it; otherwise
        // construct a numeric fallback.
        let username = userInfo["username"] as? String
        let peer = username ?? (fromID != 0 ? "user?id=\(fromID)" : "")

        let islandNotification: IslandNotification
        if isCall {
            islandNotification = .call(from: title)
        } else if isMention {
            islandNotification = .mention(from: title, text: text, peer: peer)
        } else {
            islandNotification = .message(from: title, text: text, peer: peer)
        }

        CapriGramIsland.handle(islandNotification)

        // Let the client's own handler decide presentation options. The island
        // shows the content in parallel, so the client can still show a banner
        // or play a sound if its delegate wants to.
        completionHandler([.banner, .sound, .badge])
    }
}

extension UNUserNotificationCenter {
    @objc func caprigram_setDelegate(_ delegate: UNUserNotificationCenterDelegate?) {
        // Call the original setter first.
        caprigram_setDelegate(delegate)

        // Wrap the delegate in a proxy that calls the island bridge before
        // forwarding to the real delegate.
        if let delegate = delegate {
            let proxy = NotificationDelegateProxy(target: delegate)
            caprigram_setDelegate(proxy)
        }
    }
}

/// Forwards notification delegate calls to the real delegate while extracting
/// relevant data for the island.
private final class NotificationDelegateProxy: NSObject, UNUserNotificationCenterDelegate {
    private weak var target: UNUserNotificationCenterDelegate?

    init(target: UNUserNotificationCenterDelegate) {
        self.target = target
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Extract for the island first.
        CapriGramNotificationBridge.handle(notification, center: center, completionHandler: { _ in })

        // Forward to the real delegate.
        if let target = target {
            target.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
        } else {
            completionHandler([.banner, .sound, .badge])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // The user tapped a notification. Let the client handle opening the chat.
        target?.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
            ?? completionHandler()
    }

    override func responds(to aSelector: Selector!) -> Bool {
        target?.responds(to: aSelector) ?? super.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        target
    }
}
