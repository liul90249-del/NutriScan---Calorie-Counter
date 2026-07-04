import Foundation
import UserNotifications

struct WaterReminderRequest: Encodable {
    let locale: String
    let profile: CoachUserProfilePayload
}

struct WaterReminderResponse: Decodable {
    let reminders: [WaterReminderItem]
}

struct WaterReminderItem: Decodable {
    let timeOfDay: String
    let hour: Int
    let title: String
    let body: String
}

struct WaterReminderService {
    private let endpoint: URL?
    private let apiKey: String
    private let session: URLSession
    private let notificationCenter: UNUserNotificationCenter
    private let notificationIdentifiers = [
        "nutriscan.water.morning",
        "nutriscan.water.midday",
        "nutriscan.water.evening"
    ]

    init(
        endpoint: URL? = URL(string: NutriScanBackendConfig.waterRemindersEndpoint),
        apiKey: String = NutriScanBackendConfig.clientToken,
        session: URLSession = .shared,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
        self.notificationCenter = notificationCenter
    }

    func enableDailyWaterReminders(profile: AppFlowViewModel.UserProfile, locale: Locale) async throws -> Bool {
        let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else {
            await disableDailyWaterReminders()
            return false
        }

        let reminders = await fetchReminderCopy(profile: profile, locale: locale)
        await schedule(reminders: reminders)
        return true
    }

    func disableDailyWaterReminders() async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: notificationIdentifiers)
    }

    private func fetchReminderCopy(profile: AppFlowViewModel.UserProfile, locale: Locale) async -> [WaterReminderItem] {
        guard let endpoint else {
            return Self.defaultReminders(locale: locale)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        request.httpBody = try? JSONEncoder().encode(
            WaterReminderRequest(
                locale: locale.identifier,
                profile: CoachUserProfilePayload(
                    gender: profile.gender,
                    height: profile.height,
                    weight: profile.weight,
                    goalWeight: profile.goalWeight,
                    activityLevel: profile.activityLevel,
                    weeklyLossRate: profile.weeklyLossRate,
                    unit: profile.unit.rawValue,
                    isPremium: profile.isPremium
                )
            )
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return Self.defaultReminders(locale: locale)
            }
            let decoded = try JSONDecoder().decode(WaterReminderResponse.self, from: data)
            return decoded.reminders.count == 3 ? decoded.reminders : Self.defaultReminders(locale: locale)
        } catch {
            return Self.defaultReminders(locale: locale)
        }
    }

    private func schedule(reminders: [WaterReminderItem]) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: notificationIdentifiers)

        for (index, reminder) in reminders.prefix(3).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default

            var date = DateComponents()
            date.hour = min(max(reminder.hour, 0), 23)
            date.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(
                identifier: notificationIdentifiers[index],
                content: content,
                trigger: trigger
            )
            try? await notificationCenter.add(request)
        }
    }

    private static func defaultReminders(locale: Locale) -> [WaterReminderItem] {
        if locale.identifier.hasPrefix("zh") {
            return [
                WaterReminderItem(timeOfDay: "morning", hour: 9, title: "早晨补水", body: "起床后补一杯水，帮今天的记录有个稳定开始。"),
                WaterReminderItem(timeOfDay: "midday", hour: 13, title: "午间喝水", body: "午餐前后喝点水，别把口渴误当成饥饿。"),
                WaterReminderItem(timeOfDay: "evening", hour: 19, title: "晚间补水", body: "晚饭后少量补水，给今天的状态做个温和收尾。")
            ]
        }
        return [
            WaterReminderItem(timeOfDay: "morning", hour: 9, title: "Morning water", body: "Start steady with a glass of water before the day gets busy."),
            WaterReminderItem(timeOfDay: "midday", hour: 13, title: "Midday sip", body: "Take a water break before thirst starts looking like hunger."),
            WaterReminderItem(timeOfDay: "evening", hour: 19, title: "Evening reset", body: "A small glass now helps you close the day with a steadier routine.")
        ]
    }
}
