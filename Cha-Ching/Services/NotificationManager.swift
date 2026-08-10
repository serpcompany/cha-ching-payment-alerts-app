import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let chaChingSaleReceived = Notification.Name("com.serpcompany.chaching.sale-received")
}

private struct DeviceRegistrationRequest: Encodable {
    let deviceId: String
    let token: String
    let environment: String
}

private struct DeviceRegistrationResponse: Decodable {
    let registered: Bool
}

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var registrationError: String?

    var isEnabled: Bool { authorizationStatus == .authorized || authorizationStatus == .provisional }

    private let center = UNUserNotificationCenter.current()
    private let deviceId: String
    private var deviceToken: String?

    override private init() {
        let key = "chaChingDeviceId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            deviceId = existing
        } else {
            let generated = UUID().uuidString.lowercased()
            UserDefaults.standard.set(generated, forKey: key)
            deviceId = generated
        }
        super.init()
        center.delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestPermissionAndRegister() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            registerIfAuthorized()
        } catch {
            registrationError = "Notifications couldn't be enabled: \(error.localizedDescription)"
        }
    }

    func registerIfAuthorized() {
        guard APIClient.shared.hasAuthToken else { return }
        Task {
            await refreshAuthorizationStatus()
            guard isEnabled else { return }
            UIApplication.shared.registerForRemoteNotifications()
            if deviceToken != nil { await uploadToken() }
        }
    }

    func didRegister(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        Task { await uploadToken() }
    }

    func didFailToRegister(error: Error) {
        registrationError = "This device couldn't register for notifications: \(error.localizedDescription)"
    }

    func unregisterCurrentDevice() async {
        guard APIClient.shared.hasAuthToken else { return }
        do {
            try await APIClient.shared.delete("/v1/devices/\(deviceId)")
        } catch {
            registrationError = "This device couldn't be removed from notifications."
        }
    }

    private func uploadToken() async {
        guard let deviceToken, APIClient.shared.hasAuthToken else { return }
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        do {
            let response: DeviceRegistrationResponse = try await APIClient.shared.post(
                "/v1/devices",
                body: DeviceRegistrationRequest(
                    deviceId: deviceId,
                    token: deviceToken,
                    environment: environment
                )
            )
            guard response.registered else { throw APIError.invalidResponse }
            registrationError = nil
        } catch {
            registrationError = "This device couldn't register for notifications."
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run {
            NotificationCenter.default.post(name: .chaChingSaleReceived, object: nil)
        }
        return [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            NotificationCenter.default.post(name: .chaChingSaleReceived, object: nil)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in NotificationManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in NotificationManager.shared.didFailToRegister(error: error) }
    }
}
