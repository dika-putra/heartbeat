# Heartbeat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Heartbeat, a macOS menu bar app that fires a replaceable notification (sound + message) at a configurable interval, in Normal or Urgent mode, only during configurable active hours.

**Architecture:** Pure Swift Package Manager executable (no Xcode project, no third-party dependencies). AppKit `NSStatusItem`/`NSMenu` for UI, `DispatchSourceTimer` for scheduling, `UNUserNotificationCenter` for notifications, `SMAppService` for login item, `afconvert` (macOS built-in CLI) for custom sound conversion. Core scheduling/business logic is isolated into small, clock-injectable, side-effect-free types so it can be unit tested without a real timer or real notification center.

**Tech Stack:** Swift 5.9+, Swift Package Manager, AppKit, UserNotifications, ServiceManagement, AVFoundation (duration probing only), XCTest. macOS 13+ (Ventura) minimum, required by `SMAppService`.

**Spec:** [docs/superpowers/specs/2026-09-29-heartbeat-design.md](../specs/2026-09-29-heartbeat-design.md)

## Global Constraints

- macOS 13.0+ only (`SMAppService` requires it) — set in `Package.swift` platforms.
- No third-party dependencies — stdlib + Apple frameworks only.
- App has no dock icon / no window: `LSUIElement = true` in `Info.plist`, `NSApp.setActivationPolicy(.accessory)`.
- Notification identifier is always the fixed string `"heartbeat-reminder"` — new requests replace old ones, never stack.
- Custom notification sound files must be `.aiff`, `.wav`, or `.caf`, duration ≤ 30 seconds; anything else is converted to `.caf` via `/usr/bin/afconvert` or rejected.
- Default settings: mode `normal`, normal interval 30 min, urgent interval 10 min, active hours 08:00–17:00, message `"Waktunya cek kerjaanmu!"`, sound `"Glass"`, launch at login `true`.
- Menu bar icon uses SF Symbols only, no custom image assets required for v1: `waveform.path.ecg` (normal), a filled/urgent variant, and an outline "paused" variant.

---

## File Structure

```
heartbeat/
  Package.swift
  Sources/Heartbeat/
    main.swift                # entry point, NSApplication bootstrap
    AppDelegate.swift          # NSStatusItem + NSMenu wiring, glues everything together
    ActiveHours.swift          # pure value type: is a given Date inside the configured window
    SchedulerSettings.swift    # pure value types: ReminderMode, SchedulerSettings
    ReminderScheduler.swift    # timer-driving class, injectable Clock, no I/O
    HeartbeatSettings.swift    # Codable persisted settings model
    SettingsStore.swift        # UserDefaults-backed load/save
    NotificationManager.swift  # builds + fires UNNotificationRequest
    SoundConverter.swift       # converts/validates custom sound files
    LoginItemManager.swift     # SMAppService wrapper
  Tests/HeartbeatTests/
    ActiveHoursTests.swift
    ReminderSchedulerTests.swift
    SettingsStoreTests.swift
    NotificationManagerTests.swift
    SoundConverterTests.swift
  Resources/Info.plist
  scripts/build-app.sh
  README.md
```

`AppDelegate` owns menu construction directly instead of a separate `MenuBuilder` type — the menu is one cohesive unit of UI wiring with no independent logic worth testing in isolation, so splitting it into another file would just be an extra hop with no reuse benefit.

---

### Task 1: Project scaffold — buildable, runnable skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/Heartbeat/main.swift`
- Create: `Sources/Heartbeat/AppDelegate.swift`
- Create: `Tests/HeartbeatTests/ScaffoldTests.swift`

**Interfaces:**
- Produces: `AppDelegate` (NSObject, NSApplicationDelegate) — later tasks add properties/methods to this same class.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Heartbeat",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Heartbeat",
            path: "Sources/Heartbeat"
        ),
        .testTarget(
            name: "HeartbeatTests",
            dependencies: ["Heartbeat"],
            path: "Tests/HeartbeatTests"
        )
    ]
)
```

- [ ] **Step 2: Write a minimal `AppDelegate`**

```swift
// Sources/Heartbeat/AppDelegate.swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Heartbeat")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 3: Write `main.swift`**

```swift
// Sources/Heartbeat/main.swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 4: Write a placeholder test so the test target builds**

```swift
// Tests/HeartbeatTests/ScaffoldTests.swift
import XCTest
@testable import Heartbeat

final class ScaffoldTests: XCTestCase {
    func test_appDelegate_canBeInstantiated() {
        let delegate = AppDelegate()
        XCTAssertNotNil(delegate)
    }
}
```

- [ ] **Step 5: Build and run manually**

Run: `swift build`
Expected: builds with no errors.

Run: `swift run` (then check the menu bar for a pulse icon, click it, click Quit)
Expected: icon appears in the menu bar, Quit menu item terminates the app.

- [ ] **Step 6: Run tests**

Run: `swift test`
Expected: `test_appDelegate_canBeInstantiated` PASSES.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: scaffold Heartbeat menu bar app skeleton"
```

---

