import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` so the Settings toggle is a one-liner.
/// Requires Focus.app to live in /Applications; when run from a development build
/// the call may fail silently (logged, not fatal).
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LaunchAtLogin: failed to %@: %@", enabled ? "register" : "unregister", String(describing: error))
        }
    }
}
