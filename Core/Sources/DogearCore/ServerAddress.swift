import Foundation

enum ServerAddress {
    /// Turns what the reader typed into a Server URL.
    ///
    /// Plain HTTP is accepted only for a Tailscale address, where WireGuard already encrypts
    /// the traffic, and is refused everywhere else so credentials never travel unencrypted.
    /// A missing scheme means HTTP for a Tailscale address (how a Server on a tailnet usually
    /// answers) and HTTPS for anything else.
    static func parse(_ input: String) throws(SignInError) -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if !text.contains("://") {
            let scheme = URLComponents(string: "https://" + text)?.host.map(isTailnet) == true ? "http" : "https"
            text = "\(scheme)://" + text
        }

        guard let components = URLComponents(string: text),
              let host = components.host, !host.isEmpty,
              let url = components.url
        else { throw .invalidAddress }

        switch components.scheme?.lowercased() {
        case "https": return url
        case "http" where isTailnet(host): return url
        case "http": throw .insecureAddress
        default: throw .invalidAddress
        }
    }

    /// Host names ignore case, so the same Server can be typed differently.
    static func isSame(_ a: URL, _ b: URL) -> Bool {
        a.host()?.lowercased() == b.host()?.lowercased() && a.port == b.port && a.path() == b.path()
    }

    /// A host only reachable through Tailscale: a MagicDNS name (`*.ts.net`, or a bare machine
    /// name), a 100.64.0.0/10 address, or an address in Tailscale's fd7a:115c:a1e0::/48.
    static func isTailnet(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host.hasSuffix(".ts.net") { return true }
        if host.hasPrefix("fd7a:115c:a1e0:") { return true }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false).compactMap { UInt8($0) }
        if octets.count == 4, host.split(separator: ".").count == 4 {
            return octets[0] == 100 && (64 ... 127).contains(octets[1])
        }
        // A bare machine name: MagicDNS resolves it on the tailnet. `localhost` isn't one.
        return !host.contains(".") && !host.contains(":") && host != "localhost"
    }
}