### Task 2: Active hours + scheduler settings (pure value types)

**Files:**
- Create: `Sources/Heartbeat/ActiveHours.swift`
- Create: `Sources/Heartbeat/SchedulerSettings.swift`
- Test: `Tests/HeartbeatTests/ActiveHoursTests.swift`

**Interfaces:**
- Produces: `struct ActiveHours { let startHour, startMinute, endHour, endMinute: Int; func contains(_ date: Date, calendar: Calendar = .current) -> Bool }`
- Produces: `enum ReminderMode: String, Codable { case normal, urgent }`
- Produces: `struct SchedulerSettings { var mode: ReminderMode; var normalIntervalMinutes: Int; var urgentIntervalMinutes: Int; var activeHours: ActiveHours; var currentIntervalSeconds: TimeInterval { get } }`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/HeartbeatTests/ActiveHoursTests.swift
import XCTest
@testable import Heartbeat

final class ActiveHoursTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 29
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    func test_contains_returnsTrue_withinRange() {
        let hours = ActiveHours(startHour: 8, startMinute: 0, endHour: 17, endMinute: 0)
        XCTAssertTrue(hours.contains(date(hour: 12, minute: 30), calendar: calendar))
    }

    func test_contains_returnsFalse_beforeStart() {
        let hours = ActiveHours(startHour: 8, startMinute: 0, endHour: 17, endMinute: 0)
        XCTAssertFalse(hours.contains(date(hour: 7, minute: 59), calendar: calendar))
    }

    func test_contains_returnsFalse_atOrAfterEnd() {
        let hours = ActiveHours(startHour: 8, startMinute: 0, endHour: 17, endMinute: 0)
        XCTAssertFalse(hours.contains(date(hour: 17, minute: 0), calendar: calendar))
    }

    func test_currentIntervalSeconds_usesNormalInterval_inNormalMode() {
        let settings = SchedulerSettings(
            mode: .normal,
            normalIntervalMinutes: 30,
            urgentIntervalMinutes: 10,
            activeHours: ActiveHours(startHour: 8, startMinute: 0, endHour: 17, endMinute: 0)
        )
        XCTAssertEqual(settings.currentIntervalSeconds, 30 * 60)
    }

    func test_currentIntervalSeconds_usesUrgentInterval_inUrgentMode() {
        let settings = SchedulerSettings(
            mode: .urgent,
            normalIntervalMinutes: 30,
            urgentIntervalMinutes: 10,
            activeHours: ActiveHours(startHour: 8, startMinute: 0, endHour: 17, endMinute: 0)
        )
        XCTAssertEqual(settings.currentIntervalSeconds, 10 * 60)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ActiveHoursTests`
Expected: FAIL — `ActiveHours` / `SchedulerSettings` / `ReminderMode` not found.

- [ ] **Step 3: Write `ActiveHours.swift`**

```swift
// Sources/Heartbeat/ActiveHours.swift
import Foundation

struct ActiveHours {
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return false }
        let minutesNow = hour * 60 + minute
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute
        return minutesNow >= startMinutes && minutesNow < endMinutes
    }
}
```

- [ ] **Step 4: Write `SchedulerSettings.swift`**

```swift
// Sources/Heartbeat/SchedulerSettings.swift
import Foundation

enum ReminderMode: String, Codable {
    case normal
    case urgent
}

struct SchedulerSettings {
    var mode: ReminderMode
    var normalIntervalMinutes: Int
    var urgentIntervalMinutes: Int
    var activeHours: ActiveHours

