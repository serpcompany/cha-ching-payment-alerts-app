import AuthenticationServices
import Foundation

struct ConnectionRow: Decodable {
    let provider: String
    let status: String
    let accountLabel: String?
}

struct ConnectionState: Identifiable {
    var id: String { processor.rawValue }
    let processor: Processor
    var isConnected: Bool
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
}

private struct AuthorizeResponse: Decodable {
    let authorizationUrl: URL
}

@MainActor
final class ConnectStore: ObservableObject {
    @Published var connections: [ConnectionState]
    @Published private(set) var entitlements: [String: Bool] = [:]
    @Published var isBusy = false
    @Published var errorMessage: String?

    private let webAuthentication = ProviderWebAuthenticationSession()

    init() {
        connections = Processor.mvpProviders.map {
            ConnectionState(processor: $0, isConnected: false, accountLabel: nil)
        }
    }

    func refresh() async {
        do {
            async let connectionsRequest: ConnectionsResponse = APIClient.shared.get("/v1/connections")
            async let meRequest: MeResponse = APIClient.shared.get("/v1/me")
            let (response, me) = try await (connectionsRequest, meRequest)
            let byProvider = Dictionary(uniqueKeysWithValues: response.connections.map { ($0.provider, $0) })
            connections = Processor.mvpProviders.map { processor in
                if let row = byProvider[processor.rawValue] {
                    return ConnectionState(
                        processor: processor,
                        isConnected: row.status == "connected",
                        accountLabel: row.accountLabel
                    )
                }
                return ConnectionState(processor: processor, isConnected: false, accountLabel: nil)
            }
            entitlements = Dictionary(uniqueKeysWithValues: me.entitlements.map { ($0.feature, $0.enabled) })
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load your connections."
        }
    }

    func isEntitled(to provider: Processor) -> Bool {
        entitlements["connect_\(provider.rawValue)"] ?? false
    }

    func connect(provider: Processor) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            guard isEntitled(to: provider) else {
                errorMessage = "Your plan doesn't include \(provider.title) connections."
                return false
            }
            let response: AuthorizeResponse = try await APIClient.shared.post(
                "/v1/connections/\(provider.rawValue)/authorize"
            )
            let callback = try await webAuthentication.authenticate(at: response.authorizationUrl)
            let values = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let status = values.first(where: { $0.name == "status" })?.value
            guard status == "connected" else {
                let message = values.first(where: { $0.name == "message" })?.value
                throw APIError.server(message ?? "The connection wasn't completed.")
            }
            await refresh()
            return true
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return false
        } catch {
            errorMessage = "Couldn't connect \(provider.title): \(error.localizedDescription)"
            return false
        }
    }

    func disconnect(provider: Processor) async {
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
}
