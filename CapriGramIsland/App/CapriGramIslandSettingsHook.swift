import ObjectiveC
import UIKit

/// Puts an "Островок" entry inside CapriGram's own settings screen.
///
/// CapriGram's settings tab is `PeerInfoScreen.PeerInfoScreenImpl` in
/// TelegramUIFramework, rendered with AsyncDisplayKit nodes rather than a
/// `UITableView`. Its item list is built inside the compiled framework, so a
/// row can't be appended to it from outside. Instead the hook adds a button to
/// that screen's navigation bar, which is real UIKit and safe to extend.
///
/// The hook is deliberately narrow:
///
/// * it swizzles `viewWillAppear(_:)` on `PeerInfoScreenImpl` only, never on
///   `UIViewController` itself — swizzling the base class would run this code
///   for every screen in the app;
/// * the button only appears when that controller is the root of a tab, which
///   is how the settings tab differs from opening someone's profile, since the
///   same class serves both.
///
/// Two more entry points don't depend on the hook at all, so the settings stay
/// reachable even if a future CapriGram build renames the class:
/// the link `tg://caprigram/island`, and tapping the Dynamic Island while it
/// shows the online status.
@objc(CapriGramIslandSettingsHook)
public final class CapriGramIslandSettingsHook: NSObject {
    /// Swift class name of the settings / profile screen in CapriGram 13.1.3.
    private static let settingsClassName = "PeerInfoScreen.PeerInfoScreenImpl"

    private static var didInstall = false
    private static var buttonKey: UInt8 = 0

    @objc public static func install() {
        guard !didInstall else { return }
        didInstall = true

        guard let controllerType = NSClassFromString(settingsClassName) as? UIViewController.Type else {
            // Not found in this build. The deep link still works.
            return
        }
        swizzleViewWillAppear(in: controllerType)
    }

    /// Adds the swizzled method to the target class first, then exchanges. If
    /// the class doesn't override `viewWillAppear(_:)` itself, exchanging
    /// directly would rewire `UIViewController`'s implementation for everyone.
    private static func swizzleViewWillAppear(in controllerType: UIViewController.Type) {
        let originalSelector = #selector(UIViewController.viewWillAppear(_:))
        let swizzledSelector = #selector(UIViewController.caprigram_islandViewWillAppear(_:))

        guard
            let originalMethod = class_getInstanceMethod(controllerType, originalSelector),
            let swizzledMethod = class_getInstanceMethod(UIViewController.self, swizzledSelector)
        else {
            return
        }

        let addedOriginal = class_addMethod(
            controllerType,
            originalSelector,
            method_getImplementation(originalMethod),
            method_getTypeEncoding(originalMethod)
        )
        let addedSwizzled = class_addMethod(
            controllerType,
            swizzledSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )

        guard
            let targetOriginal = class_getInstanceMethod(controllerType, originalSelector),
            let targetSwizzled = class_getInstanceMethod(controllerType, swizzledSelector)
        else {
            return
        }
        _ = addedOriginal
        _ = addedSwizzled
        method_exchangeImplementations(targetOriginal, targetSwizzled)
    }

    fileprivate static func decorate(_ controller: UIViewController) {
        guard isSettingsTab(controller) else { return }
        guard objc_getAssociatedObject(controller, &buttonKey) == nil else { return }

        let button = UIBarButtonItem(
            image: UIImage(systemName: "capsule.portrait.fill"),
            style: .plain,
            target: CapriGramIslandSettingsHook.self,
            action: #selector(openSettings)
        )
        button.accessibilityLabel = "Островок"

        var items = controller.navigationItem.leftBarButtonItems ?? []
        items.append(button)
        controller.navigationItem.leftBarButtonItems = items

        objc_setAssociatedObject(controller, &buttonKey, button, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// The settings tab is the profile screen sitting at the root of a tab's
    /// navigation stack. Someone else's profile is pushed on top of a chat, so
    /// it's never the root.
    private static func isSettingsTab(_ controller: UIViewController) -> Bool {
        guard let navigation = controller.navigationController else { return false }
        guard navigation.viewControllers.first === controller else { return false }
        return navigation.tabBarController != nil || controller.tabBarItem.title != nil
    }

    @objc private static func openSettings() {
        CapriGramIsland.presentSettings()
    }
}

extension UIViewController {
    /// After the exchange this name points at the original `viewWillAppear`,
    /// so calling it runs the screen's own code first.
    @objc func caprigram_islandViewWillAppear(_ animated: Bool) {
        caprigram_islandViewWillAppear(animated)
        CapriGramIslandSettingsHook.decorate(self)
    }
}