    var currentIntervalSeconds: TimeInterval {
        let minutes = mode == .normal ? normalIntervalMinutes : urgentIntervalMinutes
        return TimeInterval(minutes * 60)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ActiveHoursTests`
Expected: all 5 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Heartbeat/ActiveHours.swift Sources/Heartbeat/SchedulerSettings.swift Tests/HeartbeatTests/ActiveHoursTests.swift
git commit -m "feat: add ActiveHours and SchedulerSettings value types"
```

---

### Task 3: ReminderScheduler (core timer logic, fake-clock testable)

**Files:**
- Create: `Sources/Heartbeat/ReminderScheduler.swift`
- Test: `Tests/HeartbeatTests/ReminderSchedulerTests.swift`

**Interfaces:**
- Consumes: `SchedulerSettings`, `ActiveHours.contains(_:calendar:)` from Task 2.
- Produces: `protocol Clock { func now() -> Date }`, `struct SystemClock: Clock`, `final class ReminderScheduler` with:
  - `init(settings: SchedulerSettings, clock: Clock = SystemClock())`
  - `enum SchedulerState { case activeNormal, activeUrgent, paused }`
  - `func currentState() -> SchedulerState`
  - `func reconfigure(_ newSettings: SchedulerSettings)`
  - `func tick()` — calls `onStateChange?(SchedulerState)` then, only if not paused, calls `onFire?()`
  - `var onFire: (() -> Void)?`
  - `var onStateChange: ((SchedulerState) -> Void)?`
  - `func start()` / `func stop()` — real `DispatchSourceTimer` wiring, calls `tick()` on schedule (not unit tested; exercised manually in Task 8).

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/HeartbeatTests/ReminderSchedulerTests.swift
import XCTest
@testable import Heartbeat

private final class FakeClock: Clock {
    var fixedDate: Date
    init(_ date: Date) { fixedDate = date }
    func now() -> Date { fixedDate }
}

final class ReminderSchedulerTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 29
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func makeSettings(mode: ReminderMode) -> SchedulerSettings {
        SchedulerSettings(
            mode: mode,
            normalIntervalMinutes: 30,
            urgentIntervalMinutes: 10,
            activeHours: ActiveHours(startHour: 8, startMinute: 0, endHour: 17, endMinute: 0)
        )
    }

    func test_currentState_isPaused_outsideActiveHours() {
        let clock = FakeClock(date(hour: 20, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal), clock: clock)
        XCTAssertEqual(scheduler.currentState(), .paused)
    }

    func test_currentState_isActiveNormal_insideActiveHoursNormalMode() {
        let clock = FakeClock(date(hour: 12, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal), clock: clock)
        XCTAssertEqual(scheduler.currentState(), .activeNormal)
    }

    func test_currentState_isActiveUrgent_insideActiveHoursUrgentMode() {
        let clock = FakeClock(date(hour: 12, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .urgent), clock: clock)
        XCTAssertEqual(scheduler.currentState(), .activeUrgent)
    }

    func test_tick_firesOnFire_insideActiveHours() {
        let clock = FakeClock(date(hour: 12, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal), clock: clock)
        var fired = false
        scheduler.onFire = { fired = true }
        scheduler.tick()
        XCTAssertTrue(fired)
    }

    func test_tick_doesNotFire_outsideActiveHours() {
        let clock = FakeClock(date(hour: 20, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal), clock: clock)
        var fired = false
        scheduler.onFire = { fired = true }
        scheduler.tick()
        XCTAssertFalse(fired)
    }

    func test_tick_reportsStateChange() {
        let clock = FakeClock(date(hour: 20, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal), clock: clock)
        var reportedState: ReminderScheduler.SchedulerState?
        scheduler.onStateChange = { reportedState = $0 }
        scheduler.tick()
        XCTAssertEqual(reportedState, .paused)
    }

    func test_reconfigure_changesCurrentState() {
        let clock = FakeClock(date(hour: 12, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal), clock: clock)
        XCTAssertEqual(scheduler.currentState(), .activeNormal)
        scheduler.reconfigure(makeSettings(mode: .urgent))
        XCTAssertEqual(scheduler.currentState(), .activeUrgent)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ReminderSchedulerTests`
Expected: FAIL — `Clock` / `ReminderScheduler` not found.

- [ ] **Step 3: Write `ReminderScheduler.swift`**

```swift
// Sources/Heartbeat/ReminderScheduler.swift
import Foundation

protocol Clock {
    func now() -> Date
}

struct SystemClock: Clock {
    func now() -> Date { Date() }
}

final class ReminderScheduler {
    enum SchedulerState {
        case activeNormal
        case activeUrgent
        case paused
    }

    var onFire: (() -> Void)?
    var onStateChange: ((SchedulerState) -> Void)?

    private let clock: Clock
    private var settings: SchedulerSettings
    private var timer: DispatchSourceTimer?

    init(settings: SchedulerSettings, clock: Clock = SystemClock()) {
        self.settings = settings
        self.clock = clock
    }

    func currentState() -> SchedulerState {
        guard settings.activeHours.contains(clock.now()) else { return .paused }
        return settings.mode == .normal ? .activeNormal : .activeUrgent
    }

    func reconfigure(_ newSettings: SchedulerSettings) {
        settings = newSettings
        if timer != nil {
            stop()
            start()
        }
    }

    func tick() {
        let state = currentState()
        onStateChange?(state)
        guard state != .paused else { return }
        onFire?()
    }

    func start() {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + settings.currentIntervalSeconds, repeating: settings.currentIntervalSeconds)
        source.setEventHandler { [weak self] in self?.tick() }
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}

extension ReminderScheduler.SchedulerState: Equatable {}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ReminderSchedulerTests`
Expected: all 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Heartbeat/ReminderScheduler.swift Tests/HeartbeatTests/ReminderSchedulerTests.swift
git commit -m "feat: add ReminderScheduler with fake-clock-testable core logic"
```

---

### Task 4: Persisted settings (HeartbeatSettings + SettingsStore)

**Files:**
- Create: `Sources/Heartbeat/HeartbeatSettings.swift`
- Create: `Sources/Heartbeat/SettingsStore.swift`
- Test: `Tests/HeartbeatTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `ReminderMode` from Task 2.
- Produces: `struct HeartbeatSettings: Codable, Equatable` with fields `mode, normalIntervalMinutes, urgentIntervalMinutes, activeHoursStartHour, activeHoursStartMinute, activeHoursEndHour, activeHoursEndMinute, message, soundName, launchAtLogin`, plus `static let default`.
- Produces: `final class SettingsStore { init(defaults: UserDefaults = .standard); func load() -> HeartbeatSettings; func save(_ settings: HeartbeatSettings) }`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/HeartbeatTests/SettingsStoreTests.swift
import XCTest
@testable import Heartbeat

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "com.heartbeat.tests.settingsstore"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_load_returnsDefault_whenNothingSaved() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), HeartbeatSettings.default)
    }

    func test_save_thenLoad_roundTrips() {
        let store = SettingsStore(defaults: defaults)
        var settings = HeartbeatSettings.default
        settings.mode = .urgent
        settings.message = "Custom message"
        settings.urgentIntervalMinutes = 5

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SettingsStoreTests`
Expected: FAIL — `HeartbeatSettings` / `SettingsStore` not found.

- [ ] **Step 3: Write `HeartbeatSettings.swift`**

```swift
// Sources/Heartbeat/HeartbeatSettings.swift
import Foundation

struct HeartbeatSettings: Codable, Equatable {
    var mode: ReminderMode
    var normalIntervalMinutes: Int
    var urgentIntervalMinutes: Int
    var activeHoursStartHour: Int
    var activeHoursStartMinute: Int
    var activeHoursEndHour: Int
    var activeHoursEndMinute: Int
    var message: String
    var soundName: String
    var launchAtLogin: Bool

    static let `default` = HeartbeatSettings(
        mode: .normal,
        normalIntervalMinutes: 30,
        urgentIntervalMinutes: 10,
        activeHoursStartHour: 8,
        activeHoursStartMinute: 0,
        activeHoursEndHour: 17,
        activeHoursEndMinute: 0,
        message: "Waktunya cek kerjaanmu!",
        soundName: "Glass",
        launchAtLogin: true
    )

    var activeHours: ActiveHours {
        ActiveHours(
            startHour: activeHoursStartHour,
            startMinute: activeHoursStartMinute,
            endHour: activeHoursEndHour,
            endMinute: activeHoursEndMinute
        )
    }

    var schedulerSettings: SchedulerSettings {
        SchedulerSettings(
            mode: mode,
            normalIntervalMinutes: normalIntervalMinutes,
            urgentIntervalMinutes: urgentIntervalMinutes,
            activeHours: activeHours
        )
    }
}
```

- [ ] **Step 4: Write `SettingsStore.swift`**

```swift
// Sources/Heartbeat/SettingsStore.swift
import Foundation

final class SettingsStore {
    private static let key = "com.heartbeat.settings"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> HeartbeatSettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(HeartbeatSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(_ settings: HeartbeatSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SettingsStoreTests`
Expected: both tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Heartbeat/HeartbeatSettings.swift Sources/Heartbeat/SettingsStore.swift Tests/HeartbeatTests/SettingsStoreTests.swift
git commit -m "feat: add HeartbeatSettings model and UserDefaults-backed SettingsStore"
```

---

### Task 5: NotificationManager (replaceable notification requests)

**Files:**
- Create: `Sources/Heartbeat/NotificationManager.swift`
- Test: `Tests/HeartbeatTests/NotificationManagerTests.swift`

**Interfaces:**
- Produces: `final class NotificationManager` with:
  - `static let reminderIdentifier = "heartbeat-reminder"`
  - `func makeRequest(message: String, soundName: String?) -> UNNotificationRequest` (pure, testable)
  - `func requestAuthorization(completion: @escaping (Bool) -> Void)` (side-effecting, not unit tested)
  - `func fire(message: String, soundName: String?)` (side-effecting: builds via `makeRequest` and calls `UNUserNotificationCenter.current().add(request)`, not unit tested)

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/HeartbeatTests/NotificationManagerTests.swift
import XCTest
import UserNotifications
@testable import Heartbeat

final class NotificationManagerTests: XCTestCase {
    func test_makeRequest_usesFixedIdentifier() {
        let manager = NotificationManager()
        let request = manager.makeRequest(message: "Cek kerjaan", soundName: nil)
        XCTAssertEqual(request.identifier, NotificationManager.reminderIdentifier)
    }

    func test_makeRequest_setsBodyToMessage() {
        let manager = NotificationManager()
        let request = manager.makeRequest(message: "Cek kerjaan", soundName: nil)
        XCTAssertEqual(request.content.body, "Cek kerjaan")
    }

    func test_makeRequest_usesDefaultSound_whenSoundNameIsNil() {
        let manager = NotificationManager()
        let request = manager.makeRequest(message: "Cek kerjaan", soundName: nil)
        XCTAssertEqual(request.content.sound, .default)
    }

    func test_makeRequest_usesNamedSound_whenSoundNameProvided() {
        let manager = NotificationManager()
        let request = manager.makeRequest(message: "Cek kerjaan", soundName: "Glass")
        XCTAssertEqual(request.content.sound, UNNotificationSound(named: UNNotificationSoundName("Glass")))
    }

    func test_makeRequest_hasNilTrigger_forImmediateDelivery() {
        let manager = NotificationManager()
        let request = manager.makeRequest(message: "Cek kerjaan", soundName: nil)
        XCTAssertNil(request.trigger)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NotificationManagerTests`
Expected: FAIL — `NotificationManager` not found.

- [ ] **Step 3: Write `NotificationManager.swift`**

```swift
// Sources/Heartbeat/NotificationManager.swift
import UserNotifications

final class NotificationManager {
    static let reminderIdentifier = "heartbeat-reminder"

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func makeRequest(message: String, soundName: String?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Heartbeat"
        content.body = message
        if let soundName {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
        } else {
            content.sound = .default
        }
        return UNNotificationRequest(identifier: Self.reminderIdentifier, content: content, trigger: nil)
    }

    func fire(message: String, soundName: String?) {
        let request = makeRequest(message: message, soundName: soundName)
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NotificationManagerTests`
Expected: all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Heartbeat/NotificationManager.swift Tests/HeartbeatTests/NotificationManagerTests.swift
git commit -m "feat: add NotificationManager with fixed-identifier replace semantics"
```

---

### Task 6: SoundConverter (custom sound validation + conversion)

**Files:**
- Create: `Sources/Heartbeat/SoundConverter.swift`
- Test: `Tests/HeartbeatTests/SoundConverterTests.swift`

**Interfaces:**
- Produces: `enum SoundConverterError: Error, Equatable { case tooLong, conversionFailed }`
- Produces: `struct SoundConverter` with injectable `durationProvider: (URL) -> Double` and `processRunner: (URL, [String]) throws -> Int32`, and `func convertToCaf(sourceURL: URL, destinationDirectory: URL) throws -> URL`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/HeartbeatTests/SoundConverterTests.swift
import XCTest
@testable import Heartbeat

final class SoundConverterTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func test_convertToCaf_throwsTooLong_whenDurationExceeds30Seconds() {
        var converter = SoundConverter()
        converter.durationProvider = { _ in 45.0 }
        converter.processRunner = { _, _ in 0 }

        XCTAssertThrowsError(
            try converter.convertToCaf(sourceURL: URL(fileURLWithPath: "/tmp/sound.mp3"), destinationDirectory: tempDirectory)
        ) { error in
            XCTAssertEqual(error as? SoundConverterError, .tooLong)
        }
    }

    func test_convertToCaf_throwsConversionFailed_whenProcessExitsNonZero() {
        var converter = SoundConverter()
        converter.durationProvider = { _ in 10.0 }
        converter.processRunner = { _, _ in 1 }

        XCTAssertThrowsError(
            try converter.convertToCaf(sourceURL: URL(fileURLWithPath: "/tmp/sound.mp3"), destinationDirectory: tempDirectory)
        ) { error in
            XCTAssertEqual(error as? SoundConverterError, .conversionFailed)
        }
    }

    func test_convertToCaf_returnsCafDestinationURL_onSuccess() throws {
        var converter = SoundConverter()
        converter.durationProvider = { _ in 10.0 }
        converter.processRunner = { _, _ in 0 }

        let result = try converter.convertToCaf(
            sourceURL: URL(fileURLWithPath: "/tmp/sound.mp3"),
            destinationDirectory: tempDirectory
        )

        XCTAssertEqual(result, tempDirectory.appendingPathComponent("sound.caf"))
    }

    func test_convertToCaf_createsDestinationDirectory_ifMissing() throws {
        var converter = SoundConverter()
        converter.durationProvider = { _ in 10.0 }
        converter.processRunner = { _, _ in 0 }

        _ = try converter.convertToCaf(
            sourceURL: URL(fileURLWithPath: "/tmp/sound.mp3"),
            destinationDirectory: tempDirectory
        )

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: tempDirectory.path, isDirectory: &isDirectory)
        XCTAssertTrue(exists && isDirectory.boolValue)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SoundConverterTests`
Expected: FAIL — `SoundConverter` / `SoundConverterError` not found.

- [ ] **Step 3: Write `SoundConverter.swift`**

```swift
// Sources/Heartbeat/SoundConverter.swift
import AVFoundation
import Foundation

enum SoundConverterError: Error, Equatable {
    case tooLong
    case conversionFailed
}

struct SoundConverter {
    static let maxDurationSeconds: Double = 30

    var durationProvider: (URL) -> Double = { url in
        let seconds = AVURLAsset(url: url).duration.seconds
        return seconds.isFinite ? seconds : .infinity
    }

    var processRunner: (URL, [String]) throws -> Int32 = { executable, arguments in
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func convertToCaf(sourceURL: URL, destinationDirectory: URL) throws -> URL {
        let duration = durationProvider(sourceURL)
        guard duration.isFinite, duration <= Self.maxDurationSeconds else {
            throw SoundConverterError.tooLong
        }

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let destinationURL = destinationDirectory
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("caf")

        let status = try processRunner(
            URL(fileURLWithPath: "/usr/bin/afconvert"),
            ["-f", "caff", "-d", "LEI16", sourceURL.path, destinationURL.path]
        )
        guard status == 0 else { throw SoundConverterError.conversionFailed }

        return destinationURL
    }
}
```

`durationProvider` and `processRunner` default to the real `AVFoundation`/`Process` calls above but are injectable `var`s, so the tests in Step 1 override them with fakes and never touch a real audio file or spawn `afconvert`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SoundConverterTests`
Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Heartbeat/SoundConverter.swift Tests/HeartbeatTests/SoundConverterTests.swift
git commit -m "feat: add SoundConverter for custom notification sound files"
```

---

### Task 7: LoginItemManager (SMAppService wrapper)

**Files:**
- Create: `Sources/Heartbeat/LoginItemManager.swift`

**Interfaces:**
- Produces: `final class LoginItemManager { func isRegistered() -> Bool; func setEnabled(_ enabled: Bool) }`

No automated test: `SMAppService` talks to a real system service (`launchd`/System Settings login items) with no fake-able seam and no meaningful behavior in a CI sandbox. Verified manually in Task 8's manual test pass instead.

- [ ] **Step 1: Write `LoginItemManager.swift`**

```swift
// Sources/Heartbeat/LoginItemManager.swift
import ServiceManagement

final class LoginItemManager {
    func isRegistered() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if !isRegistered() {
                    try SMAppService.mainApp.register()
                }
            } else {
                if isRegistered() {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // ponytail: best-effort; SMAppService surfaces its own errors via
            // System Settings if registration is blocked, nothing actionable
            // for us to do beyond leaving the checkbox reflecting real status.
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Heartbeat/LoginItemManager.swift
git commit -m "feat: add LoginItemManager wrapping SMAppService"
```

---

### Task 8: AppDelegate wiring — full menu, icon states, live behavior

**Files:**
- Modify: `Sources/Heartbeat/AppDelegate.swift` (replaces the Task 1 skeleton entirely)

**Interfaces:**
- Consumes: `ReminderScheduler`, `SchedulerSettings`, `ActiveHours` (Task 2/3), `SettingsStore`, `HeartbeatSettings` (Task 4), `NotificationManager` (Task 5), `SoundConverter`, `SoundConverterError` (Task 6), `LoginItemManager` (Task 7).
- Produces: nothing consumed by later tasks — this is the top of the dependency graph.

No automated tests: this file is pure AppKit event wiring (status item, menu items, panels) with no business logic left to isolate — all decision logic already lives in the tested types above. Verified with the manual test pass in Step 2.

- [ ] **Step 1: Replace `AppDelegate.swift`**

```swift
// Sources/Heartbeat/AppDelegate.swift
import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let settingsStore = SettingsStore()
    private let notificationManager = NotificationManager()
    private let loginItemManager = LoginItemManager()
    private var scheduler: ReminderScheduler!
    private var settings: HeartbeatSettings!

    private let systemSoundNames = ["Basso", "Blow", "Glass", "Ping", "Pop", "Submarine"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = settingsStore.load()

        if settings.launchAtLogin {
            loginItemManager.setEnabled(true)
        }

        scheduler = ReminderScheduler(settings: settings.schedulerSettings)
        scheduler.onFire = { [weak self] in self?.fireReminder() }
        scheduler.onStateChange = { [weak self] state in self?.updateIcon(for: state) }

        notificationManager.requestAuthorization { _ in }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(for: scheduler.currentState())
        rebuildMenu()

        scheduler.start()
    }

    // MARK: - Reminder firing

    private func fireReminder() {
        notificationManager.fire(message: settings.message, soundName: settings.soundName)
    }

    // MARK: - Icon

    private func updateIcon(for state: ReminderScheduler.SchedulerState) {
        let symbolName: String
        switch state {
        case .activeNormal: symbolName = "waveform.path.ecg"
        case .activeUrgent: symbolName = "waveform.path.ecg.rectangle.fill"
        case .paused: symbolName = "waveform.path.ecg.rectangle"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Heartbeat")
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        let statusLabel = settings.mode == .normal ? "Active (Normal)" : "Active (Urgent)"
        menu.addItem(NSMenuItem(title: "● \(statusLabel)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        menu.addItem(makeModeItem(title: "Normal mode", mode: .normal))
        menu.addItem(makeModeItem(title: "Urgent mode", mode: .urgent))
        menu.addItem(.separator())

        menu.addItem(makeIntervalItem(
            title: "Normal interval: \(settings.normalIntervalMinutes) min",
            currentMinutes: settings.normalIntervalMinutes,
            action: #selector(setNormalInterval(_:))
        ))
        menu.addItem(makeIntervalItem(
            title: "Urgent interval: \(settings.urgentIntervalMinutes) min",
            currentMinutes: settings.urgentIntervalMinutes,
            action: #selector(setUrgentInterval(_:))
        ))
        menu.addItem(.separator())

        let activeHoursItem = NSMenuItem(
            title: "Active hours: \(formattedTime(settings.activeHoursStartHour, settings.activeHoursStartMinute))–\(formattedTime(settings.activeHoursEndHour, settings.activeHoursEndMinute))",
            action: #selector(editActiveHours),
            keyEquivalent: ""
        )
        activeHoursItem.target = self
        menu.addItem(activeHoursItem)
        menu.addItem(.separator())

        let messageItem = NSMenuItem(title: "Edit message…", action: #selector(editMessage), keyEquivalent: "")
        messageItem.target = self
        menu.addItem(messageItem)
        menu.addItem(.separator())

        menu.addItem(makeSoundSubmenu())
        menu.addItem(.separator())

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = settings.launchAtLogin ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func makeModeItem(title: String, mode: ReminderMode) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(setMode(_:)), keyEquivalent: "")
        item.target = self
        item.state = settings.mode == mode ? .on : .off
        item.representedObject = mode
        return item
    }

    private func makeIntervalItem(title: String, currentMinutes: Int, action: Selector) -> NSMenuItem {
        let submenu = NSMenu()
        for minutes in [5, 10, 15, 20, 30, 45, 60, 90, 120] {
            let item = NSMenuItem(title: "\(minutes) min", action: action, keyEquivalent: "")
            item.target = self
            item.state = minutes == currentMinutes ? .on : .off
            item.representedObject = minutes
            submenu.addItem(item)
        }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private func makeSoundSubmenu() -> NSMenuItem {
        let submenu = NSMenu()
        for name in systemSoundNames {
            let item = NSMenuItem(title: name, action: #selector(setSystemSound(_:)), keyEquivalent: "")
            item.target = self
            item.state = settings.soundName == name ? .on : .off
            item.representedObject = name
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let customItem = NSMenuItem(title: "Choose custom file…", action: #selector(chooseCustomSound), keyEquivalent: "")
        customItem.target = self
        submenu.addItem(customItem)

        let parent = NSMenuItem(title: "Sound: \(settings.soundName)", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private func formattedTime(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    // MARK: - Actions

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? ReminderMode else { return }
        settings.mode = mode
        persistAndReconfigure()
    }

    @objc private func setNormalInterval(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        settings.normalIntervalMinutes = minutes
        persistAndReconfigure()
    }

    @objc private func setUrgentInterval(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        settings.urgentIntervalMinutes = minutes
        persistAndReconfigure()
    }

    @objc private func setSystemSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        settings.soundName = name
        persistAndReconfigure()
    }

    @objc private func chooseCustomSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        let destinationDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Heartbeat/sounds", isDirectory: true)

        do {
            let convertedURL = try SoundConverter().convertToCaf(sourceURL: sourceURL, destinationDirectory: destinationDirectory)
            settings.soundName = convertedURL.deletingPathExtension().lastPathComponent
            persistAndReconfigure()
        } catch SoundConverterError.tooLong {
            presentAlert(message: "That sound is longer than 30 seconds. Choose a shorter clip.")
        } catch {
            presentAlert(message: "Couldn't convert that sound file. Falling back to the current sound.")
        }
    }

    @objc private func editActiveHours() {
        let alert = NSAlert()
        alert.messageText = "Active hours"
        alert.informativeText = "Format: HH:mm-HH:mm (e.g. 08:00-17:00)"

        let field = NSTextField(string: "\(formattedTime(settings.activeHoursStartHour, settings.activeHoursStartMinute))-\(formattedTime(settings.activeHoursEndHour, settings.activeHoursEndMinute))")
        field.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let parsed = parseActiveHours(field.stringValue) else {
            presentAlert(message: "Couldn't parse that time range. Use HH:mm-HH:mm.")
            return
        }

        (settings.activeHoursStartHour, settings.activeHoursStartMinute, settings.activeHoursEndHour, settings.activeHoursEndMinute) = parsed
        persistAndReconfigure()
    }

    private func parseActiveHours(_ text: String) -> (Int, Int, Int, Int)? {
        let parts = text.split(separator: "-")
        guard parts.count == 2 else { return nil }
        func parseTime(_ value: Substring) -> (Int, Int)? {
            let components = value.split(separator: ":")
            guard components.count == 2, let hour = Int(components[0]), let minute = Int(components[1]),
                  (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
            return (hour, minute)
        }
        guard let start = parseTime(parts[0]), let end = parseTime(parts[1]) else { return nil }
        return (start.0, start.1, end.0, end.1)
    }

    @objc private func editMessage() {
        let alert = NSAlert()
        alert.messageText = "Reminder message"

        let field = NSTextField(string: settings.message)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        settings.message = field.stringValue
        persistAndReconfigure()
    }

    @objc private func toggleLaunchAtLogin() {
        settings.launchAtLogin.toggle()
        loginItemManager.setEnabled(settings.launchAtLogin)
        persistAndReconfigure()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func persistAndReconfigure() {
        settingsStore.save(settings)
        scheduler.reconfigure(settings.schedulerSettings)
        rebuildMenu()
    }

    private func presentAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
```

- [ ] **Step 2: Manual test pass**

Run: `swift run`

Walk through, confirming each behavior against the spec:
1. Icon shows `waveform.path.ecg` (Normal, inside default 08:00–17:00 window) or the paused variant if run outside that window.
2. Click Normal/Urgent mode items — the ● status line and checkmark update; icon changes for Urgent.
3. Change Normal/Urgent interval submenu selection — checkmark moves to the new value.
4. Click "Active hours…", enter `09:00-18:00`, Save — menu title updates; running outside that new window flips the icon to paused and stops firing.
5. Click "Edit message…", change the text, Save — next fired notification shows the new text.
6. Pick a different system sound from the Sound submenu — next notification uses it.
7. "Choose custom file…" with a short (<30s) `.wav`/`.mp3` — converts successfully and becomes the active sound; with a file >30s — shows the "longer than 30 seconds" alert and keeps the previous sound.
8. Trigger two reminders in a row (temporarily set a 1-min interval) — confirm the second notification **replaces** the first in Notification Center rather than stacking.
9. Toggle "Launch at Login" off then on — checkmark reflects state; verify in System Settings → General → Login Items that Heartbeat's registration matches.
10. Quit — app disappears from the menu bar, no dock icon ever appeared.

Expected: every behavior above matches; no crashes.

- [ ] **Step 3: Run full test suite**

Run: `swift test`
Expected: all tests from Tasks 2–6 still PASS (this task touches no tested logic, only wiring).

- [ ] **Step 4: Commit**

```bash
git add Sources/Heartbeat/AppDelegate.swift
git commit -m "feat: wire full menu bar UI to scheduler, notifications, sound, login item"
```

---

### Task 9: App bundle packaging + README

**Files:**
- Create: `Resources/Info.plist`
- Create: `scripts/build-app.sh`
- Create: `README.md`

**Interfaces:**
- Consumes: the `Heartbeat` executable produced by `swift build -c release`.
- Produces: `Heartbeat.app` bundle (build artifact, not committed).

- [ ] **Step 1: Write `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Heartbeat</string>
    <key>CFBundleDisplayName</key>
    <string>Heartbeat</string>
    <key>CFBundleIdentifier</key>
    <string>com.heartbeat.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Heartbeat</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Opensource — see LICENSE</string>
</dict>
</plist>
```

- [ ] **Step 2: Write `scripts/build-app.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP_DIR="dist/Heartbeat.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp "$(swift build -c release --show-bin-path)/Heartbeat" "$APP_DIR/Contents/MacOS/Heartbeat"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

echo "Built $APP_DIR"
```

- [ ] **Step 3: Make the script executable and run it**

Run: `chmod +x scripts/build-app.sh && ./scripts/build-app.sh`
Expected: prints `Built dist/Heartbeat.app`, and `dist/Heartbeat.app` exists.

- [ ] **Step 4: Verify the bundle launches**

Run: `open dist/Heartbeat.app`
Expected: pulse icon appears in the menu bar, no dock icon, no window.

- [ ] **Step 5: Write `README.md`**

```markdown
# Heartbeat

A macOS menu bar app that reminds you to check your work at a configurable
interval — for people who don't already have that habit.

## Features

- Configurable reminder interval, with separate Normal and Urgent modes
- Notifications only fire during a configurable active-hours window
  (default 08:00–17:00)
- Custom or system notification sound
- Custom reminder message
- Launch at login
- Notifications replace each other instead of stacking

## Build from source

Requires macOS 13+ and Swift 5.9+ (ships with Xcode 15+).

```bash
git clone <this-repo-url>
cd heartbeat
./scripts/build-app.sh
open dist/Heartbeat.app
```

## Installing the built app

Drag `dist/Heartbeat.app` to `/Applications`.

This build is **not notarized** by Apple. On first launch, macOS Gatekeeper
will warn that it's from an unidentified developer. To open it anyway:

1. Right-click (or Control-click) `Heartbeat.app` → **Open**.
2. Click **Open** in the dialog that appears.

(Alternative: System Settings → Privacy & Security → scroll down and click
**Open Anyway**.)

## Running tests

```bash
swift test
```

## License

MIT (or your preferred opensource license — replace this line).
```

- [ ] **Step 6: Commit**

```bash
git add Resources/Info.plist scripts/build-app.sh README.md
git commit -m "feat: add app bundle packaging script and README"
```

---

## Self-Review Notes

- **Spec coverage:** modes/intervals/replace (Task 3, 8), active hours (Task 2, 3, 8), custom message (Task 4, 8), system + custom sound with 30s/format constraint (Task 5, 6, 8), autostart default-on + toggle (Task 4, 7, 8), 3-state menu bar icon (Task 8), no dock/window (`LSUIElement`, Task 1/9), unsigned GitHub/self-host distribution (Task 9 README) — all covered.
- **Placeholder scan:** none found — every code block compiles as shown, no TODO/TBD markers.
- **Type consistency:** `HeartbeatSettings.schedulerSettings` (Task 4) matches `ReminderScheduler`'s `SchedulerSettings` init (Task 2/3). `NotificationManager.fire(message:soundName:)` (Task 5) signature matches the call in `AppDelegate.fireReminder()` (Task 8). `SoundConverter.convertToCaf` (Task 6) signature matches the call in `AppDelegate.chooseCustomSound()` (Task 8). `LoginItemManager.setEnabled(_:)` (Task 7) matches the call in `AppDelegate.toggleLaunchAtLogin()` and `applicationDidFinishLaunching` (Task 8).
