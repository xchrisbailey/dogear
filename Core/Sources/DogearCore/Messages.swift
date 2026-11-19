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

extension ServerStatus {
    /// What to tell the reader, or nil when all is well. A changed Server matters more: going
    /// back online won't fix it.
    public var message: String? {
        if hasChanged { return RequestError.serverChanged.errorDescription }
        if !isReachable { return "Offline: can't reach your Server. Your saved library, Downloads and reading progress still work, and progress syncs once it's back." }
        return nil
    }
}

extension RequestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .signedOut:
            "You're signed out."
        case .needsSignIn:
            "Your sign-in has expired. Sign in again to sync."
        case .unreachable:
            "Can't reach your Server. Showing your saved library."
        case .rateLimited:
            "Your Server is turning away requests for now. Try again in a few minutes."
        case .serverChanged:
            "The Server's responses have changed shape. Update Dogear."
        }
    }
}

extension BookFile.Format {
    public var name: String {
        switch self {
        case .epub: "EPUB"
        case .pdf: "PDF"
        case .audiobook: "Audiobook"
        case .mobi: "MOBI"
        case .azw3: "AZW3"
        case .fb2: "FB2"
        case .comic: "Comic"
        case .other: "Other"
        }
    }
}

extension BookKind {
    public var name: String {
        switch self {
        case .all: "All"
        case .ebooks: "Ebooks"
        case .audiobooks: "Audiobooks"
        }
    }
}

extension Navigation {
    /// The title for browsing `scope`.
    public func name(of scope: BookScope) -> String {
        switch scope {
        case .everything: "Library"
        case let .library(id): libraries.first { $0.id == id }?.name ?? "Library"
        case let .shelf(id): shelves.first { $0.id == id }?.name ?? "Library"
        }
    }
}

extension DownloadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAllowed:
            "Your Grimmory account isn't allowed to download."
        case .notSupported:
            "Dogear can't open this format, so it can't download it."
        case .couldNotSave:
            "Couldn't save the Download on this device. Check your free space."
        case let .request(error):
            error.errorDescription
        }
    }
}
