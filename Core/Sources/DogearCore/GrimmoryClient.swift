import Foundation

/// HTTP calls to a Grimmory Server's `/api/v1`.
struct GrimmoryClient {
    let server: URL
    let urlSession: URLSession

    struct LoginTokens: Decodable {
        var accessToken: String
        var refreshToken: String
        /// Access token lifetime in seconds, not a timestamp.
        var expires: TimeInterval
        var isDefaultPassword: Bool?
    }

    private struct Healthcheck: Decodable {
        struct Payload: Decodable { var version: String }
        var data: Payload
    }

    /// The healthcheck is public and Grimmory-shaped. Status alone proves nothing:
    /// Grimmory, and many other servers, answer unknown paths with a 200 web page.
    func confirmIsGrimmory() async throws(SignInError) {
        let (status, data) = try await send(URLRequest(url: url("healthcheck")))
        guard status == 200, (try? JSONDecoder().decode(Healthcheck.self, from: data)) != nil else {
            throw .notGrimmory
        }
    }

    func login(username: String, password: String) async throws(SignInError) -> LoginTokens {
        var request = URLRequest(url: url("auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["username": username, "password": password])
        let (status, data) = try await send(request)
        switch status {
        case 200: return try decode(LoginTokens.self, from: data)
        case 401: throw .wrongCredentials
        case 429: throw .rateLimited
        default: throw .serverChanged
        }
    }

    private struct Version: Decodable { var current: String }

    /// Best effort: a missing version is reported as a warning, never a failed sign-in.
    func serverVersion(accessToken: String) async -> String? {
        var request = URLRequest(url: url("version"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (status, data) = try? await send(request), status == 200 else { return nil }
        return try? JSONDecoder().decode(Version.self, from: data).current
    }

    private func url(_ path: String) -> URL {
        server.appending(path: "api/v1/\(path)")
    }

    private func send(_ request: URLRequest) async throws(SignInError) -> (Int, Data) {
        do {
            let (data, response) = try await urlSession.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch {
            throw .unreachable
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(SignInError) -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .serverChanged
        }
    }
}
