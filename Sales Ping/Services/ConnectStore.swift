import Foundation
import Supabase

struct ConnectionRow: Decodable {
    let provider: String
    let status: String
    let accountLabel: String?
    let lastEventAt: Date?

    enum CodingKeys: String, CodingKey {
        case provider, status
        case accountLabel = "account_label"
        case lastEventAt = "last_event_at"
    }
}

struct ConnectionState: Identifiable {
    var id: String { processor.rawValue }
    let processor: Processor
    var isConnected: Bool
    var accountLabel: String?
}

private struct ConnectPayload: Encodable {
    let provider: String
    let apiKey: String
    let webhookSecret: String?
    let accountLabel: String?
}

private struct DisconnectPayload: Encodable {
    let provider: String
}

@MainActor
final class ConnectStore: ObservableObject {
    @Published var connections: [ConnectionState]
    @Published var isBusy = false
    @Published var errorMessage: String?

    init() {
        connections = Processor.allCases.map { ConnectionState(processor: $0, isConnected: false, accountLabel: nil) }
    }

    func refresh() async {
        do {
            let rows: [ConnectionRow] = try await SupabaseManager.client
                .from("provider_connections")
                .select("provider,status,account_label,last_event_at")
                .execute()
                .value
            let byProvider = Dictionary(uniqueKeysWithValues: rows.map { ($0.provider, $0) })
            connections = Processor.allCases.map { processor in
                if let row = byProvider[processor.rawValue] {
                    return ConnectionState(processor: processor, isConnected: row.status == "connected", accountLabel: row.accountLabel)
                }
                return ConnectionState(processor: processor, isConnected: false, accountLabel: nil)
            }
        } catch {
            errorMessage = "Couldn't load your connections."
        }
    }

    func connect(provider: Processor, apiKey: String, webhookSecret: String?, accountLabel: String?) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let payload = ConnectPayload(provider: provider.rawValue, apiKey: apiKey, webhookSecret: webhookSecret, accountLabel: accountLabel)
            try await SupabaseManager.client.functions.invoke("connect-provider", options: .init(body: payload))
            await refresh()
            return true
        } catch {
            errorMessage = "Couldn't connect \(provider.title). Double-check your key and try again."
            return false
        }
    }

    func disconnect(provider: Processor) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let payload = DisconnectPayload(provider: provider.rawValue)
            try await SupabaseManager.client.functions.invoke("disconnect-provider", options: .init(body: payload))
            await refresh()
        } catch {
            errorMessage = "Couldn't disconnect \(provider.title)."
        }
    }
}
