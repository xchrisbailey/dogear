import DogearCore
import Foundation
import Synchronization
import UIKit

/// Runs Downloads in a background URLSession, so they carry on after the reader leaves the app
/// and survive iOS suspending or relaunching it. Each task's `taskDescription` is its transfer id.
nonisolated final class BackgroundTransport: NSObject, DownloadTransport, URLSessionDownloadDelegate, Sendable {
    static let identifier = "computer.srcery.dogear.downloads"

    private let state = Mutex<(downloads: Downloads?, session: URLSession?)>((nil, nil))

    /// Creates the session only once `downloads` can hear its events, which may include ones
    /// from before a relaunch.
    func attach(_ downloads: Downloads) {
        state.withLock { $0.downloads = downloads }
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        state.withLock { $0.session = session }
    }

    private var session: URLSession? { state.withLock { $0.session } }
    private var downloads: Downloads? { state.withLock { $0.downloads } }

    func start(_ transfer: DownloadTransfer) async {
        guard let task = session?.downloadTask(with: transfer.request) else { return }
        task.taskDescription = transfer.id
        task.resume()
    }

    func cancel(_ transferIDs: [String]) async {
        guard let session else { return }
        for task in await session.allTasks where transferIDs.contains(task.taskDescription ?? "") {
            task.cancel()
        }
    }

    func runningTransferIDs() async -> [String] {
        guard let session else { return [] }
        return await session.allTasks
            .filter { $0.state == .running || $0.state == .suspended }
            .compactMap(\.taskDescription)
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription, let downloads else { return }
        Task { await downloads.transferProgressed(id, bytesWritten: totalBytesWritten, bytesExpected: totalBytesExpectedToWrite) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription, let downloads else { return }
        // The system deletes `location` as soon as this returns, so it's moved before going async.
        let staged = FileManager.default.temporaryDirectory.appending(path: "download-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: staged)
        } catch {
            Task { await downloads.transferFailed(id) }
            return
        }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        Task { await downloads.transferFinished(id, status: status, file: staged) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        // Cancelled means Dogear removed the Download itself.
        guard let error, (error as? URLError)?.code != .cancelled,
              let id = task.taskDescription, let downloads
        else { return }
        Task { await downloads.transferFailed(id) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in BackgroundEvents.finish() }
    }
}

/// Holds iOS's completion handler while it relaunches the app to deliver Download events.
enum BackgroundEvents {
    private static var completion: (() -> Void)?

    static func handle(_ completion: @escaping () -> Void) {
        self.completion = completion
    }

    static func finish() {
        completion?()
        completion = nil
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == BackgroundTransport.identifier else {
            completionHandler()
            return
        }
        BackgroundEvents.handle(completionHandler)
    }
}
