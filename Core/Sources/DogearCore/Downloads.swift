import Foundation

/// Book files stored on the device so they read and play without the Server.
///
/// Only for readers the Server lets download (`canDownload`, or admins), matching Grimmory's own
/// rule, including for files whose endpoints don't check it. Downloads are only ever removed by
/// the reader. The transfers themselves run in a `DownloadTransport`, a background URLSession in
/// the app, which reports back through `transferProgressed`, `transferFinished` and `transferFailed`.
public actor Downloads {
    private let account: Account
    private let directory: URL
    private let transport: any DownloadTransport
    private var manifest: Manifest
    /// The access token each running transfer was sent with, to refresh it once if refused.
    private var sentTokens: [String: String] = [:]
    private var observers: [UUID: AsyncStream<DownloadList>.Continuation] = [:]
    private var published: DownloadList?

    public init(account: Account, directory: URL, transport: any DownloadTransport) throws {
        self.account = account
        self.directory = directory
        self.transport = transport
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Kept out of backups: they can be downloaded again, and audiobooks are large.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = directory
        try? excluded.setResourceValues(values)
        let data = try? Data(contentsOf: directory.appending(path: Self.manifestName))
        manifest = data.flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) } ?? Manifest()
    }

    /// The app's Downloads in Application Support, which iOS doesn't purge.
    public static func onDevice(account: Account, transport: any DownloadTransport) throws -> Downloads {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try Downloads(account: account, directory: support.appending(path: "Downloads"), transport: transport)
    }

    public var list: DownloadList {
        DownloadList(canDownload: manifest.canDownload, downloads: manifest.entries.map(\.download))
    }

    /// The current `list`, then every change to it.
    public func updates() -> AsyncStream<DownloadList> {
        let (stream, continuation) = AsyncStream<DownloadList>.makeStream()
        let id = UUID()
        observers[id] = continuation
        continuation.yield(list)
        continuation.onTermination = { _ in Task { await self.removeObserver(id) } }
        return stream
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private struct UserInfo: Decodable {
        var canDownload: Bool?
        var admin: Bool?
    }

    /// Asks the Server whether the reader may download. Offline, the last answer stands.
    public func checkPermission() async {
        guard let server = await account.session?.server,
              let user = try? await account.fetch(UserInfo.self, URLRequest(url: server.appending(path: "api/v1/app/users/me")))
        else { return }
        manifest.canDownload = user.canDownload == true || user.admin == true
        save()
    }

    // MARK: Downloading

    /// Starts downloading `file`, or carries on with one that failed. Returns once its transfers
    /// have started; progress shows in `list`.
    public func download(_ file: BookFile, of book: Book) async throws(DownloadError) {
        guard manifest.canDownload else { throw .notAllowed }
        guard file.isSupported, [.epub, .pdf, .audiobook].contains(file.format) else { throw .notSupported }
        if manifest.entries.contains(where: { $0.bookFileID == file.id }) {
            try await retry(bookFileID: file.id)
            return
        }
        guard let server = await account.session?.server else { throw .request(.signedOut) }
        var entry = Entry(bookID: book.id, bookFileID: file.id, format: file.format, title: book.title, parts: [])
        let fileDownload = server.appending(path: file.id == book.primaryFileID
            ? "api/v1/books/\(book.id)/download"
            : "api/v1/books/\(book.id)/files/\(file.id)/download")
        switch file.format {
        case .epub:
            entry.parts = [Part(url: fileDownload, fileName: "book.epub")]
        case .pdf:
            entry.parts = [Part(url: fileDownload, fileName: "book.pdf")]
        default:
            let info = try await audiobookInfo(bookID: book.id, server: server)
            try write(info.data, to: directory(of: file.id).appending(path: Self.infoName))
            if info.tracks.isEmpty {
                entry.parts = [Part(url: fileDownload, fileName: info.wholeBookName, expectedBytes: info.totalSizeBytes ?? 0)]
            } else {
                // Track by Track rather than the Server's ZIP of the folder, so nothing needs unzipping.
                let tracks = server.appending(path: "api/v1/audiobooks/\(book.id)/track")
                entry.parts = info.tracks.map { track in
                    Part(
                        url: tracks.appending(path: "\(track.index)/stream").appending(queryItems: [URLQueryItem(name: "bookType", value: "AUDIOBOOK")]),
                        fileName: track.fileName, expectedBytes: track.fileSizeBytes ?? 0
                    )
                }
            }
        }
        manifest.entries.append(entry)
        save()
        for part in entry.parts {
            await start(part)
        }
    }

    /// Carries on with a failed Download from what already arrived. Needs only the Book file,
    /// so a Download can be retried after its Book has left the library.
    public func retry(bookFileID: Int) async throws(DownloadError) {
        guard manifest.canDownload else { throw .notAllowed }
        guard let index = manifest.entries.firstIndex(where: { $0.bookFileID == bookFileID }),
              manifest.entries[index].isFailed
        else { return }
        manifest.entries[index].isFailed = false
        manifest.entries[index].failure = nil
        save()
        for part in manifest.entries[index].parts where !part.isDone {
            await start(part)
        }
    }

    private func audiobookInfo(bookID: Int, server: URL) async throws(DownloadError) -> StoredAudiobookInfo {
        let url = server.appending(path: "api/v1/audiobooks/\(bookID)/info")
            .appending(queryItems: [URLQueryItem(name: "bookType", value: "AUDIOBOOK")])
        let data: Data
        do {
            data = try await account.fetchData(URLRequest(url: url))
        } catch {
            throw .request(error)
        }
        guard var info = try? JSONDecoder().decode(StoredAudiobookInfo.self, from: data),
              (try? JSONDecoder().decode(AudiobookInfo.self, from: data)) != nil
        else { throw .request(.serverChanged) }
        info.data = data
        return info
    }

    private func start(_ part: Part) async {
        let token: String
        do {
            token = try await account.accessToken()
        } catch {
            fail(transferID: part.transferID, because: error == .needsSignIn ? .needsSignIn : .unreachable)
            return
        }
        await send(part, token: token)
    }

    private func send(_ part: Part, token: String) async {
        var request = URLRequest(url: part.url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        sentTokens[part.transferID] = token
        await transport.start(DownloadTransfer(id: part.transferID, request: request))
    }

    /// Starts again whatever the transport lost, such as transfers the system dropped when the
    /// app was quit from the app switcher. Call after launch.
    public func resumeTransfers() async {
        let running = Set(await transport.runningTransferIDs())
        for entry in manifest.entries where !entry.isFailed {
            for part in entry.parts where !part.isDone && !running.contains(part.transferID) {
                await start(part)
            }
        }
    }

    // MARK: Transport events

    public func transferProgressed(_ transferID: String, bytesWritten: Int64, bytesExpected: Int64) {
        guard let (entry, part) = locate(transferID) else { return }
        manifest.entries[entry].parts[part].writtenBytes = bytesWritten
        if bytesExpected > 0 { manifest.entries[entry].parts[part].expectedBytes = bytesExpected }
        publish(onlyIfMoved: true)
    }

    /// The Server answered; `file` holds its body and is moved or deleted here.
    public func transferFinished(_ transferID: String, status: Int, file: URL) async {
        defer { try? FileManager.default.removeItem(at: file) }
        guard let (entry, part) = locate(transferID) else { return }
        switch status {
        case 200:
            let bookFileID = manifest.entries[entry].bookFileID
            let destination = directory(of: bookFileID).appending(path: manifest.entries[entry].parts[part].fileName)
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: file, to: destination)
            } catch {
                fail(transferID: transferID, because: .couldNotSave)
                return
            }
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            manifest.entries[entry].parts[part].isDone = true
            manifest.entries[entry].parts[part].writtenBytes = size
            manifest.entries[entry].parts[part].expectedBytes = size
            sentTokens[transferID] = nil
            save()
        case 401 where !manifest.entries[entry].parts[part].hasRetried:
            // Queued transfers can start after the access token has expired.
            manifest.entries[entry].parts[part].hasRetried = true
            let retry = manifest.entries[entry].parts[part]
            guard let token = try? await account.accessToken(replacing: sentTokens[transferID] ?? "") else {
                fail(transferID: transferID, because: .needsSignIn)
                return
            }
            await send(retry, token: token)
        case 403:
            // The admin has taken the permission away since it was last checked.
            manifest.canDownload = false
            fail(transferID: transferID, because: .notAllowed)
        case 401:
            fail(transferID: transferID, because: .needsSignIn)
        case 404:
            fail(transferID: transferID, because: .gone)
        default:
            fail(transferID: transferID, because: .serverError)
        }
    }

    /// The transfer couldn't reach the Server or was cut off.
    public func transferFailed(_ transferID: String) {
        fail(transferID: transferID, because: .unreachable)
    }

    private func fail(transferID: String, because failure: Download.Failure) {
        guard let (entry, _) = locate(transferID) else { return }
        manifest.entries[entry].isFailed = true
        manifest.entries[entry].failure = failure
        let others = manifest.entries[entry].parts.filter { !$0.isDone && $0.transferID != transferID }.map(\.transferID)
        sentTokens[transferID] = nil
        save()
        // The rest would only finish into a Download that's already failed.
        if !others.isEmpty { Task { await transport.cancel(others) } }
    }

    private func locate(_ transferID: String) -> (entry: Int, part: Int)? {
        for (entryIndex, entry) in manifest.entries.enumerated() {
            if let partIndex = entry.parts.firstIndex(where: { $0.transferID == transferID }) {
                return (entryIndex, partIndex)
            }
        }
        return nil
    }

    // MARK: Opening

    /// The Download of `file`, when it has finished.
    public func downloaded(_ file: BookFile) -> DownloadedBookFile? {
        guard let entry = manifest.entries.first(where: { $0.bookFileID == file.id }), entry.download.state == .finished else { return nil }
        let folder = directory(of: entry.bookFileID)
        switch entry.format {
        case .epub: return .epub(folder.appending(path: entry.parts[0].fileName))
        case .pdf: return .pdf(folder.appending(path: entry.parts[0].fileName))
        case .audiobook:
            guard let data = try? Data(contentsOf: folder.appending(path: Self.infoName)),
                  let info = try? JSONDecoder().decode(StoredAudiobookInfo.self, from: data)
            else { return nil }
            return .audiobook(DownloadedAudiobook(bookID: entry.bookID, folder: folder, infoData: data, info: info))
        default: return nil
        }
    }

    // MARK: Removing

    public func remove(bookFileID: Int) async {
        await remove { $0.bookFileID == bookFileID }
    }

    /// Leaves Downloads still in progress or failed alone.
    public func removeAllFinished() async {
        await remove { $0.download.state == .finished }
    }

    /// Every Download, for signing out: another account or Server numbers its Books differently.
    public func removeAll() async {
        await remove { _ in true }
    }

    private func remove(where shouldRemove: (Entry) -> Bool) async {
        let removed = manifest.entries.filter(shouldRemove)
        guard !removed.isEmpty else { return }
        manifest.entries.removeAll(where: shouldRemove)
        save()
        let transfers = removed.flatMap { $0.parts.filter { !$0.isDone }.map(\.transferID) }
        if !transfers.isEmpty { await transport.cancel(transfers) }
        for entry in removed {
            try? FileManager.default.removeItem(at: directory(of: entry.bookFileID))
        }
    }

    // MARK: Storage

    private static let manifestName = "Downloads.json"
    private static let infoName = "info.json"

    private func directory(of bookFileID: Int) -> URL {
        directory.appending(path: "\(bookFileID)")
    }

    private func write(_ data: Data, to url: URL) throws(DownloadError) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw .couldNotSave
        }
    }

    /// Saves the manifest and tells observers. A failed save leaves the in-memory state working
    /// until the app quits; a relaunch then sees the last saved one.
    private func save() {
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: directory.appending(path: Self.manifestName), options: .atomic)
        }
        publish(onlyIfMoved: false)
    }

    /// Progress arrives many times a second; observers hear about whole percents.
    private func publish(onlyIfMoved: Bool) {
        let current = list
        if onlyIfMoved, let published, !current.hasMoved(since: published) { return }
        published = current
        for observer in observers.values { observer.yield(current) }
    }
}

