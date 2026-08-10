import AuthenticationServices
import UIKit

@MainActor
final class ProviderWebAuthenticationSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "chaching") { [weak self] callback, error in
                Task { @MainActor in
                    self?.session = nil
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let callback {
                        continuation.resume(returning: callback)
                    } else {
                        continuation.resume(throwing: APIError.invalidResponse)
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: APIError.server("Couldn't open the provider sign-in page."))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
