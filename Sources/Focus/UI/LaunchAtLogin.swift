import Foundation
import ServiceManagement
import os

private let log = Logger(subsystem: "com.nchourrout.focus", category: "launch-at-login")

/// Thin wrapper around `SMAppService.mainApp` so the Settings toggle is a one-liner.
/// Requires Focus.app to live in /Applications; when run from a development build
/// the call may fail silently (logged to Console.app, not fatal).
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
            log.error("failed to \(enabled ? "register" : "unregister", privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
