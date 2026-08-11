import Foundation
import UIKit
@preconcurrency import UserNotifications

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

struct PaymentNotificationPreference {
    private static let key = "chaChingPaymentNotificationsEnabled"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasExplicitValue: Bool { defaults.object(forKey: Self.key) != nil }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}

struct ForegroundPaymentNotification: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let lines: [String]

    init(title: String, body: String) {
        self.title = title
        lines = body.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}

enum PaymentNotificationPresentation {
    static let foregroundOptions: UNNotificationPresentationOptions = [
        .banner,
        .list,
        .sound,
        .badge,
    ]
    static let showsFullDetailsAutomatically = false
    static let showsFullDetailsAfterTap = true
}

enum PaymentNotificationResponseRouter {
    static func route(
        title: String,
        body: String,
        onOpen: @escaping @MainActor @Sendable (ForegroundPaymentNotification) -> Void,
        completion: @escaping @Sendable () -> Void
    ) {
        DispatchQueue.main.async {
            onOpen(ForegroundPaymentNotification(title: title, body: body))
            completion()
        }
    }
}

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var hasRegisteredDevice = false
    @Published private(set) var registrationError: String?
    @Published private(set) var paymentNotificationsEnabled: Bool
    @Published private(set) var isUpdatingPaymentNotifications = false
    @Published private(set) var foregroundNotification: ForegroundPaymentNotification?

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    var canDeliverNotifications: Bool {
        paymentNotificationsEnabled && isAuthorized && hasRegisteredDevice
    }

    var statusText: String {
        if registrationError != nil { return "Needs attention" }
        if !paymentNotificationsEnabled { return "Off" }
        if canDeliverNotifications { return "On" }
        if isAuthorized { return "Waiting for device" }
        return "Off"
    }

    var registrationHelpText: String? {
        guard paymentNotificationsEnabled, isAuthorized, !hasRegisteredDevice, registrationError == nil else {
            return nil
        }
        #if targetEnvironment(simulator)
        return "Notification permission is on, but remote payment notifications require a signed build on your iPhone."
        #else
        return "Notification permission is on. Tap Retry registration to finish connecting this iPhone."
        #endif
    }

    private let center = UNUserNotificationCenter.current()
    private let deviceId: String
    private var preference = PaymentNotificationPreference()
    private var deviceToken: String?

    override private init() {
        paymentNotificationsEnabled = preference.isEnabled
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
        if !preference.hasExplicitValue {
            let migratedValue = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            preference.isEnabled = migratedValue
            paymentNotificationsEnabled = migratedValue
        }
    }

    func requestPermissionAndRegister() async {
        guard paymentNotificationsEnabled else { return }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            guard granted else {
                registrationError = "Allow notifications in iPhone Settings to turn payment notifications on."
                return
            }
            registerIfAuthorized()
        } catch {
            registrationError = "Notifications couldn't be enabled: \(error.localizedDescription)"
        }
    }

    func registerIfAuthorized() {
        guard APIClient.shared.hasAuthToken else { return }
        Task {
            await refreshAuthorizationStatus()
            guard paymentNotificationsEnabled, isAuthorized else { return }
            UIApplication.shared.registerForRemoteNotifications()
            if deviceToken != nil { await uploadToken() }
        }
    }

    func didRegister(deviceToken data: Data) {
        guard paymentNotificationsEnabled else { return }
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        Task { await uploadToken() }
    }

    func didFailToRegister(error: Error) {
        hasRegisteredDevice = false
        registrationError = "This device couldn't register for notifications: \(error.localizedDescription)"
    }

    @discardableResult
    func unregisterCurrentDevice() async -> Bool {
        guard APIClient.shared.hasAuthToken else {
            hasRegisteredDevice = false
            return true
        }
        do {
            try await APIClient.shared.delete("/v1/devices/\(deviceId)")
            hasRegisteredDevice = false
            registrationError = nil
            return true
        } catch {
            registrationError = "This device couldn't be removed from notifications."
            return false
        }
    }

    func setPaymentNotificationsEnabled(_ enabled: Bool) async {
        guard enabled != paymentNotificationsEnabled else { return }
        isUpdatingPaymentNotifications = true
        registrationError = nil
        defer { isUpdatingPaymentNotifications = false }

        if enabled {
            preference.isEnabled = true
            paymentNotificationsEnabled = true
            await requestPermissionAndRegister()
            return
        }

        guard await unregisterCurrentDevice() else { return }
        preference.isEnabled = false
        paymentNotificationsEnabled = false
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    func dismissForegroundNotification() {
        foregroundNotification = nil
    }

    private func uploadToken() async {
        guard paymentNotificationsEnabled, let deviceToken, APIClient.shared.hasAuthToken else { return }
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
            hasRegisteredDevice = true
            registrationError = nil
        } catch {
            hasRegisteredDevice = false
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
        return PaymentNotificationPresentation.foregroundOptions
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let content = response.notification.request.content
        PaymentNotificationResponseRouter.route(
            title: content.title,
            body: content.body,
            onOpen: { [weak self] notification in
                guard let self else { return }
                NotificationCenter.default.post(name: .chaChingSaleReceived, object: nil)
                if PaymentNotificationPresentation.showsFullDetailsAfterTap {
                    foregroundNotification = notification
                }
            },
            completion: completionHandler
        )
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
