import DogearCore
import Foundation
@preconcurrency import ReadiumShared

/// Signs every request Readium makes for a Server EPUB's entries with the current access token.
/// A per-request delegate rather than fixed headers, because the token changes when it's refreshed.
nonisolated final class EPUBRequestSigner: DefaultHTTPClientDelegate, Sendable {
    private static let retriedKey = "dogear.retried"
    private let epub: ServerEPUB

    init(epub: ServerEPUB) {
        self.epub = epub
    }

    func httpClient(_ httpClient: DefaultHTTPClient, willStartRequest request: HTTPRequest) async -> HTTPResult<HTTPRequestConvertible> {
        await sign(request) { urlRequest throws(RequestError) in try await self.epub.authorize(urlRequest) }
    }

    func httpClient(_ httpClient: DefaultHTTPClient, recoverRequest request: HTTPRequest, fromError error: HTTPError) async -> HTTPResult<HTTPRequestConvertible> {
        // Retry once: a second 401 with fresh tokens means the reader can't see this Book.
        guard case let .errorResponse(response) = error, response.status.rawValue == 401,
              request.userInfo[Self.retriedKey] == nil
        else { return .failure(error) }
        var retry = request
        retry.userInfo[Self.retriedKey] = true
        return await sign(retry) { urlRequest throws(RequestError) in try await self.epub.reauthorize(afterRejecting: urlRequest) }
    }

    private func sign(
        _ request: HTTPRequest,
        with signer: (URLRequest) async throws(RequestError) -> URLRequest
    ) async -> HTTPResult<HTTPRequestConvertible> {
        var urlRequest = URLRequest(url: request.url.url)
        urlRequest.allHTTPHeaderFields = request.headers
        let signed: URLRequest
        do {
            signed = try await signer(urlRequest)
        } catch {
            return .failure(.other(error))
        }
        guard let url = signed.url.flatMap(HTTPURL.init(url:)) else {
            return .failure(.malformedRequest(url: signed.url?.absoluteString))
        }
        var request = request
        request.url = url
        request.headers = signed.allHTTPHeaderFields ?? request.headers
        return .success(request)
    }
}
