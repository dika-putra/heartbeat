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
        alert.informativeText = "Tip: include [HH:mm] or [HH:mm:ss] to show the current time when the reminder fires."

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
        updateIcon(for: scheduler.currentState())
        rebuildMenu()
    }

    private func presentAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
