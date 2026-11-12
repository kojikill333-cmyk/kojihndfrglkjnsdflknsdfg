import BackgroundTasks
import Foundation
import UIKit

/// Keeps the CapriGram client alive in the background the way CapriCompanion
/// keeps itself alive: a Live Activity that is never allowed to go stale, fed
/// by a background task and a refresh lease.
///
/// CapriCompanion does this with three cooperating pieces, all present in its
/// binary, and CapriGram uses the same three:
///
/// 1. `LiveActivityService` holds one ongoing Live Activity. While an activity
///    is active iOS treats the app as running a live task: it gets background
///    execution time to update that activity, it is relaunched to do so, and
///    the system does not suspend it the way it suspends an ordinary app.
/// 2. `beginBackgroundTask(withName:expirationHandler:)` covers the gap between
///    "the user just left" and "the activity update has been delivered", which
///    is exactly where CapriCompanion calls it.
/// 3. `BGAppRefreshTask` (identifier `com.evoidk.capricompanion.joke` over
///    there) periodically wakes the process so the island can be refreshed
///    even when no message arrives. CapriGram registers the same kind of task.
///
/// None of this replaces CapriGram's existing `voip`, `remote-notification`,
/// `fetch` and `processing` background modes. It adds the island lease on top,
/// so a client that is already connected stays connected instead of being
/// frozen the moment the app is backgrounded.
public final class IslandBackgroundKeeper: NSObject {
    public static let shared = IslandBackgroundKeeper()

    /// Background refresh identifier. Declared in the app's
    /// `BGTaskSchedulerPermittedIdentifiers`, exactly as CapriCompanion declares
    /// `com.evoidk.capricompanion.joke`.
    public static let refreshTaskIdentifier = "com.evoidk.caprigram.island"

    /// How long content stays fresh. Comes from the settings screen; the
    /// fallback matches CapriCompanion, which keeps the stale date close so iOS
    /// comes back for an update rather than letting the island fade.
    public var heartbeatInterval: TimeInterval {
        IslandSettingsStore.current.heartbeatMinutes * 60
    }

    /// Whether the island should be up at all. The settings screen is the one
    /// place this changes.
    public var isEnabled: Bool {
        get { IslandSettingsStore.current.enabled }
        set {
            var settings = IslandSettingsStore.current
            settings.enabled = newValue
            IslandSettingsStore.current = settings
        }
    }

    private var revision = 0
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var heartbeat: Timer?

    /// The notification currently on the island, so it can fall back to the
    /// plain "на связи" status once its hold time runs out.
    private var activeNotification: IslandNotification?
    private var clearNotificationTask: Task<Void, Never>?

    private let storage: UserDefaults = {
        // Same trick as CapriCompanion's `SharedStore`: an app group so the
        // widget extension and the app read one set of preferences. Falls back
        // to the standard defaults if the group isn't provisioned yet.
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }()

    private enum Keys {
        static let revision = "island.revision"
    }

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    /// Call once at launch, from the app delegate. Registers the background
    /// refresh handler *before* the end of `didFinishLaunching` — iOS requires
    /// that — and raises the island if it should already be up.
    public func start() {
        registerBackgroundRefresh()
        scheduleBackgroundRefresh()

        guard isEnabled else { return }
        Task { await self.showOnlineStatus() }
    }

    /// Call when the scene moves to the background. CapriCompanion does this
    /// from `scenePhaseChanged`: it takes a background task so the island
    /// update finishes even though the app is no longer foreground.
    public func sceneDidEnterBackground() {
        guard isEnabled else { return }
        beginBackgroundLease(named: "caprigram.island.background")
        Task {
            await self.showOnlineStatus(backgrounded: true)
            self.endBackgroundLease()
        }
    }

    /// Call when the scene returns to the foreground. Refreshes the island so
    /// the stale date is pushed back out and drops the background lease.
    public func sceneDidBecomeActive() {
        guard isEnabled else { return }
        Task { await self.showOnlineStatus() }
    }

