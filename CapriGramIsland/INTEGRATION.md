# CapriGram Dynamic Island

Порт Dynamic Island из CapriCompanion. CapriGram в этом репозитории собран в
бинарный вид (`Payload/Swiftgram.app`, логика внутри `TelegramUIFramework`),
исходников клиента в дереве нет, поэтому остров добавлен отдельным модулем,
который подключается к приложению, а не переписывает его.

## Что именно взято из CapriCompanion

Разобрано по бинарнику `CapriCompanion.app` версии 0.2.5. Остров там — это
одна Live Activity, а не виджет и не аудио-сессия.

| В CapriCompanion | Где в бинарнике | Куда перенесено |
| --- | --- | --- |
| `LiveActivityService` | `LiveActivityService.swift` | `App/LiveActivityService.swift` |
| `start(with:staleDate:)` | символ `5start4with9staleDate` | `LiveActivityService.start` |
| `update(_:staleDate:alert:sound:)` | символ `6update_9staleDate5alert5sound` | `LiveActivityService.update` |
| `endAll()`, `current` | символы `6endAll`, `7current` | те же методы |
| `CapriActivityAttributes.ContentState` | поля `mood message batteryLevel isCharging showBattery revision pose boltOnly companionName` | `Shared/CapriGramActivityAttributes.swift` |
| `IslandMood` | 19 кейсов от `idle` до `phoneInteraction` | `IslandMood` |
| `CapriLiveActivityWidget` | `CapriWidgets.appex`, регионы leading/trailing/bottom, compact, minimal | `Widget/CapriGramLiveActivityWidget.swift` |
| `NSSupportsLiveActivities` | `Info.plist` компаньона | добавлен в `Swiftgram.app/Info.plist` |
| `beginBackgroundTaskWithName:expirationHandler:` | импорт в бинарнике | `IslandBackgroundKeeper.beginBackgroundLease` |
| `BGAppRefreshTask` `com.evoidk.capricompanion.joke` | `BGTaskSchedulerPermittedIdentifiers` | `com.evoidk.caprigram.island` |
| `BatteryMonitor` + `refreshIsland(battery:)` | `BatteryMonitor.swift`, `CompanionService` | `App/BatterySnapshot.swift` |
| `NotificationManager` | локальные уведомления и алерты острова | `IslandNotification` + `CapriGramIsland.handle` |

Поведение сохранено: активность одна, контент обновляется, а не создаётся
заново, `pushType` остаётся `nil` (компаньон тоже не использует push-обновления
ActivityKit), а алерт с заголовком, текстом и звуком уходит через
`AlertConfiguration` прямо в обновлении активности.

## Как остров держит клиент в фоне

Так же, как в CapriCompanion, тремя механизмами сразу.

1. Пока Live Activity активна, iOS считает приложение выполняющим живую задачу:
   его не замораживают как обычное приложение, и системе есть повод запустить
   его снова, чтобы обновить активность.
2. `staleDate` стоит на `heartbeatInterval` (15 минут) вперёд. Когда срок
   выходит, система помечает активность устаревшей и даёт приложению время
   обновиться. Это и есть «аренда», на которой держится фоновый режим.
3. `BGAppRefreshTask` с идентификатором `com.evoidk.caprigram.island` будит
   процесс по расписанию и двигает `staleDate` дальше, даже если новых
   сообщений не было. `beginBackgroundTask` закрывает дыру между уходом
   приложения в фон и доставкой обновления активности.

Существующие режимы CapriGram (`audio`, `fetch`, `location`,
`remote-notification`, `voip`, `processing`) не тронуты. Остров добавляет к ним
ещё одну причину оставаться запущенным.

## Уведомления

`CapriGramIsland.handle(_:)` принимает `IslandNotification` и поднимает остров
с алертом. Для клиента подготовлены три конструктора:

```swift
CapriGramIsland.handle(.message(from: name, text: text, peer: username))
CapriGramIsland.handle(.mention(from: name, text: text, peer: username))
CapriGramIsland.handle(.call(from: name))
```

Каждый вызов берёт фоновую задачу `caprigram.island.notification`, так что
клиент успевает забрать и подтвердить сообщение, пока остров его показывает.
Батарея обрабатывается отдельно: `BatteryMonitor` повторяет логику компаньона и
звучит только на порогах 20% и 10%, а не на каждом проценте.

Звуки ищутся по имени бандла, как `bundledSound(_:)` в компаньоне. Каталоги
`notification` и `island_alert` соответствуют файлам `notification.wav` и
`island_alert.wav` из CapriCompanion.

