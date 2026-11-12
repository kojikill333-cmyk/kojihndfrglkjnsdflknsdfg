import Foundation
import UIKit

/// Reads the device battery the way CapriCompanion's `BatteryMonitor` does.
///
/// The companion treats battery as a first-class island event: its
/// `CompanionService.refreshIsland(battery:)` runs on every
/// `UIDevice.batteryStateDidChangeNotification` and rewrites the activity.
/// CapriGram shows the same reading in the compact trailing slot, and promotes
/// the island mood when the charge drops to low or critical — the two
/// thresholds CapriCompanion's `BatteryClassifier` uses.
struct BatterySnapshot {
    var level: Int?
    var isCharging: Bool

    /// A mood that should win over whatever the caller asked for, because the
    /// battery state matters more. `nil` means "leave the caller's mood alone".
    var moodOverride: IslandMood? {
        guard let level else { return nil }
        if isCharging { return nil }
        if level <= 10 { return .batteryCritical }
        if level <= 20 { return .batteryLow }
        return nil
    }

    static var current: BatterySnapshot {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        let raw = device.batteryLevel
        let level = raw < 0 ? nil : Int((raw * 100).rounded())
        let isCharging = device.batteryState == .charging || device.batteryState == .full
        return BatterySnapshot(level: level, isCharging: isCharging)
    }
}

/// Observes battery changes and refreshes the island, mirroring
/// `BatteryMonitor.start()` plus `CompanionService.refreshIsland(battery:)`.
final class BatteryMonitor {
    static let shared = BatteryMonitor()

    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        UIDevice.current.isBatteryMonitoringEnabled = true
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(batteryChanged),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(batteryChanged),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
    }

    func stop() {
        guard started else { return }
        started = false
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func batteryChanged() {
        let snapshot = BatterySnapshot.current
        let mood = snapshot.moodOverride ?? .idle
        let message: String
        if snapshot.isCharging {
            message = "Зарядка \(snapshot.level.map { "\($0)%" } ?? "")"
        } else if mood == .batteryCritical {
            message = "Батарея почти на нуле"
        } else if mood == .batteryLow {
            message = "Батарея садится"
        } else {
            message = "CapriGram на связи"
        }

        let notification = IslandNotification(
            kind: .battery,
            title: "CapriGram",
            body: message,
            // Only the threshold crossings make a sound, matching the
            // companion, which dings on low and critical but not on every
            // percent tick.
            soundName: snapshot.moodOverride == nil ? nil : "battery_low",
            mood: mood
        )
        IslandBackgroundKeeper.shared.present(notification)
    }
}
