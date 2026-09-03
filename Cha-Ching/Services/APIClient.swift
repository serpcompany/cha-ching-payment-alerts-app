import Foundation
import Security

enum APIError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case unauthorized
    case notFound
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "The API URL isn't configured."
        case .invalidResponse: "The server returned an invalid response."
        case .unauthorized: "Your session expired. Please sign in again."
        case .notFound: "The requested item was not found."
        case .server(let message): message
        }
    }
}

private struct ErrorResponse: Decodable {
    let error: String
}

private struct AppleSignInRequest: Encodable {
    let provider = "apple"
    let idToken: AppleIDToken

    struct AppleIDToken: Encodable {
        let token: String
        let nonce: String
        let user: AppleUser?
    }

    struct AppleUser: Encodable {
        let name: AppleName

        struct AppleName: Encodable {
            let firstName: String?
            let lastName: String?
        }
    }
}

private struct AppleCredentialRequest: Encodable {
    let authorizationCode: String
    let nonce: String
}

actor APIClient {
    static let shared = APIClient()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        decoder.dateDecodingStrategy = .iso8601
    }

    nonisolated var hasAuthToken: Bool { KeychainToken.load() != nil }

    private var baseURL: URL {
        get throws {
            guard
                let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
                let url = URL(string: value),
                url.scheme != nil
            else { throw APIError.invalidConfiguration }
            return url
        }
    }

    func signInWithApple(
        idToken: String,
        nonce: String,
        firstName: String?,
        lastName: String?
    ) async throws {
        let hasName = firstName != nil || lastName != nil
        let user = hasName
            ? AppleSignInRequest.AppleUser(name: .init(firstName: firstName, lastName: lastName))
            : nil
        let payload = AppleSignInRequest(idToken: .init(token: idToken, nonce: nonce, user: user))
        var request = try makeRequest(path: "/api/auth/sign-in/social", method: "POST", authorized: false)
        request.httpBody = try encoder.encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await perform(request)
        guard let token = response.value(forHTTPHeaderField: "set-auth-token"), !token.isEmpty else {
            throw APIError.invalidResponse
        }
        try KeychainToken.save(token)
    }

#if DEBUG && targetEnvironment(simulator)
    /// Creates a Better Auth anonymous session against the local development
    /// Worker. This endpoint is not registered by staging or production.
    func signInForSimulatorDevelopment() async throws {
        var request = try makeRequest(
            path: "/api/auth/sign-in/anonymous",
            method: "POST",
            authorized: false
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (_, response) = try await perform(request)
        guard let token = response.value(forHTTPHeaderField: "set-auth-token"), !token.isEmpty else {
            throw APIError.invalidResponse
        }
        try KeychainToken.save(token)
    }
#endif

    func validateSession() async throws -> Bool {
        let request = try makeRequest(path: "/api/auth/get-session", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { return false }
        guard (200..<300).contains(http.statusCode) else {
            try throwServerError(data: data, status: http.statusCode)
        }
        return String(data: data, encoding: .utf8) != "null"
    }

    func signOut() async {
        if let request = try? makeRequest(path: "/api/auth/sign-out", method: "POST") {
            _ = try? await perform(request)
        }
        clearAuthToken()
    }

    func storeAppleDeletionCredential(authorizationCode: String, nonce: String) async throws {
        let _: StoredAppleCredentialResponse = try await post(
            "/v1/account/apple-credential",
            body: AppleCredentialRequest(authorizationCode: authorizationCode, nonce: nonce)
        )
    }

    func deleteAccount() async throws {
        try await delete("/v1/account")
        clearAuthToken()
    }

    func get<Response: Decodable>(_ path: String) async throws -> Response {
        let request = try makeRequest(path: path, method: "GET")
        let (data, _) = try await perform(request)
        return try decoder.decode(Response.self, from: data)
    }

    func get<Response: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem]
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: "GET", queryItems: queryItems)
        let (data, _) = try await perform(request)
        return try decoder.decode(Response.self, from: data)
    }

    func get<Response: Decodable>(pathComponents: [String]) async throws -> Response {
        let request = try makeRequest(pathComponents: pathComponents, method: "GET")
        let (data, _) = try await perform(request)
        return try decoder.decode(Response.self, from: data)
    }

    func post<Response: Decodable>(_ path: String) async throws -> Response {
        var request = try makeRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (data, _) = try await perform(request)
        return try decoder.decode(Response.self, from: data)
    }

    func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, _) = try await perform(request)
        return try decoder.decode(Response.self, from: data)
    }

    func put<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, _) = try await perform(request)
        return try decoder.decode(Response.self, from: data)
    }

    func delete(_ path: String) async throws {
        let request = try makeRequest(path: path, method: "DELETE")
        _ = try await perform(request)
    }

    func deleteResponse<Response: Decodable>(
        _ path: String,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: "DELETE")
        let (data, _) = try await perform(request)
        return try decoder.decode(type, from: data)
    }

    nonisolated func clearAuthToken() {
        KeychainToken.delete()
    }

    private func makeRequest(
        path: String,
        method: String,
        authorized: Bool = true,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        let request = URLRequest(url: try Self.requestURL(
            baseURL: baseURL,
            path: path,
            queryItems: queryItems
        ))
        return configured(request, method: method, authorized: authorized)
    }

    private func makeRequest(
        pathComponents: [String],
        method: String,
        authorized: Bool = true
    ) throws -> URLRequest {
        let request = URLRequest(url: Self.requestURL(
            baseURL: try baseURL,
            pathComponents: pathComponents
        ))
        return configured(request, method: method, authorized: authorized)
    }

    private func configured(
        _ initialRequest: URLRequest,
        method: String,
        authorized: Bool
    ) -> URLRequest {
        var request = initialRequest
        request.httpMethod = method
        // Better Auth returns a bearer token for the native client. Do not let
        // URLSession attach a stale browser-style cookie to a later sign-in.
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized, let token = KeychainToken.load() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    nonisolated static func requestURL(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = baseURL.appendingPathComponent(relativePath)
        guard !queryItems.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidConfiguration
        }
        components.queryItems = queryItems
        guard let result = components.url else { throw APIError.invalidConfiguration }
        return result
    }

    nonisolated static func requestURL(baseURL: URL, pathComponents: [String]) -> URL {
        pathComponents.reduce(baseURL) { partial, component in
            partial.appendingPathComponent(component)
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.unauthorized }
            if http.statusCode == 404 { throw APIError.notFound }
            try throwServerError(data: data, status: http.statusCode)
        }
        return (data, http)
    }

    private func throwServerError(data: Data, status: Int) throws -> Never {
        let message = (try? decoder.decode(ErrorResponse.self, from: data).error)
            ?? HTTPURLResponse.localizedString(forStatusCode: status)
        throw APIError.server(message)
    }
}

private struct StoredAppleCredentialResponse: Decodable {
    let stored: Bool
}

private enum KeychainToken {
    private static let service = "com.serpcompany.chaching.auth"
    private static let account = "better-auth-session"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) throws {
        delete()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8)
        ]
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw APIError.server("Couldn't securely save your session.")
        }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
