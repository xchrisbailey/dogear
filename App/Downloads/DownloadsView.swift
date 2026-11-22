import DogearCore
import SwiftUI

/// Storage used by Downloads, per Book and in total, and removing them.
struct DownloadsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingRemoveAll = false

    private var list: DownloadList { model.downloadList }

    /// Books in the order their first Download started.
    private var bookIDs: [Int] {
        list.downloads.map(\.bookID).reduce(into: []) { ids, id in
            if !ids.contains(id) { ids.append(id) }
        }
    }

    private var hasFinished: Bool {
        list.downloads.contains { $0.state == .finished }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(bookIDs, id: \.self) { bookID in
                    let downloads = list.downloads.filter { $0.bookID == bookID }
                    Section {
                        ForEach(downloads) { download in
                            DownloadRow(download: download)
                        }
                        .onDelete { offsets in
                            let removed = offsets.map { downloads[$0].bookFileID }
                            Task { for id in removed { await model.downloads?.remove(bookFileID: id) } }
                        }
                    } header: {
                        HStack {
                            Text(downloads.first?.title ?? "")
                            Spacer()
                            Text(Self.size(list.bytes(ofBook: bookID)))
                        }
                    }
                }
            }
            .overlay {
                if list.downloads.isEmpty {
                    ContentUnavailableView(
                        "No Downloads", systemImage: "arrow.down.circle",
                        description: Text("Book files you download stay on this device until you remove them.")
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !list.downloads.isEmpty {
                    Text("\(Self.size(list.totalBytes)) used on this device")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Remove All Finished", role: .destructive) { isConfirmingRemoveAll = true }
                        .disabled(!hasFinished)
                }
            }
            .confirmationDialog("Remove every finished Download from this device?", isPresented: $isConfirmingRemoveAll, titleVisibility: .visible) {
                Button("Remove All Finished", role: .destructive) {
                    Task { await model.downloads?.removeAllFinished() }
                }
            }
        }
    }

    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}

private struct DownloadRow: View {
    let download: Download

    @Environment(AppModel.self) private var model

    /// Retrying needs the permission, and a reason that another try could get past.
    private var canRetry: Bool {
        model.downloadList.canDownload && download.failure?.canRetry ?? true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(download.format.name)
                Spacer()
                switch download.state {
                case let .downloading(progress):
                    ProgressView(value: progress)
                        .frame(width: 80)
                case .finished:
                    Text(DownloadsView.size(download.bytes))
                        .foregroundStyle(.secondary)
                case .failed:
                    if canRetry {
                        Button("Retry", systemImage: "arrow.clockwise") {
                            Task { try? await model.downloads?.retry(bookFileID: download.bookFileID) }
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Label("Failed", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            if download.state == .failed {
                Text(download.failure?.message ?? "The download stopped before it finished.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Download and remove actions for each of a Book's files. Downloading is hidden when the
/// account can't; removing never is.
struct DownloadMenu: View {
    let book: Book
    @Binding var problem: String?

    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(book.files.filter(\.isSupported)) { file in
            let name = book.files.filter(\.isSupported).count > 1 ? " \(file.format.name)" : ""
            switch model.downloadList.download(bookFileID: file.id)?.state {
            case nil:
                if model.downloadList.canDownload {
                    Button("Download\(name)", systemImage: "arrow.down.circle") { start(file) }
                }
            case .failed:
                if model.downloadList.canDownload, model.downloadList.download(bookFileID: file.id)?.failure?.canRetry ?? true {
                    Button("Retry Download\(name)", systemImage: "arrow.clockwise") { start(file) }
                }
                Button("Remove Download\(name)", systemImage: "trash", role: .destructive) { remove(file) }
            case .downloading:
                Button("Cancel Download\(name)", systemImage: "xmark.circle", role: .destructive) { remove(file) }
            case .finished:
                Button("Remove Download\(name)", systemImage: "trash", role: .destructive) { remove(file) }
            }
        }
    }

    private func start(_ file: BookFile) {
        Task {
            do throws(DownloadError) {
                try await model.download(file, of: book)
            } catch {
                problem = error.errorDescription
            }
        }
    }

    private func remove(_ file: BookFile) {
        Task { await model.removeDownload(of: file) }
    }
}