/// Runs the HTTP transfers for `Downloads`, in the background in the app.
public protocol DownloadTransport: Sendable {
    func start(_ transfer: DownloadTransfer) async
    func cancel(_ transferIDs: [String]) async
    /// Transfers still running, such as ones the background session kept across a relaunch.
    func runningTransferIDs() async -> [String]
}

public struct DownloadTransfer: Sendable {
    public let id: String
    public let request: URLRequest

    public init(id: String, request: URLRequest) {
        self.id = id
        self.request = request
    }
}

public enum DownloadError: Error, Equatable {
    /// The reader's account can't download.
    case notAllowed
    case notSupported
    case couldNotSave
    case request(RequestError)
}

public struct Download: Sendable, Equatable, Identifiable {
    public enum State: Sendable, Equatable {
        /// `progress` from 0 to 1.
        case downloading(progress: Double)
        case finished
        /// Downloading again carries on from what already arrived.
        case failed
    }

    /// Why a Download failed, so the reader knows whether trying again can help.
    public enum Failure: String, Sendable, Codable {
        /// The connection to the Server was lost, or it couldn't be reached.
        case unreachable
        /// The Server wants the reader to sign in again.
        case needsSignIn
        /// The account may no longer download.
        case notAllowed
        /// The Book file has gone from the Server.
        case gone
        /// The Server answered with an error.
        case serverError
        /// The device couldn't store it, usually for lack of space.
        case couldNotSave

