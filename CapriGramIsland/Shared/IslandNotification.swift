import Foundation

/// A notification the island can surface.
///
/// CapriCompanion's `LiveActivityService.update` takes an optional
/// `(title, body)` alert plus a sound name and turns it into an
/// `AlertConfiguration` on the Live Activity. This is the CapriGram-side
/// equivalent: the app describes what happened, the island service decides
/// whether it becomes an alert, a mood change, or both.
public struct IslandNotification: Codable, Hashable {
    public enum Kind: String, Codable {
        /// A new chat message. Expands the island briefly, then settles.
        case message
        /// A mention. Same treatment as a message, but a sharper mood.
        case mention
        /// An incoming or ongoing call.
        case call
        /// Battery crossed a threshold. CapriCompanion treats this as a
        /// first-class island event, so CapriGram does too.
        case battery
        /// Anything else the client wants to say.
        case status
    }

    public var kind: Kind
    public var title: String
    public var body: String

    /// Who the reply goes back to: a username or a chat reference the client
    /// can resolve. Empty for notifications that can't be answered, such as a
    /// battery warning.
    public var peer: String

    /// Bundled sound name without extension, matching CapriCompanion's
    /// `bundledSound(_:)`. `nil` keeps the update silent.
    public var soundName: String?

    /// Mood the island should adopt while this notification is showing.
    public var mood: IslandMood

    public init(
        kind: Kind,
        title: String,
        body: String,
        peer: String = "",
        soundName: String? = "notification",
        mood: IslandMood = .happy
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.peer = peer
        self.soundName = soundName
        self.mood = mood
    }

    /// Whether the expanded island should offer replies for this notification.
    public var canReply: Bool {
        !peer.isEmpty && (kind == .message || kind == .mention)
    }

    /// CapriGram chat message. `peer` is the username the reply is addressed to.
    public static func message(from name: String, text: String, peer: String) -> IslandNotification {
        IslandNotification(kind: .message, title: name, body: text, peer: peer, mood: .smile)
    }

    /// CapriGram mention.
    public static func mention(in chat: String, text: String, peer: String) -> IslandNotification {
        IslandNotification(kind: .mention, title: chat, body: text, peer: peer, soundName: "island_alert", mood: .surprised)
    }

    /// CapriGram call. Calls are answered by opening the chat, not by text.
    public static func call(from name: String, peer: String) -> IslandNotification {
        IslandNotification(kind: .call, title: name, body: "Входящий звонок", peer: peer, soundName: "island_alert", mood: .phoneInteraction)
    }
}
