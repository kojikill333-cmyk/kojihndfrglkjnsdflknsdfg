import Foundation
import SwiftUI
import UIKit

/// The integration point between the existing CapriGram client and the island.
///
/// CapriGram ships as a compiled Telegram client, so its Swift sources aren't
/// in this tree. Rather than patching the binary, the island is wired in at
/// the two places the client already calls into app-level code:
///
/// * launch and scene transitions, through `CapriGramIslandAppDelegate`, which
///   is installed as an additional `UIApplicationDelegate` via the
///   `CapriGramIslandLoader` Objective-C loader below;
/// * incoming events, through `CapriGramIsland.handle(_:)`, which the client's
///   notification path can call directly.
///
/// Both entry points end up in `IslandBackgroundKeeper`, so there is exactly
/// one activity and one background lease no matter who triggered them.
public enum CapriGramIsland {
    /// Raises the island and arms the background lease. Safe to call more than
    /// once; a second call only refreshes the activity.
    public static func start() {
        BatteryMonitor.shared.start()
        IslandBackgroundKeeper.shared.start()
    }

    /// Forwards a scene phase change. Call from the client's scene delegate.
    public static func scenePhaseChanged(isActive: Bool) {
        if isActive {
            IslandBackgroundKeeper.shared.sceneDidBecomeActive()
        } else {
            IslandBackgroundKeeper.shared.sceneDidEnterBackground()
        }
    }

    /// Presents a notification on the Dynamic Island and takes a background
    /// lease long enough for the client to process it.
    public static func handle(_ notification: IslandNotification) {
        IslandBackgroundKeeper.shared.present(notification)
    }

    /// Emits a synthetic island notification so the user can instantly verify
    /// the runtime state, visual treatment and reply actions from inside the
    /// settings sheet.
    public static func previewNotification() {
        let notification = IslandNotification.message(
            from: "CapriGram",
            text: "Островок работает и готов к ответам",
            peer: "caprigram"
        )
        handle(notification)
    }

    /// Tears the island down. The client keeps its own connection logic; this
    /// only removes the background lease the island was providing.
    public static func stop() {
        BatteryMonitor.shared.stop()
        IslandBackgroundKeeper.shared.stop()
    }

    /// Opens the island settings over whatever CapriGram is currently showing.
    ///
    /// The client's own settings are compiled into TelegramUIFramework, so this
    /// is presented on top of them instead of being inserted into that list.
    /// Reachable from Swift as `CapriGramIsland.presentSettings()` and from the
    /// compiled client through `CapriGramIslandLoader`.
    public static func presentSettings() {
        DispatchQueue.main.async {
            guard let presenter = topViewController() else { return }
            if presenter is UIHostingController<IslandSettingsView> { return }

            let controller = UIHostingController(rootView: IslandSettingsView())
            controller.modalPresentationStyle = .formSheet
            presenter.present(controller, animated: true)
        }
    }

    /// The deepest view controller currently on screen. That's the one a new
    /// sheet has to be presented from, otherwise it lands behind a chat.
    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        return deepest(from: root)
    }

    private static func deepest(from controller: UIViewController?) -> UIViewController? {
        if let navigation = controller as? UINavigationController {
            return deepest(from: navigation.visibleViewController)
        }
        if let tab = controller as? UITabBarController {
            return deepest(from: tab.selectedViewController)
        }
        if let presented = controller?.presentedViewController {
            return deepest(from: presented)
        }
        return controller
    }
}

/// Objective-C visible loader.
///
/// Because CapriGram's own app delegate lives inside the compiled
/// `TelegramUIFramework`, this loader doesn't try to replace it. It observes
/// the same `UIApplication` notifications the system's delegate receives and
/// drives the island from those. That keeps the change entirely additive: the
/// client's existing delegate, push handling and background modes are
/// untouched.
@objc(CapriGramIslandLoader)
public final class CapriGramIslandLoader: NSObject {
    @objc public static let shared = CapriGramIslandLoader()

    private var didStart = false

    private override init() {
        super.init()
    }

    /// Hooks launch, background and foreground transitions. Called once from
    /// `+load` below, so it is in place before `didFinishLaunching` returns —
    /// which is also the deadline for registering the `BGAppRefreshTask`.
    @objc public func install() {
        guard !didStart else { return }
        didStart = true

        CapriGramIslandSettingsHook.install()
        CapriGramIslandURLHook.install()
        CapriGramNotificationBridge.install()

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(applicationDidFinishLaunching),
            name: UIApplication.didFinishLaunchingNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func applicationDidFinishLaunching() {
        CapriGramIsland.start()
    }

    /// Opens the settings when CapriGram is asked to open
    /// `tg://caprigram/island`. Returns true when the URL was the island's, so
    /// a caller can skip handing it to the client.
    ///
    /// The client resolves every other `tg://` link itself. This one is caught
    /// by `CapriGramIslandURLHook`, which wraps the scene delegate's URL
    /// handler.
    @objc public static func handle(url: URL) -> Bool {
        guard url.scheme == "tg", url.host == "caprigram", url.path == "/island" else {
            return false
        }
        CapriGramIsland.presentSettings()
        return true
    }

    @objc private func applicationDidEnterBackground() {
        CapriGramIsland.scenePhaseChanged(isActive: false)
    }

    @objc private func applicationDidBecomeActive() {
        CapriGramIsland.scenePhaseChanged(isActive: true)
    }

    /// Entry point for the compiled client, which can only see Objective-C.
    /// A settings button added to CapriGram calls this.
    @objc public func presentSettings() {
        CapriGramIsland.presentSettings()
    }
}
