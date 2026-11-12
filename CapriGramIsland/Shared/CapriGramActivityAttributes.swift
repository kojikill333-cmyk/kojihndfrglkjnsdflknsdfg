import ActivityKit
import Foundation

/// Shared Live Activity contract between the CapriGram app and the
/// CapriGramIsland widget extension.
///
/// This file is compiled into both targets, so it imports only Foundation and
/// ActivityKit — the widget extension has no UIKit, and the contract doesn't
/// need any.
///
/// The shape is ported from CapriCompanion's `CapriActivityAttributes`. The
/// companion's reflection metadata lists the `ContentState` fields in this
/// order: `mood`, `message`, `batteryLevel`, `isCharging`, `showBattery`,
/// `revision`, `pose`, `boltOnly`, with `companionName` carried alongside.
/// CapriGram keeps that payload so the island behaves the way the companion's
/// does: one long-lived activity whose content is updated, never recreated,
/// which is what convinces iOS to keep the process warm.
public struct CapriGramActivityAttributes: ActivityAttributes {
    public typealias ContentState = State

    /// Stable for the lifetime of the activity. The island stays up; only
    /// `ContentState` changes.
    public struct ConstantAttributes: Codable, Hashable {
        /// Shown in the expanded island and on the Lock Screen. CapriCompanion
        /// stores its own name here so the widget can render it without
        /// calling back into the app.
        public var companionName: String

        public init(companionName: String = "CapriGram") {
            self.companionName = companionName
        }
    }

    public var constant: ConstantAttributes

    public init(constant: ConstantAttributes = ConstantAttributes()) {
        self.constant = constant
    }

    /// The mutable part, one field per field from the companion.
    public struct State: Codable, Hashable {
        /// Current island mood. Raw values match CapriCompanion's `IslandMood`.
        public var mood: IslandMood

        /// Line of text in the expanded island and on the Lock Screen.
        public var message: String

        /// Battery percent, 0...100. `nil` hides the reading.
        public var batteryLevel: Int?

        /// True while the device is on a charger.
        public var isCharging: Bool

        /// Whether the compact island renders the battery glyph at all.
        public var showBattery: Bool

        /// Bumped on every update. Live Activities dedupe identical content, so
        /// a changing revision is how CapriCompanion forces the island to
        /// redraw even when the visible text didn't change.
        public var revision: Int

        /// Named pose for the island figure. Empty lets the mood decide, which
        /// is the companion's default.
        public var pose: String

        /// Compact trailing slot shows only the charging bolt, no percent.
        public var boltOnly: Bool

        /// Who the notification is from. Empty while the island is just
        /// showing that the client is online.
        public var title: String

        /// Chat the quick replies on the island answer. Empty when the current
        /// notification can't be replied to.
        public var peer: String

        /// True when nothing is pending and the island is only there to show
        /// the client is alive. The widget draws a live dot in that state.
        public var online: Bool

        public init(
            mood: IslandMood = .idle,
            message: String = "",
            batteryLevel: Int? = nil,
            isCharging: Bool = false,
            showBattery: Bool = true,
            revision: Int = 0,
            pose: String = "",
            boltOnly: Bool = false,
            title: String = "",
            peer: String = "",
            online: Bool = true
        ) {
            self.mood = mood
            self.message = message
            self.batteryLevel = batteryLevel
            self.isCharging = isCharging
            self.showBattery = showBattery
            self.revision = revision
            self.pose = pose
            self.boltOnly = boltOnly
            self.title = title
            self.peer = peer
            self.online = online
        }
    }
}

/// Island moods, carried over from CapriCompanion's `IslandMood`.
///
/// The raw values travel inside the activity payload, so they have to stay
/// stable: the widget decodes whatever the app last wrote.
public enum IslandMood: String, Codable, Hashable, CaseIterable {
    case idle
    case blink
    case lookLeft
    case lookRight
    case headTilt
    case breathing
    case smile
    case happy
    case annoyed
    case surprised
    case sleepy
    case sleep
    case wakeUp
    case pointUp
    case charging
    case batteryLow
    case batteryCritical
    case headphones
    case phoneInteraction

    /// SF Symbol for the compact and minimal island slots. CapriCompanion draws
    /// its rigged figure in these slots; CapriGram has no such asset, so the
    /// mood is conveyed with a symbol instead.
    public var symbolName: String {
        switch self {
        case .idle, .blink, .breathing: return "message.fill"
        case .lookLeft, .lookRight, .headTilt: return "eyes"
        case .smile, .happy: return "face.smiling.fill"
        case .annoyed: return "exclamationmark.bubble.fill"
        case .surprised: return "bolt.fill"
        case .sleepy, .sleep: return "moon.zzz.fill"
        case .wakeUp: return "sun.max.fill"
        case .pointUp: return "arrow.up.circle.fill"
        case .charging: return "bolt.fill"
        case .batteryLow, .batteryCritical: return "battery.25percent"
        case .headphones: return "headphones"
        case .phoneInteraction: return "phone.fill"
        }
    }

    /// Short caption under the message in the expanded island.
    public var caption: String {
        switch self {
        case .batteryLow: return "Батарея садится"
        case .batteryCritical: return "Батарея почти на нуле"
        case .charging: return "На зарядке"
        case .headphones: return "В наушниках"
        case .phoneInteraction: return "Звонок"
        case .sleepy, .sleep: return "Тихий режим"
        default: return "На связи"
        }
    }
}