### Автоматический перехват уведомлений

`CapriGramNotificationBridge` оборачивает делегат `UNUserNotificationCenter` и
извлекает поля `from_id`, `text`, `title`, `call`, `mention` из payload. Хук
устанавливается в `+load` и не требует изменений в коде клиента: все
уведомления, доставленные через `UNUserNotificationCenter`, автоматически
попадают на остров, если их тип включён в настройках.

## Настройки островка

Доступны тремя способами:

1. **Кнопка в навигации настроек CapriGram**: `CapriGramIslandSettingsHook`
   оборачивает `viewWillAppear(_:)` на `PeerInfoScreenImpl` и добавляет
   `UIBarButtonItem` с иконкой `capsule.portrait.fill` в левую часть навбара.
2. **Deep link** `tg://caprigram/island`: `CapriGramIslandURLHook` оборачивает
   `scene(_:openURLContexts:)` на `SceneDelegate` и открывает настройки, если
   URL содержит `caprigram/island`.
3. **Tap на островке в статусе «на связи»**: островок, показывающий зелёную
   точку и надпись «CapriGram на связи», открывает настройки при тапе.

Экран `IslandSettingsView` — SwiftUI sheet с секциями:

- **Статус**: toggle включения островка, индикатор состояния (зелёная точка /
  серая), кнопка проверки (отправляет тестовое уведомление).
- **Что показывать**: toggle для сообщений, упоминаний, звонков, батареи,
  статуса «на связи».
- **Ответы с островка**: toggle для быстрых ответов, список из до 6 фраз с
  кнопками перемещения и удаления, поле добавления новой фразы.
- **Фон**: слайдеры для времени удержания уведомления (10–120 сек) и интервала
  heartbeat (5–60 мин).
- **Ещё**: кнопка сброса настроек на стандартные, описание.

Настройки хранятся в `IslandSettingsStore` (app group UserDefaults) и
применяются немедленно: изменение toggle вызывает `CapriGramIsland.start()`
или `.stop()`.

## Ответы через островок

При получении уведомления `IslandBackgroundKeeper` записывает `peer`, `title`,
`body` в `IslandPendingReplyStore`, и островок показывает до трёх кнопок с
фразами из `IslandSettings.quickReplies` плюс кнопку клавиатуры для
произвольного текста. Tap на кнопке открывает `tg://resolve?domain=<peer>&text=<text>`,
что отправляет клиент в чат с подставленным текстом.

Expanded region островка показывает:

- **Leading**: аватар настроения (SF Symbol из `IslandMood`) или зелёная точка
  в режиме покоя.
- **Trailing**: уровень батареи (процент + болт при зарядке).
- **Bottom**: заголовок, текст сообщения, кнопки ответов.

Lock screen баннер повторяет структуру островка и тоже поддерживает ответы.

## Сборка

На машине, где лежит этот репозиторий, нет Xcode и Swift, поэтому модуль
проверен чтением, а не сборкой. Собирать на Mac:

```bash
cd CapriGram/CapriGramIsland
xcodebuild -scheme CapriGramIslandKit -destination 'generic/platform=iOS' build
```

Дальше один шаг, который делается в проекте клиента, потому что его исходников
здесь нет: добавить `CapriGramIslandKit.framework` в таргет приложения и
встроить `CapriGramIsland.appex` в `PlugIns`. Загрузчик на Objective-C
(`+load` в `CapriGramIslandLoader.m`) сам подписывается на жизненный цикл
приложения и устанавливает хуки: делегат клиента, обработчик уведомлений и
навигационные контроллеры трогать не нужно.

`Info.plist` приложения уже обновлён: включены `NSSupportsLiveActivities` и
`NSSupportsLiveActivitiesFrequentUpdates`, а `com.evoidk.caprigram.island`
добавлен в `BGTaskSchedulerPermittedIdentifiers`. Рядом лежит
`Info.plist.bak` с прежним содержимым.

Нужен capability App Groups с группой `group.com.evoidk.caprigram` и на
приложении, и на расширении. Файл `CapriGramIsland.entitlements` задаёт её для
обоих таргетов.

## Что сознательно не переносилось

Реакции, шутки, будильник и риг персонажа CapriCompanion к клиенту CapriGram
отношения не имеют, поэтому в модуль не вошли. В слотах, где компаньон рисует
фигуру, CapriGram показывает SF Symbol настроения: отдельных ассетов персонажа
у клиента нет.
