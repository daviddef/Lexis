import Foundation
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

// MARK: - Local notifications (the daily habit)
//
// The single highest-ROI retention lever, and previously unbuilt: a daily
// game with no reminder loses players the moment they forget to open it.
// Three opt-in, purely-local reminders (no push server, no entitlement):
//
//   1. Daily reminder  — "today's puzzle is ready", at a user-set hour, daily.
//   2. Streak at risk  — evening nudge only when a live streak is unplayed.
//   3. Win-back        — a single nudge after ~3 idle days.
//
// Permission is requested at the RIGHT moment — after the player finishes
// their first Daily Challenge, when the value is obvious — never cold on
// first launch. All copy lives here for easy review/tuning.
//
// Scheduling is idempotent: `refresh()` clears and re-lays every pending
// request from current settings + streak state, and is called on launch,
// after each daily result, and when notification settings change. So the
// schedule self-heals every time the app is opened.

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    // Set when the user taps a notification, observed by the UI to deep-link
    // (currently everything routes into the Daily Challenge).
    @Published var pendingRoute: String?

    private let center = UNUserNotificationCenter.current()
    private let settings = GameSettings.shared

    private enum ID {
        static let daily = "lexis.daily_reminder"
        static let streak = "lexis.streak_risk"
        static let winback = "lexis.winback"
    }

    func configure() {
        center.delegate = self
    }

    // MARK: Permission

    /// Ask for permission the first time it makes sense (after a first daily
    /// result). No-ops if we've asked before. Refreshes the schedule on grant.
    func requestAuthorizationIfAppropriate() {
        guard !settings.notificationsRequested else { return }
        settings.notificationsRequested = true
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            Task { @MainActor in
                Analytics.shared.notificationPermission(granted: granted)
                if granted { self?.refresh() }
            }
        }
    }

    /// Called from Settings when the user flips a notification toggle. Also
    /// requests permission if they're enabling something and we've never asked.
    func settingsChanged() {
        if !settings.notificationsRequested {
            settings.notificationsRequested = true
            center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
                Task { @MainActor in
                    Analytics.shared.notificationPermission(granted: granted)
                    self?.refresh()
                }
            }
        } else {
            refresh()
        }
    }

    // MARK: Scheduling

    /// Clear and re-lay every pending reminder from current settings + streak
    /// state. Safe to call as often as we like.
    func refresh() {
        center.getNotificationSettings { [weak self] auth in
            Task { @MainActor in
                guard let self else { return }
                guard auth.authorizationStatus == .authorized || auth.authorizationStatus == .provisional else {
                    self.center.removeAllPendingNotificationRequests()
                    return
                }
                self.center.removePendingNotificationRequests(withIdentifiers: [ID.daily, ID.streak, ID.winback])

                if self.settings.dailyReminderEnabled {
                    self.scheduleDailyReminder()
                }
                if self.settings.streakReminderEnabled {
                    self.scheduleStreakReminder()
                }
                if self.settings.winbackEnabled {
                    self.scheduleWinback()
                }
            }
        }
    }

    private func scheduleDailyReminder() {
        var comps = DateComponents()
        comps.hour = settings.dailyReminderHour
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        add(ID.daily, title: "Today's LEXIS is ready",
            body: "A fresh 40-letter puzzle is waiting — what's your best score?",
            route: "daily", trigger: trigger)
    }

    // Fires at 20:00 on the soonest day the streak is actually at risk: today
    // if it's unplayed and 8pm hasn't passed, otherwise the next day. Rebuilt
    // every open, so playing today pushes it to tomorrow automatically.
    private func scheduleStreakReminder() {
        let daily = DailyChallengeManager.shared
        let streak = daily.currentStreak
        guard streak >= 1 else { return }

        let cal = Calendar.current
        let now = Date()
        var fireDay = now
        // If today's already done, the earliest at-risk evening is tomorrow.
        if daily.hasCompletedToday {
            fireDay = cal.date(byAdding: .day, value: 1, to: now) ?? now
        }
        var comps = cal.dateComponents([.year, .month, .day], from: fireDay)
        comps.hour = 20
        comps.minute = 0
        guard var fireDate = cal.date(from: comps) else { return }
        // If that moment is already in the past (e.g. it's 9pm and unplayed),
        // roll to tomorrow evening.
        if fireDate <= now {
            fireDate = cal.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate
        }
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
            repeats: false)
        add(ID.streak, title: "🔥 Your streak is on the line",
            body: "Play today's LEXIS before midnight to keep your \(streak)-day streak alive.",
            route: "daily", trigger: trigger)
    }

    // A single nudge ~3 days out; pushed forward every launch, so it only ever
    // fires if the app goes genuinely untouched for three days.
    private func scheduleWinback() {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3 * 24 * 60 * 60, repeats: false)
        add(ID.winback, title: "Your letters are getting lonely",
            body: "A new LEXIS daily puzzle is waiting. Come find a word or two.",
            route: "daily", trigger: trigger)
    }

    private func add(_ id: String, title: String, body: String, route: String,
                     trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["route": route]
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

// MARK: - Delegate (foreground presentation + taps)

extension NotificationManager: UNUserNotificationCenterDelegate {
    // Show the banner even if the app is foregrounded, so a reminder that
    // fires while playing isn't silently swallowed.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let route = response.notification.request.content.userInfo["route"] as? String
        Task { @MainActor in
            self.pendingRoute = route ?? "daily"
        }
        completionHandler()
    }
}
