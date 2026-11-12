import ObjectiveC
import UIKit

/// Catches `tg://caprigram/island` before CapriGram's own URL handling sees it.
///
/// CapriGram's Info.plist names `SceneDelegate` as the scene delegate class,
/// and links that arrive while the app runs are delivered to
/// `scene(_:openURLContexts:)`. The hook wraps that one method: the island's
/// own link opens the settings sheet, every other link is passed through to
/// the original implementation untouched.
///
/// Cold launches through the link deliver the URL in the connection options
/// instead, which the client handles; there the settings open from the
/// navigation bar button or the island itself.
@objc(CapriGramIslandURLHook)
public final class CapriGramIslandURLHook: NSObject {
    private static var didInstall = false
    private static let selector = NSSelectorFromString("scene:openURLContexts:")

    /// The client's implementation, captured before it is replaced.
    private typealias OpenURLContexts = @convention(c) (AnyObject, Selector, UIScene, Set<UIOpenURLContext>) -> Void
    private static var original: OpenURLContexts?

    @objc public static func install() {
        guard !didInstall else { return }
        didInstall = true

        let delegateClassName = sceneDelegateClassName() ?? "SceneDelegate"
        guard
            let delegateClass = NSClassFromString(delegateClassName),
            let method = class_getInstanceMethod(delegateClass, selector)
        else {
            return
        }

        original = unsafeBitCast(method_getImplementation(method), to: OpenURLContexts.self)

        let block: @convention(block) (AnyObject, UIScene, Set<UIOpenURLContext>) -> Void = { delegate, scene, contexts in
            let remaining = contexts.filter { !CapriGramIslandLoader.handle(url: $0.url) }
            guard !remaining.isEmpty else { return }
            CapriGramIslandURLHook.original?(delegate, CapriGramIslandURLHook.selector, scene, remaining)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    /// Reads the delegate class from the scene manifest so the hook follows
    /// the app if the class is ever renamed.
    private static func sceneDelegateClassName() -> String? {
        guard
            let manifest = Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any],
            let configurations = manifest["UISceneConfigurations"] as? [String: Any],
            let roles = configurations["UIWindowSceneSessionRoleApplication"] as? [[String: Any]],
            let name = roles.first?["UISceneDelegateClassName"] as? String
        else {
            return nil
        }
        return name
    }
}