        public var message: String {
            switch self {
            case .unreachable: "Lost the connection to your Server."
            case .needsSignIn: "Your sign-in expired. Sign in again, then retry."
            case .notAllowed: "Your account can no longer download."
            case .gone: "This Book file is no longer on your Server."
            case .serverError: "Your Server couldn't send it."
            case .couldNotSave: "Couldn't save it on this device. It may be out of space."
            }
        }

        /// Whether retrying can work as things stand.
        public var canRetry: Bool {
            self != .notAllowed && self != .gone
        }
    }

    public var bookID: Int
    public var bookFileID: Int
    public var format: BookFile.Format
    /// The Book's title when downloaded, so it's named even if the Book leaves the library.
    public var title: String
    public var state: State
    /// Why it failed; nil unless `state` is `.failed`, and for Downloads that failed before
    /// Dogear kept the reason.
    public var failure: Failure?
    /// Storage used on the device.
    public var bytes: Int64

    public var id: Int { bookFileID }
}

public struct DownloadList: Sendable, Equatable {
    /// False hides every download option.
    public var canDownload: Bool
    public var downloads: [Download]

    public init(canDownload: Bool = false, downloads: [Download] = []) {
        self.canDownload = canDownload
        self.downloads = downloads
    }

    public var totalBytes: Int64 {
        downloads.reduce(0) { $0 + $1.bytes }
    }

