import AuthenticationServices
import Foundation

struct ConnectionRow: Decodable {
    let provider: String
    let status: String
    let accountLabel: String?
    let isActive: Bool
}

struct ConnectionState: Identifiable {
    var id: String { provider.rawValue }
    let provider: Provider
    var isConnected: Bool
    var isActive: Bool
    var accountLabel: String?
}

private struct ConnectionsResponse: Decodable {
    let connections: [ConnectionRow]
}

private struct Entitlement: Decodable {
    let feature: String
    let enabled: Bool
}

private struct MeResponse: Decodable {
    let entitlements: [Entitlement]
    let providerConnections: [String: Bool]
}

private struct AuthorizeResponse: Decodable {
    let authorizationUrl: URL
}

private struct CustomSourcesResponse: Decodable {
    let sources: [CustomPaymentSource]
}

private struct CustomSourceResponse: Decodable {
    let source: CustomPaymentSource
}

private struct CustomSourceMappingResponse: Decodable {
    let mapping: WebhookFieldMapping
}

private struct NotificationFieldsRequest: Encodable {
    let notificationFields: [WebhookNotificationField]
}

private struct CreateCustomSourceRequest: Encodable {
    let name: String
}

private struct CustomPreviewResponse: Decodable {
    let preview: CustomPaymentPreview
}

private struct ClearProviderPaymentsResponse: Decodable {
    let clearedPayments: Int
}

struct TestNotificationResponse: Decodable {
    let sent: Int?
    let scheduled: Bool?
    let delaySeconds: Int?
    let registered: Int?
}

enum CustomSourceRouteResolution: Equatable {
    case found(String)
    case missing
    case failed
}

private struct TestNotificationRequest: Encodable {
    let mapping: WebhookFieldMapping
    let delaySeconds: Int?
}

@MainActor
final class ConnectStore: ObservableObject {
    typealias CustomSourceDetailLoader = @MainActor (String) async throws -> CustomSourceDetail
    @Published var connections: [ConnectionState]
    @Published private(set) var entitlements: [String: Bool] = [:]
    @Published private(set) var providerAvailability: [String: Bool] = [:]
    @Published private(set) var customSources: [CustomPaymentSource] = []
    @Published var isBusy = false
    @Published var errorMessage: String?

    private let webAuthentication = ProviderWebAuthenticationSession()
    private let customSourceDetailLoader: CustomSourceDetailLoader

    convenience init() {
        self.init(customSourceDetailLoader: { id in
            try await APIClient.shared.get("/v1/custom-sources/\(id)")
        })
    }

    init(customSourceDetailLoader: @escaping CustomSourceDetailLoader) {
        self.customSourceDetailLoader = customSourceDetailLoader
        connections = Provider.mvpProviders.map {
            ConnectionState(provider: $0, isConnected: false, isActive: false, accountLabel: nil)
        }
    }

    func refresh() async {
        do {
            async let connectionsRequest: ConnectionsResponse = APIClient.shared.get("/v1/connections")
            async let meRequest: MeResponse = APIClient.shared.get("/v1/me")
            async let customRequest: CustomSourcesResponse = APIClient.shared.get("/v1/custom-sources")
            let (response, me, custom) = try await (connectionsRequest, meRequest, customRequest)
            let byProvider = Dictionary(uniqueKeysWithValues: response.connections.map { ($0.provider, $0) })
            connections = Provider.mvpProviders.map { provider in
                if let row = byProvider[provider.rawValue] {
                    return ConnectionState(
                        provider: provider,
                        isConnected: row.status == "connected",
                        isActive: row.isActive,
                        accountLabel: row.accountLabel
                    )
                }
                return ConnectionState(provider: provider, isConnected: false, isActive: false, accountLabel: nil)
            }
            entitlements = Dictionary(uniqueKeysWithValues: me.entitlements.map { ($0.feature, $0.enabled) })
            providerAvailability = me.providerConnections
            customSources = custom.sources
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load your connections."
        }
    }

    func reset() {
        connections = Provider.mvpProviders.map {
            ConnectionState(provider: $0, isConnected: false, isActive: false, accountLabel: nil)
        }
        entitlements = [:]
        providerAvailability = [:]
        customSources = []
        isBusy = false
        errorMessage = nil
    }

    func createCustomSource(name: String) async throws -> CustomPaymentSource {
        let response: CustomSourceResponse = try await APIClient.shared.post(
            "/v1/custom-sources",
            body: CreateCustomSourceRequest(name: name)
        )
        customSources.append(response.source)
        return response.source
    }

    func customSourceDetail(id: String) async throws -> CustomSourceDetail {
        let detail = try await customSourceDetailLoader(id)
        replaceCustomSource(detail.source)
        return detail
    }

    func resolveCustomSourceRoute(id: String) async -> CustomSourceRouteResolution {
        do {
            let detail = try await customSourceDetail(id: id)
            return .found(detail.source.id)
        } catch APIError.notFound {
            return .missing
        } catch {
            return .failed
        }
    }

