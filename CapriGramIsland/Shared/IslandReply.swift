import Foundation

/// A reply the user composed on the Dynamic Island.
///
/// The island can't send a Telegram message by itself: widget extensions have
/// no network stack and no access to the account. So a reply becomes a deep
/// link that CapriGram already knows how to open. The client resolves it, and
/// the text lands in the compose field of the right chat — the same path the
/// app uses for the system share sheet.
public struct IslandReply: Equatable {
    /// Username, or a chat reference the client can resolve.
    public var peer: String

    /// What the user wants to send.
    public var text: String

    public init(peer: String, text: String) {
        self.peer = peer
        self.text = text
    }

    /// `tg://resolve?domain=<peer>&text=<text>`.
    ///
    /// CapriGram registers the `tg` scheme (see its Info.plist) and its client
    /// already resolves `domain` to a chat. `text` is the standard parameter
    /// Telegram clients use to prefill the message field, so the reply doesn't
    /// need a new entry point inside the compiled client.
    public var url: URL {
        var components = URLComponents()
        components.scheme = "tg"
        components.host = "resolve"
        components.queryItems = [
            URLQueryItem(name: "domain", value: peer),
            URLQueryItem(name: "text", value: text)
        ]
        return components.url ?? URL(string: "tg://resolve?domain=\(peer)")!
    }

    /// Opens the chat without prefilling anything. Used by the "open" button.
    public static func openChat(peer: String) -> URL {
        var components = URLComponents()
        components.scheme = "tg"
        components.host = "resolve"
        components.queryItems = [URLQueryItem(name: "domain", value: peer)]
        return components.url ?? URL(string: "tg://")!
    }
}

/// One incoming message the island is currently showing and can answer.
///
/// Only the latest one is kept. The compact island has room for a single
/// conversation, and a newer message simply replaces the one before it.
public struct IslandPendingReply: Codable, Equatable {
    public var peer: String
    public var title: String
    public var body: String
    public var receivedAt: Date

    public init(peer: String, title: String, body: String, receivedAt: Date = Date()) {
        self.peer = peer
        self.title = title
        self.body = body
        self.receivedAt = receivedAt
    }
}

/// The message waiting for an answer, shared with the widget extension so the
/// expanded island knows which chat a quick reply belongs to.
public enum IslandPendingReplyStore {
    private static let storageKey = "island.pendingReply"

    public static var current: IslandPendingReply? {
        get {
            guard
                let data = defaults.data(forKey: storageKey),
                let pending = try? JSONDecoder().decode(IslandPendingReply.self, from: data)
            else {
                return nil
            }
            return pending
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: storageKey)
            } else {
                defaults.removeObject(forKey: storageKey)
            }
        }
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: IslandSettingsStore.suiteName) ?? .standard
    }
}
