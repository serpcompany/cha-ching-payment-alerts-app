import Foundation

private struct PreferencesResponse: Decodable {
    let reportingTimezone: String?
}

private struct PreferencesRequest: Encodable {
    let reportingTimezone: String
    let initializeOnly: Bool
}

@MainActor
final class PreferencesStore: ObservableObject {
    @Published private(set) var reportingTimezone: String?
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    func initializeIfNeeded() async {
        guard reportingTimezone == nil else { return }
        do {
            let response: PreferencesResponse = try await APIClient.shared.put(
                "/v1/preferences",
                body: PreferencesRequest(
                    reportingTimezone: TimeZone.current.identifier,
                    initializeOnly: true
                )
            )
            reportingTimezone = response.reportingTimezone
            errorMessage = nil
        } catch {
            errorMessage = "Reporting timezone couldn't be set."
        }
    }

    func updateReportingTimezone(_ identifier: String) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            let response: PreferencesResponse = try await APIClient.shared.put(
                "/v1/preferences",
                body: PreferencesRequest(reportingTimezone: identifier, initializeOnly: false)
            )
            reportingTimezone = response.reportingTimezone
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Reporting timezone couldn't be updated."
            return false
        }
    }

    func reset() {
        reportingTimezone = nil
        errorMessage = nil
        isSaving = false
    }
}
