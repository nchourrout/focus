import Foundation

/// User-tunable preferences persisted in UserDefaults. Defaults to the classic
/// 25 / 5 pomodoro split if unset.
enum Defaults {
    private static let workKey = "workMinutes"
    private static let breakKey = "breakMinutes"

    static var workMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: workKey)
            return v > 0 ? v : 25
        }
        set {
            UserDefaults.standard.set(max(1, newValue), forKey: workKey)
        }
    }

    static var breakMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: breakKey)
            return v > 0 ? v : 5
        }
        set {
            UserDefaults.standard.set(max(1, newValue), forKey: breakKey)
        }
    }
}
