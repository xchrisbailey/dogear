import Foundation

extension SignInError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "That doesn't look like a Server address. Try something like https://grimmory.example."
        case .insecureAddress:
            "Dogear only connects over HTTPS so your password is never sent unencrypted. Use an https:// address for your Server."
        case .unreachable:
            "Couldn't reach a Server at that address. Check the address and that you're on the right network."
        case .notGrimmory:
            "Something answered at that address, but it isn't a Grimmory Server. Check the address."
        case .wrongCredentials:
            "Wrong username or password."
        case .rateLimited:
            "Too many failed sign-in attempts. Wait a few minutes and try again."
        case .defaultPassword:
            "This account still uses Grimmory's default password. Sign in to Grimmory in a browser, change your password, then come back."
        case .serverChanged:
            "The Server's responses have changed shape. Update Dogear."
        case .couldNotSaveSession:
            "Signed in, but couldn't save your sign-in on this device. Try again."
        }
    }
}

extension VersionWarning {
    public var message: String {
        switch self {
        case let .untested(serverVersion):
            "This Server runs Grimmory \(serverVersion). Dogear is tested with \(Session.testedServerVersion), so some things might misbehave."
        case .unknown:
            "Couldn't read this Server's Grimmory version. Dogear is tested with \(Session.testedServerVersion), so some things might misbehave."
        }
    }
}
