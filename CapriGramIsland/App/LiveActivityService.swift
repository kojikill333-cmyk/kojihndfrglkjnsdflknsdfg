import ActivityKit
import Foundation

/// Owns the single Live Activity that keeps CapriGram present on the
/// Dynamic Island.
///
/// This is a direct port of CapriCompanion's `LiveActivityService`. The
/// companion's binary exposes exactly four operations and CapriGram uses the
/// same four:
///
/// * `start(with:staleDate:)` — requests one `Activity` and remembers it.
/// * `update(_:staleDate:alert:sound:)` — pushes new `ContentState`, optionally
///   with an `AlertConfiguration` so the island itself delivers the
///   notification (banner, sound, Lock Screen) without a separate push.
/// * `current` — the running activity, if iOS still has one.
/// * `endAll()` — tears every activity of this type down.
///
/// The activity is requested with `pushType: nil`: CapriCompanion drives the
/// island locally from battery changes, reactions and background tasks, not
/// from ActivityKit push tokens. CapriGram does the same, so the client keeps
/// updating the island from its own connection instead of depending on APNs.
@available(iOS 16.2, *)
public final class LiveActivityService {
    public static let shared = LiveActivityService()

    /// CapriCompanion throttles alert sounds so a burst of reactions can't
    /// machine-gun the speaker. `lastAlert` is that throttle.
    private var lastAlert = Date.distantPast
    private let minimumAlertSpacing: TimeInterval = 2

    private init() {}

    public enum StartError: LocalizedError {
        case activitiesDisabled
        case requestFailed(String)

        public var errorDescription: String? {
            switch self {
            case .activitiesDisabled:
                return "Live Activities выключены для CapriGram. Включи их в Настройки → CapriGram → Live Activities."
            case .requestFailed(let reason):
                return "Не удалось поднять Dynamic Island: \(reason)"
            }
        }
    }

    /// The activity iOS currently has for CapriGram, adopted across launches.
    ///
    /// CapriCompanion keeps the activity alive past the app's own lifetime, so
    /// on the next cold start the service must *find* it rather than start a
    /// second one. `Activity.activities` is how it does that.
    public var current: Activity<CapriGramActivityAttributes>? {
        Activity<CapriGramActivityAttributes>.activities.first
    }

    /// Raises the island. If one is already running it is reused — CapriGram,
    /// like CapriCompanion, never runs more than one island at a time.
    ///
    /// `staleDate` is the companion's heartbeat. iOS dims a Live Activity once
    /// its content goes stale, which is the signal the client uses to know it
    /// must check in again. Passing a near `staleDate` is what turns the island
    /// into a "keep the client awake" lease instead of a static decoration.
    @discardableResult
    public func start(
        with state: CapriGramActivityAttributes.ContentState,
        staleDate: Date? = nil
    ) async throws -> Activity<CapriGramActivityAttributes> {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw StartError.activitiesDisabled
        }

        if let existing = current {
            await existing.update(self.content(state, staleDate: staleDate))
            return existing
        }

        // The companion name is fixed for the life of the activity. The
        // message rides in ContentState instead, so it can change on every
        // update without iOS treating it as a different activity.
        let attributes = CapriGramActivityAttributes(constant: .init(companionName: "CapriGram"))

        do {
            // pushType stays nil on purpose: see the type comment above.
            return try Activity.request(
                attributes: attributes,
                content: content(state, staleDate: staleDate),
                pushType: nil
            )
        } catch {
            throw StartError.requestFailed(error.localizedDescription)
        }
    }

    /// Pushes a new state to the running island, starting one if the lease has
    /// lapsed. Mirrors `LiveActivityService.update(_:staleDate:alert:sound:)`.
    ///
    /// - Parameters:
    ///   - state: new `ContentState`.
    ///   - staleDate: when this content should be considered stale.
    ///   - alert: title and body announced through the island. `nil` updates
    ///     silently, which is what the heartbeat does.
    ///   - sound: bundled sound name. CapriCompanion resolves this with
    ///     `bundledSound(_:)`; an unknown name falls back to the default tone.
    public func update(
        _ state: CapriGramActivityAttributes.ContentState,
        staleDate: Date? = nil,
        alert: (title: String, body: String)? = nil,
        sound: String? = nil
    ) async {
        let alertConfiguration = makeAlert(alert, sound: sound)
        let content = self.content(state, staleDate: staleDate, alert: alertConfiguration)

        if let activity = current {
            // The alert is what makes the island announce the notification:
            // iOS plays the sound and raises the banner from the activity
            // update itself, which is how CapriCompanion delivers its alerts.
            await activity.update(content, alertConfiguration: alertConfiguration)
            return
        }

        // The island died (iOS reclaimed it, or the user dismissed it). Bring
        // it straight back so the client never loses its background lease.
        _ = try? await start(with: state, staleDate: staleDate)
    }

    /// Ends every CapriGram activity. CapriCompanion exposes this as `endAll()`
    /// and calls it when the user turns the island off.
    public func endAll() async {
        for activity in Activity<CapriGramActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: - Alerts

    /// Builds the `AlertConfiguration` CapriCompanion attaches to an update.
    /// Returns nil when the caller asked for a silent update or when the
    /// previous alert was too recent.
    private func makeAlert(
        _ alert: (title: String, body: String)?,
        sound: String?
    ) -> AlertConfiguration? {
        guard let alert else { return nil }

        let now = Date()
        guard now.timeIntervalSince(lastAlert) >= minimumAlertSpacing else { return nil }
        lastAlert = now

        return AlertConfiguration(
            title: LocalizedStringResource(stringLiteral: alert.title),
            body: LocalizedStringResource(stringLiteral: alert.body),
            sound: bundledSound(sound)
        )
    }

    /// CapriCompanion's `bundledSound(_:)`. A named file shipped in the app
    /// bundle becomes the alert tone; anything missing falls back to the
    /// system default so a notification is never silent by accident.
    private func bundledSound(_ name: String?) -> AlertConfiguration.AlertSound {
        guard let name, !name.isEmpty else { return .default }
        return .named(name)
    }

    /// An alerted update ranks above a heartbeat so that, if iOS ever has to
    /// choose which activity to surface, a real notification wins over the
    /// keep-alive tick. `alert` is accepted so the call site reads the same as
    /// the companion's, which threads the configuration through to one place.
    private func content(
        _ state: CapriGramActivityAttributes.ContentState,
        staleDate: Date?,
        alert: AlertConfiguration? = nil
    ) -> ActivityContent<CapriGramActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: staleDate, relevanceScore: alert == nil ? 50 : 100)
    }
}