    public func bytes(ofBook bookID: Int) -> Int64 {
        downloads.filter { $0.bookID == bookID }.reduce(0) { $0 + $1.bytes }
    }

    public func download(bookFileID: Int) -> Download? {
        downloads.first { $0.bookFileID == bookFileID }
    }

    fileprivate func hasMoved(since other: DownloadList) -> Bool {
        guard canDownload == other.canDownload, downloads.count == other.downloads.count else { return true }
        return zip(downloads, other.downloads).contains { now, then in
            guard case let .downloading(progress) = now.state, case let .downloading(previous) = then.state else {
                return now != then
            }
            return abs(progress - previous) >= 0.01
        }
    }
}

/// A finished Download, opened from the device.
public enum DownloadedBookFile: Sendable {
    case epub(URL)
    case pdf(URL)
    case audiobook(DownloadedAudiobook)
}

/// A downloaded audiobook. Plays like a streamed one, from files on the device.
public struct DownloadedAudiobook: AudiobookSource {
    public let bookID: Int
    private let stream: AudiobookStream
    private let infoData: Data

    fileprivate init(bookID: Int, folder: URL, infoData: Data, info: StoredAudiobookInfo) {
        self.bookID = bookID
        self.infoData = infoData
        let tracks = Dictionary(info.tracks.map { ($0.index, folder.appending(path: $0.fileName)) }, uniquingKeysWith: { first, _ in first })
        stream = AudiobookStream(wholeBook: folder.appending(path: info.wholeBookName), tracks: tracks)
    }

