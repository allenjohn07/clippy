import Foundation
import ServiceManagement

/// "Launch at Login" via the system login-items service (only works when running as Clippy.app).
enum LoginItem {
    private static let offeredKey = "didEnableLoginItemOnFirstLaunch"

    /// Login items need a real app bundle; `swift run` / bare binaries can't register.
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static var isEnabled: Bool { isAvailable && SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            print("clippy: could not \(enabled ? "enable" : "disable") launch at login: \(error)")
        }
    }

    /// Turns on launch-at-login the first time the app runs. The user can switch it off
    /// from the menu bar icon or System Settings → General → Login Items.
    static func enableOnFirstLaunch() {
        guard isAvailable, !UserDefaults.standard.bool(forKey: offeredKey) else { return }
        UserDefaults.standard.set(true, forKey: offeredKey)
        setEnabled(true)
    }
}
