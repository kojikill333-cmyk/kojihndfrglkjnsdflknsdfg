import ActivityKit
import SwiftUI
import WidgetKit

/// The Dynamic Island UI for CapriGram.
///
/// The regions follow CapriCompanion's `CapriLiveActivityWidget`: the figure
/// on the leading side, the battery trailing, and the message along the
/// bottom. Two things are CapriGram's own.
///
/// The compact leading slot carries a live dot whenever the island is simply
/// showing that the client is running, so a glance tells "на связи" apart from
/// "пришло сообщение".
///
/// The bottom region grows a reply row when a message or mention is showing.
/// Quick replies are `Link`s into `tg://resolve`, which CapriGram already
/// handles; the widget extension itself never sends anything.
struct CapriGramLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CapriGramActivityAttributes.self) { context in
            LockScreenBanner(context: context)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandGlyph(mood: context.state.mood, size: 28)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.showBattery {
                        BatteryReading(state: context.state)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandBottom(state: context.state, name: context.attributes.constant.companionName)
                }
            } compactLeading: {
                CompactLeading(state: context.state)
            } compactTrailing: {
                CompactBattery(state: context.state)
            } minimal: {
                IslandGlyph(mood: context.state.mood, size: 14)
            }
            .widgetURL(chatURL(for: context.state))
            .keylineTint(IslandPalette.accent)
        }
    }

    /// Tapping the island opens the chat the notification came from, or the
    /// app itself when the island is only showing the online status.
    private func chatURL(for state: CapriGramActivityAttributes.ContentState) -> URL {
        state.peer.isEmpty ? CapriGramLinks.open : IslandReply.openChat(peer: state.peer)
    }
}

// MARK: - Expanded bottom

/// Message, and the reply buttons when there's a chat to answer.
private struct IslandBottom: View {
    let state: CapriGramActivityAttributes.ContentState
    let name: String

    private var settings: IslandSettings { IslandSettingsStore.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if state.online {
                    LiveDot()
                }
                Text(state.title.isEmpty ? name : state.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(state.message.isEmpty ? state.mood.caption : state.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)

            if canReply {
                ReplyRow(peer: state.peer, replies: settings.quickReplies)
            }
        }
        .padding(.horizontal, 4)
    }

    /// Replies only make sense for a real message, and only when the user left
    /// them switched on.
    private var canReply: Bool {
        settings.repliesEnabled && !state.peer.isEmpty && !state.online
    }
}

/// One button per quick reply, plus a button that opens the chat with an empty
/// field for anything longer.
private struct ReplyRow: View {
    let peer: String
    let replies: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(replies.prefix(3), id: \.self) { reply in
                Link(destination: IslandReply(peer: peer, text: reply).url) {
                    Text(reply)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(IslandPalette.accent.opacity(0.18), in: Capsule())
                }
            }
            Link(destination: IslandReply.openChat(peer: peer)) {
                Image(systemName: "keyboard")
                    .font(.caption2.weight(.semibold))
                    .padding(5)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
        }
    }
}

// MARK: - Lock Screen

/// The rectangular presentation iOS shows on the Lock Screen. Same three
/// things as CapriCompanion — glyph, message, battery — plus the live dot and
/// the same reply row the island has.
private struct LockScreenBanner: View {
    let context: ActivityViewContext<CapriGramActivityAttributes>

    private var state: CapriGramActivityAttributes.ContentState { context.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                IslandGlyph(mood: state.mood, size: 26)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if state.online { LiveDot() }
                        Text(state.title.isEmpty ? context.attributes.constant.companionName : state.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(state.message.isEmpty ? state.mood.caption : state.message)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if state.showBattery {
                    BatteryReading(state: state)
                }
            }

            if IslandSettingsStore.current.repliesEnabled && !state.peer.isEmpty && !state.online {
                ReplyRow(peer: state.peer, replies: IslandSettingsStore.current.quickReplies)
            }
        }
        .padding(12)
    }
}

// MARK: - Pieces

/// The small mark that says the client is alive. It's the only decoration on
/// the resting island, so it has to be readable at compact size.
private struct LiveDot: View {
    var body: some View {
        Circle()
            .fill(IslandPalette.live)
            .frame(width: 6, height: 6)
            .overlay(Circle().stroke(IslandPalette.live.opacity(0.4), lineWidth: 2).scaleEffect(1.8))
    }
}

/// Compact leading slot: the live dot while idle, the mood glyph when a
/// notification is up.
private struct CompactLeading: View {
    let state: CapriGramActivityAttributes.ContentState

    var body: some View {
        if state.online {
            HStack(spacing: 4) {
                LiveDot()
                Text("на связи")
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
        } else {
            IslandGlyph(mood: state.mood, size: 16)
        }
    }
}

/// Stand-in for CapriCompanion's `CapriFigureView`. The companion draws its
/// rigged character here; CapriGram uses the mood's symbol so the island still
/// reads at a glance in every region.
private struct IslandGlyph: View {
    let mood: IslandMood
    let size: CGFloat

    var body: some View {
        Image(systemName: mood.symbolName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch mood {
        case .batteryCritical: return .red
        case .batteryLow: return .orange
        case .charging: return .green
        case .phoneInteraction: return .green
        default: return IslandPalette.accent
        }
    }
}

/// CapriCompanion's expanded-trailing battery reading: percent plus a bolt
/// while charging.
private struct BatteryReading: View {
    let state: CapriGramActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 3) {
            if state.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.green)
            }
            if !state.boltOnly, let level = state.batteryLevel {
                Text("\(level)%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(level <= 20 && !state.isCharging ? .orange : .primary)
            }
        }
    }
}

/// The compact trailing slot. CapriCompanion shows just the number here,
/// because the compact island is only a few dozen points wide.
private struct CompactBattery: View {
    let state: CapriGramActivityAttributes.ContentState

    var body: some View {
        if state.isCharging && state.boltOnly {
            Image(systemName: "bolt.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.green)
        } else if let level = state.batteryLevel, state.showBattery {
            Text("\(level)%")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(state.isCharging ? .green : .primary)
        } else {
            Image(systemName: state.mood.symbolName)
                .font(.caption2)
        }
    }
}

/// The two colours the island uses. Kept in one place so the live dot and the
/// reply chips don't drift apart.
enum IslandPalette {
    static let accent = Color.cyan
    static let live = Color(red: 0.30, green: 0.85, blue: 0.55)
}

/// Deep links back into CapriGram. The app already claims the `telegram` and
/// `tg` schemes, so the island reuses them instead of registering a new one.
enum CapriGramLinks {
    static let open = URL(string: "tg://")!
}
