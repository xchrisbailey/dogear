import Foundation

enum ServerAddress {
    /// Turns what the reader typed into a Server URL. A missing scheme means HTTPS;
    /// plain HTTP is refused so credentials never travel unencrypted.
    static func parse(_ input: String) throws(SignInError) -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if !text.contains("://") { text = "https://" + text }

        guard let components = URLComponents(string: text),
              let host = components.host, !host.isEmpty,
              let url = components.url
        else { throw .invalidAddress }

        switch components.scheme?.lowercased() {
        case "https": return url
        case "http": throw .insecureAddress
        default: throw .invalidAddress
        }
    }

    /// Host names ignore case, so the same Server can be typed differently.
    static func isSame(_ a: URL, _ b: URL) -> Bool {
        a.host()?.lowercased() == b.host()?.lowercased() && a.port == b.port && a.path() == b.path()
    }
}
