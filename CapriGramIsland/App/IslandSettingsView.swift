import SwiftUI

/// The island's settings, opened from inside CapriGram.
///
/// It's a sheet rather than a page buried in the client's own settings,
/// because the client's settings screens are compiled into TelegramUIFramework
/// and can't be extended from here. `CapriGramIsland.presentSettings()` finds
/// the topmost view controller and presents this over it.
struct IslandSettingsView: View {
    @State private var settings = IslandSettingsStore.current
    @State private var newReply = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    statusCard
                    notificationSection
                    replySection
                    backgroundSection
                    extraSection
                }
                .padding(16)
            }
            .background(IslandScreenPalette.background.ignoresSafeArea())
            .navigationTitle("Островок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: settings) { updated in
            IslandSettingsStore.current = updated
            apply(updated)
        }
    }

    // MARK: Status

    /// The one thing the screen leads with: is the client actually up.
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(settings.enabled ? IslandScreenPalette.live : IslandScreenPalette.dim)
                    .frame(width: 9, height: 9)
                Text(settings.enabled ? "CapriGram на связи" : "Островок выключен")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $settings.enabled)
                    .labelsHidden()
                    .tint(IslandScreenPalette.accent)
            }

            Text(settings.enabled
                 ? "Островок горит, пока клиент работает в фоне. Сверни CapriGram — он останется на месте."
                 : "Включи, чтобы клиент оставался запущенным и уведомления приходили на островок.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                IslandPreview(settings: settings)
                Button {
                    CapriGramIsland.previewNotification()
                } label: {
                    Label("Проверить", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(IslandScreenPalette.accent)
                .disabled(!settings.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IslandScreenPalette.card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Notifications

    private var notificationSection: some View {
        section("Что показывать") {
            row("Сообщения", "Приходят на островок, и на них можно ответить", $settings.showMessages)
            divider
            row("Упоминания", "Отдельным сигналом, чтобы не потеряться", $settings.showMentions)
            divider
            row("Звонки", "Островок держит звонок, пока не ответишь", $settings.showCalls)
            divider
            row("Батарея", "Процент на островке и предупреждение на 20% и 10%", $settings.showBattery)
            divider
            row("Статус «на связи»", "Зелёная точка, когда ничего не происходит", $settings.showOnlineStatus)
        }
    }

    // MARK: Replies

    private var replySection: some View {
        section("Ответы с островка") {
            row("Быстрые ответы", "Кнопки прямо на островке", $settings.repliesEnabled)

            if settings.repliesEnabled {
                divider
                VStack(alignment: .leading, spacing: 10) {
                    Text("Фразы")
                        .font(.subheadline.weight(.semibold))
                    repliesList
                    addReplyField
                    Text("Нажатие открывает чат и подставляет текст. CapriGram отправит его оттуда.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var repliesList: some View {
        VStack(spacing: 8) {
            ForEach(Array(settings.quickReplies.enumerated()), id: \.offset) { index, reply in
                HStack(spacing: 8) {
                    Text(reply)
                        .font(.subheadline)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(IslandScreenPalette.accent.opacity(0.16), in: Capsule())
                    Spacer()
                    stepButton("chevron.up", enabled: index > 0) { moveReply(from: index, by: -1) }
                    stepButton("chevron.down", enabled: index < settings.quickReplies.count - 1) {
                        moveReply(from: index, by: 1)
                    }
                    Button {
                        settings.quickReplies.remove(at: index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var addReplyField: some View {
        HStack(spacing: 8) {
            TextField("Новая фраза", text: $newReply)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit(addReply)
            Button("Добавить", action: addReply)
                .disabled(newReply.trimmingCharacters(in: .whitespaces).isEmpty
                          || settings.quickReplies.count >= 6)
        }
    }

    // MARK: Background

    private var backgroundSection: some View {
        section("Фон") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Держать уведомление")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(settings.notificationHoldSeconds)) с")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.notificationHoldSeconds, in: 10...120, step: 5)
                    .tint(IslandScreenPalette.accent)
            }
            divider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Проверять связь каждые")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(settings.heartbeatMinutes)) мин")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.heartbeatMinutes, in: 5...60, step: 5)
                    .tint(IslandScreenPalette.accent)
                Text("Как часто клиент подтверждает, что ещё работает, когда новых сообщений нет.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var extraSection: some View {
        section("Ещё") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    settings = IslandSettings()
                    IslandSettingsStore.current = settings
                    apply(settings)
                } label: {
                    Label("Вернуть стандартные настройки", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(IslandScreenPalette.accent)

                Text("Островок дублирует статус фонового запуска и помогает быстро отвечать без открытия чата, если для этого есть доступ к peer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IslandScreenPalette.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func row(_ title: String, _ detail: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .tint(IslandScreenPalette.accent)
    }

    private var divider: some View {
        Rectangle().fill(IslandScreenPalette.hairline).frame(height: 1)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(enabled ? .primary : IslandScreenPalette.dim)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: Actions

    private func addReply() {
        let text = newReply.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, settings.quickReplies.count < 6 else { return }
        settings.quickReplies.append(text)
        newReply = ""
    }

    private func moveReply(from index: Int, by offset: Int) {
        let destination = index + offset
        guard settings.quickReplies.indices.contains(destination) else { return }
        settings.quickReplies.swapAt(index, destination)
    }

    /// Pushes the change onto the live island immediately, so the switch and
    /// the sliders aren't waiting for the next message to take effect.
    private func apply(_ updated: IslandSettings) {
        if updated.enabled {
            CapriGramIsland.start()
        } else {
            CapriGramIsland.stop()
        }
    }
}

// MARK: - Preview

/// A small drawing of the compact island, so the switches above it have
/// something to point at. It isn't the real island — that only exists on a
/// device that supports Live Activities.
private struct IslandPreview: View {
    let settings: IslandSettings

    var body: some View {
        HStack(spacing: 8) {
            if settings.enabled && settings.showOnlineStatus {
                Circle().fill(IslandScreenPalette.live).frame(width: 7, height: 7)
                Text("на связи")
                    .font(.caption.weight(.medium))
            } else {
                Image(systemName: "message.fill")
                    .font(.caption)
                    .foregroundStyle(IslandScreenPalette.accent)
            }
            Spacer()
            if settings.showBattery {
                Text("76%")
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .frame(maxWidth: 230)
        .background(Color.black, in: Capsule())
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .opacity(settings.enabled ? 1 : 0.4)
    }
}

/// Colours for the screen. The island itself stays black, like the real
/// Dynamic Island; the screen behind it is a deep blue-black so the black
/// pill still reads as the object.
enum IslandScreenPalette {
    static let background = Color(red: 0.07, green: 0.09, blue: 0.13)
    static let card = Color(red: 0.12, green: 0.15, blue: 0.20)
    static let accent = Color(red: 0.36, green: 0.78, blue: 0.86)
    static let live = Color(red: 0.30, green: 0.85, blue: 0.55)
    static let dim = Color.white.opacity(0.25)
    static let hairline = Color.white.opacity(0.08)
}
