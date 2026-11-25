import AVKit
import DogearCore
import SwiftUI

/// Full-screen player for one audiobook Book file: the Pocket Player, in the app theme. The Book
/// is loaded as a cassette, and the tape on its reels is how far through the Book the listener is.
///
/// Closing it leaves the audiobook playing under the library; Eject stops it. Changing the theme
/// only redraws it: the file stays loaded and playing.
struct AudiobookPlayerView: View {
    @State var model: AudiobookPlayerModel
    let cover: Cover?
    let library: Library?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var isShowingChapters = false
    @State private var isShowingTracks = false

    var body: some View {
        NavigationStack {
            PocketPlayer(model: model, close: close) {
                if model.info?.isFolder == true { isShowingTracks = true } else { isShowingChapters = true }
            }
            .background { CanvasBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingChapters) {
                ChaptersView(model: model)
            }
            .sheet(isPresented: $isShowingTracks) {
                TracksView(model: model)
            }
        }
        // Past the largest accessibility sizes the transport would leave the screen.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    /// Leaves the tape running under the library, or ejects one that can't play, so no strip is
    /// left behind for it.
    private func close() {
        if case .failed = model.state {
            Task { await app.eject() }
        } else {
            dismiss()
        }
    }

    static func format(speed: Float) -> String {
        speed.formatted(.number.precision(.fractionLength(0 ... 2))) + "×"
    }

    static func format(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// What the player shows, worked out from the model.
extension AudiobookPlayerModel {
    /// Whole-book length in seconds, never zero so it can divide.
    var bookSeconds: Double { max(info?.duration.seconds ?? 1, 1) }

    /// The whole-book length, once it's known.
    var knownSeconds: Double? {
        guard let seconds = info?.duration.seconds, seconds > 0 else { return nil }
        return seconds
    }

    /// The Chapter or Track playing.
    var placeName: String? { chapter?.title ?? track.map(TracksView.title) }

    /// Folder audiobooks list Tracks; the rest list Chapters.
    var contentsName: String { info?.isFolder == true ? "Tracks" : "Chapters" }
    var contentsIcon: String { info?.isFolder == true ? "list.number" : "list.bullet" }
    var hasContents: Bool {
        info?.isFolder == true ? !(info?.tracks.isEmpty ?? true) : !(info?.chapters.isEmpty ?? true)
    }

    var sleepLabel: String {
        guard let timer = sleepTimer else { return "Off" }
        if let remaining = timer.remaining { return AudiobookPlayerView.format(remaining.seconds.rounded(.up)) }
        return "End of Chapter"
    }
}

/// The sleep timer's choices, for the player's menu.
struct SleepTimerChoices: View {
    let model: AudiobookPlayerModel

    var body: some View {
        if model.sleepTimer != nil {
            Button("Turn Off", systemImage: "moon.zzz") { model.setSleepTimer(nil) }
        }
        Button("End of Chapter") { model.setSleepTimer(.endOfChapter) }
        ForEach([5, 15, 30, 45, 60], id: \.self) { minutes in
            Button("\(minutes) minutes") { model.setSleepTimer(.after(.seconds(minutes * 60))) }
        }
    }
}

/// The player folded down to a strip under the library while its audiobook is loaded, paused
/// or playing. A tap opens the player again; the key plays and pauses without opening it.
struct NowPlayingBar: View {
    let player: AudiobookPlayerModel
    let open: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    private var detail: String? {
        player.placeName ?? player.author
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    // Too small to read, so the label is left blank.
                    CassetteArt()
                        .frame(width: 48, height: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.title)
                            .font(.system(.body, design: .serif, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        if let detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(palette.inkSecondary)
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the player")
            Group {
                if isOpening {
                    ProgressView()
                        .accessibilityLabel("Loading")
                } else {
                    Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
                        player.togglePlayback()
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(palette.ink)
                    .disabled(!isReady)
                }
            }
            .frame(width: 44, height: 44)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(minHeight: 64)
        .background(palette.raised, in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(palette.outline, lineWidth: 1) }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .contextMenu {
            Button("Eject", systemImage: "eject") { Task { await app.eject() } }
        }
        .accessibilityAction(named: "Eject") { Task { await app.eject() } }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        // Paper whatever the theme, so its text is ink.
        .environment(\.colorScheme, .light)
    }

    private var isReady: Bool {
        if case .ready = player.state { true } else { false }
    }

    private var isOpening: Bool {
        if case .opening = player.state { true } else { false }
    }
}

/// The system's AirPlay and Bluetooth route picker.
struct RoutePicker: UIViewRepresentable {
    var tint: UIColor
    /// The icon's colour while playing somewhere other than the device.
    var activeTint: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        updateUIView(picker, context: context)
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {
        picker.tintColor = tint
        picker.activeTintColor = activeTint
    }
}

/// The Chapters of the loaded Book file, the one playing marked.
private struct ChaptersView: View {
    let model: AudiobookPlayerModel

    var body: some View {
        ContentsList(title: "Chapters", rows: (model.info?.chapters ?? []).map { chapter in
            ContentsRow(id: "\(chapter.start)", title: chapter.title, detail: AudiobookPlayerView.format(chapter.start.seconds), isCurrent: chapter == model.chapter) {
                model.go(to: chapter)
            }
        })
    }
}

/// The Tracks of a folder audiobook, the one playing marked.
struct TracksView: View {
    let model: AudiobookPlayerModel

    static func title(_ track: AudiobookInfo.Track) -> String {
        track.title ?? "Track \(track.index + 1)"
    }

    var body: some View {
        ContentsList(title: "Tracks", rows: (model.info?.tracks ?? []).map { track in
            ContentsRow(id: "\(track.index)", title: Self.title(track), detail: AudiobookPlayerView.format(track.duration.seconds), isCurrent: track == model.track) {
                model.go(to: track)
            }
        })
    }
}

private struct ContentsRow: Identifiable {
    let id: String
    let title: String
    let detail: String
    let isCurrent: Bool
    let go: () -> Void
}

/// A list of Chapters or Tracks on the theme's paper.
private struct ContentsList: View {
    let title: String
    let rows: [ContentsRow]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            List(rows) { row in
                Button {
                    row.go()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(palette.paperAction)
                            .opacity(row.isCurrent ? 1 : 0)
                            .accessibilityHidden(true)
                        Text(row.title)
                            .font(.body.weight(row.isCurrent ? .semibold : .regular))
                        Spacer()
                        Text(row.detail)
                            .foregroundStyle(palette.inkSecondary)
                            .monospacedDigit()
                    }
                    .contentShape(.rect)
                }
                .foregroundStyle(palette.ink)
                .listRowBackground(row.isCurrent ? palette.accent.opacity(0.14) : palette.raised)
                .accessibilityAddTraits(row.isCurrent ? .isSelected : [])
            }
            .scrollContentBackground(.hidden)
            .background(palette.raised)
            .environment(\.colorScheme, .light)
            .tint(palette.paperAction)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
