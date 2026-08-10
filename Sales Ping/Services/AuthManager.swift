import Foundation
import AuthenticationServices
import CryptoKit

@MainActor
final class AuthManager: ObservableObject {
    @Published var isSignedIn = false
    @Published var isLoading = true
    @Published var errorMessage: String?

    private(set) var currentNonce: String?

    init() {
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        defer { isLoading = false }
        guard APIClient.shared.hasAuthToken else { return }
        isSignedIn = (try? await APIClient.shared.validateSession()) == true
        if !isSignedIn { APIClient.shared.clearAuthToken() }
    }

    /// Generates a fresh nonce for the Apple request and returns its SHA-256 hash.
    func prepareAppleRequest() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

    func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let authorization):
            Task { await signIn(with: authorization) }
        }
    }

    private func signIn(with authorization: ASAuthorization) async {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let nonce = currentNonce
        else {
            errorMessage = "Apple sign-in did not return a valid credential."
            return
        }

        do {
            try await APIClient.shared.signInWithApple(
                idToken: idToken,
                nonce: nonce,
                firstName: credential.fullName?.givenName,
                lastName: credential.fullName?.familyName
            )
            isSignedIn = true
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't sign in: \(error.localizedDescription)"
        }
    }

    func signOut() {
        Task {
            await APIClient.shared.signOut()
            isSignedIn = false
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
