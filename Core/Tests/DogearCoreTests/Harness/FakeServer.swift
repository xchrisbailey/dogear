import Foundation
import Synchronization

/// Intercepts HTTP for one URLSession and hands each request to a handler.
/// Sessions are routed by a per-session header instead of a global registration
/// so tests can run in parallel.
final class FakeServer: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        case response(status: Int, body: Data, contentType: String = "application/json")
        case failure(URLError.Code)
    }

    typealias Handler = @Sendable (URLRequest, Data?) -> Reply

    private static let handlers = Mutex<[String: Handler]>([:])
    private static let routingHeader = "X-Fake-Server"

    static func session(_ handler: @escaping Handler) -> URLSession {
        let id = UUID().uuidString
        handlers.withLock { $0[id] = handler }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeServer.self]
        config.httpAdditionalHeaders = [routingHeader: id]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: Self.routingHeader) ?? ""
        let handler = Self.handlers.withLock { $0[id] }
        let reply = handler?(request, Self.body(of: request)) ?? .response(status: 500, body: Data())
        switch reply {
        case let .response(status, body, contentType):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": contentType]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    // URLSession moves httpBody into a stream before it reaches a URLProtocol.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