    public func info() async throws(RequestError) -> AudiobookInfo {
        guard let info = try? JSONDecoder().decode(AudiobookInfo.self, from: infoData) else { throw .serverChanged }
        return info
    }

    public func streamUpdates() async -> AsyncStream<AudiobookStream> {
        AsyncStream { continuation in
            continuation.yield(stream)
            continuation.finish()
        }
    }

    /// Files on the device have no token to refresh; a failure is a real one.
    public func reauthorize(afterRejecting rejected: AudiobookStream) async throws(RequestError) -> AudiobookStream {
        throw .unreachable
    }
}

/// The parts of the Server's audiobook info a Download needs to name its files.
private struct StoredAudiobookInfo: Decodable {
    struct Track: Decodable {
        var index: Int
        var fileName: String
        var fileSizeBytes: Int64?

        private enum CodingKeys: String, CodingKey { case index, fileName, fileSizeBytes }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            index = try container.decode(Int.self, forKey: .index)
            fileSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .fileSizeBytes)
            // The player needs the extension to know the audio format; the name itself is the Server's.
            let ext = (try container.decodeIfPresent(String.self, forKey: .fileName)).map { ($0 as NSString).pathExtension.lowercased() } ?? ""
            fileName = "track-\(index).\(ext.isEmpty ? "mp3" : ext)"
        }
    }

    var codec: String?
    var totalSizeBytes: Int64?
    var tracks: [Track]
    var data = Data()

    private enum CodingKeys: String, CodingKey { case codec, totalSizeBytes, tracks }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        codec = try container.decodeIfPresent(String.self, forKey: .codec)
        totalSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .totalSizeBytes)
        tracks = try container.decodeIfPresent([Track].self, forKey: .tracks) ?? []
    }

    /// Single-file audiobooks are M4B unless the Server says MP3.
    var wholeBookName: String {
        codec?.lowercased() == "mp3" ? "book.mp3" : "book.m4b"
    }
}

private struct Manifest: Codable {
    var canDownload = false
    var entries: [Entry] = []
}

private struct Entry: Codable {
    var bookID: Int
    var bookFileID: Int
    var format: BookFile.Format
    var title: String
    var parts: [Part]
    var isFailed = false
    /// Optional, so manifests saved before it existed still load.
    var failure: Download.Failure?

    var download: Download {
        let bytes = parts.filter(\.isDone).reduce(0) { $0 + $1.writtenBytes }
        let state: Download.State
        if parts.allSatisfy(\.isDone) {
            state = .finished
        } else if isFailed {
            state = .failed
        } else {
            let expected = parts.reduce(0) { $0 + max($1.expectedBytes, $1.writtenBytes) }
            let written = parts.reduce(0) { $0 + $1.writtenBytes }
            // Without sizes, count finished parts.
            let progress = expected > 0 ? Double(written) / Double(expected) : Double(parts.filter(\.isDone).count) / Double(max(parts.count, 1))
            state = .downloading(progress: min(progress, 1))
        }
        return Download(
            bookID: bookID, bookFileID: bookFileID, format: format, title: title, state: state,
            failure: state == .failed ? failure : nil, bytes: bytes
        )
    }
}

private struct Part: Codable {
    var transferID = UUID().uuidString
    var url: URL
    var fileName: String
    var expectedBytes: Int64 = 0
    var writtenBytes: Int64 = 0
    var isDone = false
    var hasRetried = false
}
