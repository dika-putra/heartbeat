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
