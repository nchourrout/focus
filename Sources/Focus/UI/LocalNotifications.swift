import Foundation
import UserNotifications

/// Notifications routed through `UNUserNotificationCenter`, which attributes
/// the banner to the calling app's bundle identifier. That's why the user sees
/// the Focus icon here. The daemon (CLI process, no NSApplication) can't use
/// UNC, so phase-change notifications are emitted by `AppState` instead — which
/// observes the same state file the daemon writes.
enum LocalNotifications {
    /// Category + action wiring for the "stop after each set" prompt. Both actions
    /// are handled by `FocusAppDelegate` (the UNC delegate), which relaunches a
    /// pomodoro: `startAnotherSet` reuses the goal carried in `userInfo`, while
    /// `newGoal` is a text-input action that starts the next set with whatever the
    /// user types (falling back to the previous goal if they submit it empty).
    static let setCompleteCategory = "SET_COMPLETE"
    static let startAnotherSetAction = "START_ANOTHER_SET"
    static let newGoalAction = "NEW_GOAL"
    static let goalUserInfoKey = "goal"

    /// First call shows the system permission prompt; subsequent calls are
    /// no-ops. Safe to invoke from `applicationDidFinishLaunching`.
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Register the actionable categories. Call once at launch, before any
    /// `postSetComplete` could fire, so the "Start another set" button renders.
    static func registerCategories() {
        // No `.foreground`: continuing starts a background daemon (a CLI spawn),
        // so there's no reason to yank focus to the app. The text-input action
        // keeps the user in the notification to type the next goal.
        let start = UNNotificationAction(
            identifier: startAnotherSetAction,
            title: "Start another set",
            options: []
        )
        let newGoal = UNTextInputNotificationAction(
            identifier: newGoalAction,
            title: "New goal…",
            options: [],
            textInputButtonTitle: "Start",
            textInputPlaceholder: "What are you working on?"
        )
        let category = UNNotificationCategory(
            identifier: setCompleteCategory,
            actions: [start, newGoal],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Posted when a "stop after each set" run finishes. Carries the goal so the
    /// action handler can relaunch the same work. No `sound` — the caller plays
    /// its own `NSSound` cue, audible under Do-Not-Disturb.
    static func postSetComplete(goal: String) {
        post(
            title: "Set complete",
            body: "Finished a full set: \(goal). Start another?",
            sound: nil,
            category: setCompleteCategory,
            userInfo: [goalUserInfoKey: goal]
        )
    }

    /// `sound: nil` for callers that play their own `NSSound` cue (phase
    /// transitions) so we don't double-trigger audio. `category`/`userInfo` wire
    /// up actionable notifications (see `postSetComplete`).
    static func post(title: String, body: String, sound: UNNotificationSound? = .default,
                     category: String? = nil, userInfo: [AnyHashable: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let sound { content.sound = sound }
        if let category { content.categoryIdentifier = category }
        if !userInfo.isEmpty { content.userInfo = userInfo }
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
