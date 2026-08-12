import Foundation
import AuthenticationServices
import CryptoKit

@MainActor
final class AuthManager: ObservableObject {
    @Published var isSignedIn = false
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published private(set) var isDeletingAccount = false
    @Published var accountDeletionError: String?

    private(set) var currentNonce: String?

    init() {
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        defer { isLoading = false }
        guard APIClient.shared.hasAuthToken else { return }
        isSignedIn = (try? await APIClient.shared.validateSession()) == true
        if !isSignedIn { APIClient.shared.clearAuthToken() }
        if isSignedIn { NotificationManager.shared.registerIfAuthorized() }
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
            guard try await APIClient.shared.validateSession() else {
                APIClient.shared.clearAuthToken()
                throw APIError.unauthorized
            }
            isSignedIn = true
            errorMessage = nil
            NotificationManager.shared.registerIfAuthorized()
        } catch {
            errorMessage = "Couldn't sign in: \(error.localizedDescription)"
        }
    }

#if DEBUG && targetEnvironment(simulator)
    func signInForSimulatorDevelopment() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                try await APIClient.shared.signInForSimulatorDevelopment()
                guard try await APIClient.shared.validateSession() else {
                    APIClient.shared.clearAuthToken()
                    throw APIError.unauthorized
                }
                isSignedIn = true
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't create the local Simulator session: \(error.localizedDescription)"
            }
        }
    }
#endif

    func signOut() {
        Task {
            await NotificationManager.shared.unregisterCurrentDevice()
            await APIClient.shared.signOut()
            isSignedIn = false
        }
    }

    func handleAccountDeletionAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            accountDeletionError = error.localizedDescription
        case .success(let authorization):
            Task { await deleteAccount(with: authorization) }
        }
    }

    private func deleteAccount(with authorization: ASAuthorization) async {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let codeData = credential.authorizationCode,
            let authorizationCode = String(data: codeData, encoding: .utf8),
            let nonce = currentNonce
        else {
            accountDeletionError = "Apple didn't return the credential needed to delete this account."
            return
        }

        isDeletingAccount = true
        accountDeletionError = nil
        defer { isDeletingAccount = false }
        do {
            try await APIClient.shared.storeAppleDeletionCredential(
                authorizationCode: authorizationCode,
                nonce: nonce
            )
            try await APIClient.shared.deleteAccount()
            NotificationManager.shared.accountDidDelete()
            isSignedIn = false
        } catch {
            accountDeletionError = "Account deletion couldn't finish: \(error.localizedDescription)"
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