    func previewCustomSource(id: String, mapping: WebhookFieldMapping) async throws -> CustomPaymentPreview {
        let response: CustomPreviewResponse = try await APIClient.shared.post(
            "/v1/custom-sources/\(id)/mapping",
            body: mapping
        )
        return response.preview
    }

    func testCustomSourceNotification(
        id: String,
        mapping: WebhookFieldMapping,
        delaySeconds: Int? = nil
    ) async throws -> TestNotificationResponse {
        try await APIClient.shared.post(
            "/v1/custom-sources/\(id)/test-notification",
            body: TestNotificationRequest(mapping: mapping, delaySeconds: delaySeconds)
        )
    }

    func activateCustomSource(id: String, mapping: WebhookFieldMapping) async throws -> CustomPaymentSource {
        let response: CustomSourceResponse = try await APIClient.shared.post(
            "/v1/custom-sources/\(id)/activate",
            body: mapping
        )
        replaceCustomSource(response.source)
        return response.source
    }

    func updateCustomSourceNotificationFields(
        id: String,
        fields: [WebhookNotificationField]
    ) async throws -> WebhookFieldMapping {
        let response: CustomSourceMappingResponse = try await APIClient.shared.post(
            "/v1/custom-sources/\(id)/notification-fields",
            body: NotificationFieldsRequest(notificationFields: fields)
        )
        return response.mapping
    }

    func setCustomSource(id: String, active: Bool) async throws -> CustomPaymentSource {
        let action = active ? "resume" : "pause"
        let response: CustomSourceResponse = try await APIClient.shared.post(
            "/v1/custom-sources/\(id)/\(action)"
        )
        replaceCustomSource(response.source)
        return response.source
    }

    func regenerateCustomSourceURL(id: String) async throws -> CustomPaymentSource {
        let response: CustomSourceResponse = try await APIClient.shared.post(
            "/v1/custom-sources/\(id)/regenerate"
        )
        replaceCustomSource(response.source)
        return response.source
    }

    private func replaceCustomSource(_ source: CustomPaymentSource) {
        if let index = customSources.firstIndex(where: { $0.id == source.id }) {
            customSources[index] = source
        } else {
            customSources.append(source)
        }
    }

    func isEntitled(to provider: Provider) -> Bool {
        entitlements["connect_\(provider.rawValue)"] ?? false
    }

    func isAvailable(_ provider: Provider) -> Bool {
        providerAvailability[provider.rawValue] ?? false
    }

    func connect(provider: Provider) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            guard isEntitled(to: provider) else {
                errorMessage = "Your plan doesn't include \(provider.title) connections."
                return false
            }
            guard isAvailable(provider) else {
                errorMessage = "\(provider.title) connections aren't available yet."
                return false
            }
            let response: AuthorizeResponse = try await APIClient.shared.post(
                "/v1/connections/\(provider.rawValue)/authorize"
            )
            let callback = try await webAuthentication.authenticate(at: response.authorizationUrl)
            let values = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let status = values.first(where: { $0.name == "status" })?.value
            guard status == "connected" else {
                // URLComponents percent-decodes query items but preserves the
                // form-encoded `+` that URLSearchParams uses for spaces.
                let message = values.first(where: { $0.name == "message" })?.value?
                    .replacingOccurrences(of: "+", with: " ")
                throw APIError.server(message ?? "The connection wasn't completed.")
            }
            await refresh()
            await NotificationManager.shared.requestPermissionAndRegister()
            return true
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return false
        } catch {
            errorMessage = "Couldn't connect \(provider.title): \(error.localizedDescription)"
            return false
        }
    }

    func setProviderActivity(provider: Provider, active: Bool) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let action = active ? "resume" : "pause"
            let _: ConnectionActivityResponse = try await APIClient.shared.post(
                "/v1/connections/\(provider.rawValue)/\(action)"
            )
            await refresh()
        } catch {
            errorMessage = "Couldn't update \(provider.title) payments."
        }
    }

    func disconnect(provider: Provider) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await APIClient.shared.delete("/v1/connections/\(provider.rawValue)")
            await refresh()
        } catch {
            errorMessage = "Couldn't disconnect \(provider.title)."
        }
    }

    func clearPayments(provider: Provider) async -> Int? {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response: ClearProviderPaymentsResponse = try await APIClient.shared.deleteResponse(
                "/v1/connections/\(provider.rawValue)/payments"
            )
            return response.clearedPayments
        } catch {
            errorMessage = "Couldn't clear \(provider.title) payment history."
            return nil
        }
    }

    var hasCustomSourceEntitlement: Bool {
        entitlements["connect_custom"] ?? false
    }
}

private struct ConnectionActivityResponse: Decodable {
    let connection: ConnectionRow
}
