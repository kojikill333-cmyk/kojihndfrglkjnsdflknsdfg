import Foundation

/// Everything the island screen can change.
///
/// Lives in the shared app group (`group.com.evoidk.caprigram`) because two
/// processes read it: the app, which decides whether to raise the island and
/// how, and the widget extension, which only needs to know whether a tap
/// should offer a reply. CapriCompanion keeps the same split in its
/// `SharedStore`; the keys here are CapriGram's own so the two apps don't
/// collide.
public struct IslandSettings: Codable, Equatable {
    /// The island is up and the background lease is armed.
    public var enabled: Bool

    /// Chat messages expand the island and can be answered from it.
    public var showMessages: Bool

    /// Mentions get their own, sharper treatment.
    public var showMentions: Bool

    /// Incoming calls take over the island until answered or declined.
    public var showCalls: Bool

    /// Battery percent in the compact slot, and a warning at the thresholds.
    public var showBattery: Bool

    /// A steady "CapriGram на связи" when nothing else is happening, so it's
    /// obvious the client is alive in the background.
    public var showOnlineStatus: Bool

    /// The expanded island offers quick replies and a text field.
    public var repliesEnabled: Bool

    /// Phrases behind the quick-reply buttons, in display order.
    public var quickReplies: [String]

    /// How long the island keeps a notification before falling back to the
    /// online status. Short notifications would otherwise sit forever.
    public var notificationHoldSeconds: Double

    /// How often the background refresh pushes the stale date forward.
    public var heartbeatMinutes: Double

    /// Alert sound name shipped in the bundle, or nil for the system tone.
    public var soundName: String?

    /// Whether this kind of notification is allowed to reach the island.
    public func allows(_ kind: IslandNotification.Kind) -> Bool {
        switch kind {
        case .message: return showMessages
        case .mention: return showMentions
        case .call: return showCalls
        case .battery: return showBattery
        case .status: return true
        }
    }

    public init(
        enabled: Bool = true,
        showMessages: Bool = true,
        showMentions: Bool = true,
        showCalls: Bool = true,
        showBattery: Bool = true,
        showOnlineStatus: Bool = true,
        repliesEnabled: Bool = true,
        quickReplies: [String] = IslandSettings.defaultQuickReplies,
        notificationHoldSeconds: Double = 30,
        heartbeatMinutes: Double = 15,
        soundName: String? = "notification"
    ) {
        self.enabled = enabled
        self.showMessages = showMessages
        self.showMentions = showMentions
        self.showCalls = showCalls
        self.showBattery = showBattery
        self.showOnlineStatus = showOnlineStatus
        self.repliesEnabled = repliesEnabled
        self.quickReplies = quickReplies
        self.notificationHoldSeconds = notificationHoldSeconds
        self.heartbeatMinutes = heartbeatMinutes
        self.soundName = soundName
    }

    public static let defaultQuickReplies = ["Ок", "Скоро буду", "Перезвоню", "👍"]

    /// Posted whenever the settings change, so the island and the screen stay
    /// in agreement without polling.
    public static let didChangeNotification = Notification.Name("CapriGramIslandSettingsDidChange")
}

/// Reads and writes `IslandSettings` in the shared app group.
public enum IslandSettingsStore {
    public static let suiteName = "group.com.evoidk.caprigram"
    private static let storageKey = "island.settings"

    public static var current: IslandSettings {
        get {
            guard
                let data = defaults.data(forKey: storageKey),
                let settings = try? JSONDecoder().decode(IslandSettings.self, from: data)
            else {
                return IslandSettings()
            }
            return settings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: storageKey)
            }
            NotificationCenter.default.post(name: IslandSettings.didChangeNotification, object: nil)
        }
    }

    /// The suite when the app group is provisioned, otherwise the standard
    /// defaults so the screen still works before signing is set up.
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}