    /// Turns the island off and ends the activity. Mirrors the companion's
    /// path for `islandAutoStart = false`.
    public func stop() {
        isEnabled = false
        heartbeat?.invalidate()
        heartbeat = nil
        if #available(iOS 16.2, *) {
            Task { await LiveActivityService.shared.endAll() }
        }
    }

    // MARK: - Notifications

    /// Surfaces a notification on the island.
    ///
    /// This is the CapriGram equivalent of CapriCompanion's `showInIsland`.
    /// The companion routes reactions, battery events and jokes through it;
    /// CapriGram routes chat messages, mentions and calls. The island expands,
    /// plays the sound, and the activity update is what grants the client the
    /// background time to actually fetch and ack the message.
    public func present(_ notification: IslandNotification) {
        let settings = IslandSettingsStore.current
        guard settings.enabled, settings.allows(notification.kind) else { return }

        if notification.canReply {
            IslandPendingReplyStore.current = IslandPendingReply(
                peer: notification.peer,
                title: notification.title,
                body: notification.body
            )
        }

        beginBackgroundLease(named: "caprigram.island.notification")
        activeNotification = notification
        Task {
            await raiseIsland(
                message: notification.body,
                mood: notification.mood,
                title: notification.title,
                peer: notification.peer,
                alert: (notification.title, notification.body),
                sound: notification.soundName ?? settings.soundName
            )
            self.scheduleClear(after: settings.notificationHoldSeconds)
            self.endBackgroundLease()
        }
    }

    /// Returns the island to its resting state: a visible "на связи" when the
    /// user wants to see that the client is alive, otherwise just the lease
    /// with no message.
    private func showOnlineStatus(backgrounded: Bool = false) async {
        guard isEnabled else { return }
        guard activeNotification == nil else { return }

        let settings = IslandSettingsStore.current
        let message: String
        if settings.showOnlineStatus {
            message = backgrounded ? "CapriGram работает в фоне" : "CapriGram на связи"
        } else {
            message = ""
        }
        await raiseIsland(message: message, mood: backgrounded ? .breathing : .idle, title: "", peer: "")
    }

    /// Drops the notification back to the resting state once it has been on
    /// screen long enough. A newer notification cancels the pending clear.
    private func scheduleClear(after seconds: Double) {
        clearNotificationTask?.cancel()
        clearNotificationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.activeNotification = nil
            await self.showOnlineStatus()
        }
    }

    /// Silent heartbeat used by the background refresh task. No alert, no
    /// sound — it only exists to push the stale date forward and prove to iOS
    /// that the client is still alive.
    public func heartbeatTick() async {
        guard isEnabled else { return }
        await showOnlineStatus()
    }

    // MARK: - Island updates

    @available(iOS 16.2, *)
    private func raiseIsland(
        message: String,
        mood: IslandMood,
        title: String = "",
        peer: String = "",
        alert: (title: String, body: String)? = nil,
        sound: String? = nil
    ) async {
        revision += 1
        storage.set(revision, forKey: Keys.revision)

        let settings = IslandSettingsStore.current
        let battery = BatterySnapshot.current
        let state = CapriGramActivityAttributes.ContentState(
            mood: battery.moodOverride ?? mood,
            message: message,
            batteryLevel: battery.level,
            isCharging: battery.isCharging,
            showBattery: settings.showBattery,
            revision: revision,
            pose: "",
            boltOnly: false,
            title: title,
            peer: peer,
            online: settings.showOnlineStatus && activeNotification == nil
        )

        // The stale date is the lease. When it expires iOS marks the activity
        // stale and gives the app a chance to update it — which is the wakeup
        // CapriCompanion relies on to stay resident.
        let staleDate = Date().addingTimeInterval(heartbeatInterval)

        if LiveActivityService.shared.current == nil {
            _ = try? await LiveActivityService.shared.start(with: state, staleDate: staleDate)
        }
        await LiveActivityService.shared.update(
            state,
            staleDate: staleDate,
            alert: alert,
            sound: sound
        )

        scheduleBackgroundRefresh()
    }

    // MARK: - Background execution lease

    /// CapriCompanion's `beginBackgroundTaskWithName:expirationHandler:`.
    /// It buys a few minutes of execution after the app leaves the foreground,
    /// long enough to deliver the activity update and finish the in-flight
    /// network work that update represents.
    private func beginBackgroundLease(named name: String) {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.endBackgroundLease()
        }
    }

    private func endBackgroundLease() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - BGAppRefreshTask

    /// Registers the refresh handler. Must run before `didFinishLaunching`
    /// returns, which is why `start()` is called from the launch path and not
    /// lazily.
    private func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handleBackgroundRefresh(refresh)
        }
    }

    /// CapriCompanion's `IslandJokes.schedule()`. It asks iOS to wake the app
    /// roughly one heartbeat from now. iOS may delay it, so the stale date on
    /// the Live Activity is the real backstop.
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(heartbeatInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()

        let work = Task { await self.heartbeatTick() }
        task.expirationHandler = { work.cancel() }

        Task {
            // The heartbeat only pushes the stale date forward, so a
            // cancellation still counts as handled: the next scheduled refresh
            // retries it. Awaiting the result keeps the task open until then.
            _ = await work.result
            task.setTaskCompleted(success: true)
        }
    }
}

/// App group shared with the widget extension. CapriCompanion uses
/// `group.com.evoidk.capricompanion`; CapriGram gets its own so the two apps
/// never collide when both are installed.
enum AppGroup {
    static let identifier = "group.com.evoidk.caprigram"
}
