import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var countdownTimer: Timer?
    private let settingsStore = SettingsStore()
    private let notificationManager = NotificationManager()
    private let loginItemManager = LoginItemManager()
    private var scheduler: ReminderScheduler!
    private var settings: HeartbeatSettings!

    private let systemSoundNames = ["Basso", "Blow", "Glass", "Ping", "Pop", "Submarine"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpEditMenu()

        settings = settingsStore.load()

        if settings.launchAtLogin {
            loginItemManager.setEnabled(true)
        }

        scheduler = ReminderScheduler(settings: settings.schedulerSettings)
        scheduler.onFire = { [weak self] in self?.fireReminder() }
        scheduler.onStateChange = { [weak self] _ in self?.refreshDisplay() }

        UNUserNotificationCenter.current().delegate = self
        notificationManager.requestAuthorization { _ in }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        refreshDisplay()

        scheduler.start()

        // The reminder timer only ticks on the scheduled interval grid, so
        // without this, the menu's "outside active hours" / countdown text
        // would stay stale for however long it's been since the last tick
        // (e.g. still showing "outside active hours" well after crossing
        // into the active window). This keeps it live regardless.
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshDisplay()
        }
    }

    private func refreshDisplay() {
        let state = scheduler.currentState()
        updateIcon(for: state)
        updateCountdownTitle()
        rebuildMenu()
    }

    // MARK: - Edit menu

    // As an accessory (menu bar only) app, Heartbeat has no main menu by
    // default, so there's no "Edit" menu wiring Cmd+C/V/X/A to the standard
    // NSText selectors. Without it, those shortcuts silently do nothing in
    // any text field, including the alert dialogs below.
    private func setUpEditMenu() {
        let mainMenu = NSMenu()

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Reminder firing

    private func fireReminder() {
        notificationManager.fire(message: settings.message, soundName: settings.soundName)
    }

    // MARK: - Notification interaction

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.notification.request.identifier == NotificationManager.reminderIdentifier else {
            completionHandler()
            return
        }
        performNotificationAction()
        completionHandler()
    }

    private func performNotificationAction() {
        switch settings.actionType {
        case .none:
            break
        case .openURL:
            guard let url = URL(string: settings.actionValue) else { return }
            NSWorkspace.shared.open(url)
        case .openApp:
            NSWorkspace.shared.open(URL(fileURLWithPath: settings.actionValue))
        }
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

    private func updateCountdownTitle() {
        guard scheduler.pauseReason() == nil, let nextFireDate = scheduler.nextFireDate() else {
            statusItem.button?.title = ""
            return
        }
        let secondsRemaining = nextFireDate.timeIntervalSinceNow
        guard secondsRemaining > 0 else {
            statusItem.button?.title = ""
            return
        }
        let minutesRemaining = Int((secondsRemaining / 60).rounded(.up))
        statusItem.button?.title = " \(minutesRemaining)m"
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        let statusLabel = settings.mode == .normal ? "Active (Normal)" : "Active (Urgent)"
        menu.addItem(NSMenuItem(title: "● \(statusLabel)", action: nil, keyEquivalent: ""))

        if let pauseReason = scheduler.pauseReason() {
            let reasonText: String
            switch pauseReason {
            case .outsideActiveHours: reasonText = "outside active hours"
            case .weekend: reasonText = "weekend (weekdays only is on)"
            }
            menu.addItem(NSMenuItem(title: "Next reminder: \(reasonText)", action: nil, keyEquivalent: ""))
        } else if let nextFireDate = scheduler.nextFireDate() {
            menu.addItem(NSMenuItem(title: "Next reminder: \(formattedClockTime(nextFireDate))", action: nil, keyEquivalent: ""))
        }
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

        let weekdaysOnlyItem = NSMenuItem(title: "Weekdays only", action: #selector(toggleWeekdaysOnly), keyEquivalent: "")
        weekdaysOnlyItem.target = self
        weekdaysOnlyItem.state = settings.weekdaysOnly ? .on : .off
        menu.addItem(weekdaysOnlyItem)
        menu.addItem(.separator())

        let messageItem = NSMenuItem(title: "Edit message…", action: #selector(editMessage), keyEquivalent: "")
        messageItem.target = self
        menu.addItem(messageItem)
        menu.addItem(.separator())

        menu.addItem(makeSoundSubmenu())
        menu.addItem(.separator())

        menu.addItem(makeActionSubmenu())
        menu.addItem(.separator())

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = settings.launchAtLogin ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About Heartbeat…", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

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

    private func makeActionSubmenu() -> NSMenuItem {
        let submenu = NSMenu()

        let noneItem = NSMenuItem(title: "None (just clear notification)", action: #selector(setActionNone), keyEquivalent: "")
        noneItem.target = self
        noneItem.state = settings.actionType == .none ? .on : .off
        submenu.addItem(noneItem)

        let urlItem = NSMenuItem(title: "Open URL…", action: #selector(setActionURL), keyEquivalent: "")
        urlItem.target = self
        urlItem.state = settings.actionType == .openURL ? .on : .off
        submenu.addItem(urlItem)

        let appItem = NSMenuItem(title: "Open App…", action: #selector(setActionApp), keyEquivalent: "")
        appItem.target = self
        appItem.state = settings.actionType == .openApp ? .on : .off
        submenu.addItem(appItem)

        let subtitle: String
        switch settings.actionType {
        case .none: subtitle = "None"
        case .openURL: subtitle = "Open URL"
        case .openApp: subtitle = "Open App"
        }
        let parent = NSMenuItem(title: "On click: \(subtitle)", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private func formattedTime(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    private func formattedClockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
        previewSound(named: name)
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
            previewSound(at: convertedURL)
        } catch SoundConverterError.tooLong {
            presentAlert(message: "That sound is longer than 30 seconds. Choose a shorter clip.")
        } catch {
            presentAlert(message: "Couldn't convert that sound file. Falling back to the current sound.")
        }
    }

    private var soundPreview: NSSound?

    private func previewSound(named name: String) {
        soundPreview = NSSound(named: name)
        soundPreview?.play()
    }

    private func previewSound(at url: URL) {
        soundPreview = NSSound(contentsOf: url, byReference: true)
        soundPreview?.play()
    }

    @objc private func editActiveHours() {
        let alert = NSAlert()
        alert.messageText = "Active hours"
        alert.informativeText = "Format: HH:mm-HH:mm (e.g. 08:00-17:00)"

        let field = NSTextField(string: "\(formattedTime(settings.activeHoursStartHour, settings.activeHoursStartMinute))-\(formattedTime(settings.activeHoursEndHour, settings.activeHoursEndMinute))")
        field.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
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

    @objc private func toggleWeekdaysOnly() {
        settings.weekdaysOnly.toggle()
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
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        settings.message = field.stringValue
        persistAndReconfigure()
    }

    @objc private func setActionNone() {
        settings.actionType = .none
        settings.actionValue = ""
        persistAndReconfigure()
    }

    @objc private func setActionURL() {
        let alert = NSAlert()
        alert.messageText = "Open URL on click"
        alert.informativeText = "e.g. https://your-task-board.example.com"

        let field = NSTextField(string: settings.actionType == .openURL ? settings.actionValue : "https://")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let url = URL(string: field.stringValue), url.scheme != nil else {
            presentAlert(message: "That doesn't look like a valid URL.")
            return
        }

        settings.actionType = .openURL
        settings.actionValue = url.absoluteString
        persistAndReconfigure()
    }

    @objc private func setActionApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let appURL = panel.url else { return }

        settings.actionType = .openApp
        settings.actionValue = appURL.path
        persistAndReconfigure()
    }

    @objc private func toggleLaunchAtLogin() {
        settings.launchAtLogin.toggle()
        loginItemManager.setEnabled(settings.launchAtLogin)
        persistAndReconfigure()
    }

    @objc private func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

        let alert = NSAlert()
        alert.messageText = "Heartbeat \(version)"
        alert.informativeText = """
        A macOS menu bar app that nudges you to check your work at a \
        configurable interval.

        Created by dika-putra.

        Found an issue or want to contribute? Visit the GitHub repo.
        """
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "Close")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/dika-putra/heartbeat")!)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func persistAndReconfigure() {
        settingsStore.save(settings)
        scheduler.reconfigure(settings.schedulerSettings)
        refreshDisplay()
    }

    private func presentAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
