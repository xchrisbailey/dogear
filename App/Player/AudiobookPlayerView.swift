import AVKit
import DogearCore
import SwiftUI

/// Full-screen player for one audiobook Book file.
struct AudiobookPlayerView: View {
    @State var model: AudiobookPlayerModel
    let cover: Cover?
    let library: Library?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingChapters = false
    @State private var isShowingTracks = false
    @State private var scrubbing: Double?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(model.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if model.info?.isFolder == true {
                            Button("Tracks", systemImage: "list.number") { isShowingTracks = true }
                                .disabled(model.info?.tracks.isEmpty ?? true)
                        } else {
                            Button("Chapters", systemImage: "list.bullet") { isShowingChapters = true }
                                .disabled(model.info?.chapters.isEmpty ?? true)
                        }
                    }
                }
                .sheet(isPresented: $isShowingChapters) {
                    ChaptersView(model: model)
                }
                .sheet(isPresented: $isShowingTracks) {
                    TracksView(model: model)
                }
                .task { await model.open() }
                .onDisappear { Task { await model.close() } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.catchUp() } }
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .opening:
            ProgressView("Opening…")
        case let .failed(message):
            ContentUnavailableView("Can't play this audiobook", systemImage: "exclamationmark.triangle", description: Text(message))
        case .ready:
            Group {
                if sizeClass == .regular {
                    // Cover beside the controls, using the iPad's width.
                    HStack(spacing: 48) {
                        artwork.frame(maxWidth: 420)
                        controls.frame(maxWidth: 420)
                    }
                    .padding(48)
                } else {
                    VStack(spacing: 32) {
                        artwork.frame(maxWidth: 320)
                        controls
                    }
                    .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var artwork: some View {
        CoverArt(cover: cover, library: library)
            .aspectRatio(1, contentMode: .fit)
            .shadow(radius: 12, y: 6)
    }

    private var controls: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text(model.chapter?.title ?? model.track.map(TracksView.title) ?? " ")
                    .font(.headline)
                    .lineLimit(1)
                Text(model.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.orange.opacity(0.2), in: .rect(cornerRadius: 8))
            }
            scrubber
            transport
            HStack {
                speedMenu
                Spacer()
                RoutePicker()
                    .frame(width: 44, height: 44)
                Spacer()
                sleepMenu
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 40) {
            Button("Back \(Int(AudiobookPlayerModel.skipBack.seconds)) seconds", systemImage: "gobackward.15") {
                model.skip(by: .zero - AudiobookPlayerModel.skipBack)
            }
            .font(.system(size: 32))
            Button(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                model.togglePlayback()
            }
            .font(.system(size: 56))
            Button("Forward \(Int(AudiobookPlayerModel.skipForward.seconds)) seconds", systemImage: "goforward.30") {
                model.skip(by: AudiobookPlayerModel.skipForward)
            }
            .font(.system(size: 32))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
    }

    private var speedMenu: some View {
        Menu {
            Picker("Speed", selection: Binding { model.speed } set: { model.setSpeed($0) }) {
                ForEach(AudiobookPlayerModel.speeds, id: \.self) { speed in
                    Text(Self.format(speed: speed)).tag(speed)
                }
            }
        } label: {
            Text(Self.format(speed: model.speed))
                .monospacedDigit()
                .frame(minWidth: 64, alignment: .leading)
        }
        .accessibilityLabel("Speed \(Self.format(speed: model.speed))")
    }

    private var sleepMenu: some View {
        Menu {
            if model.sleepTimer != nil {
                Button("Turn Off", systemImage: "moon.zzz") { model.setSleepTimer(nil) }
            }
            Button("End of Chapter") { model.setSleepTimer(.endOfChapter) }
            ForEach([5, 15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) minutes") { model.setSleepTimer(.after(.seconds(minutes * 60))) }
            }
        } label: {
            Label(sleepLabel, systemImage: model.sleepTimer == nil ? "moon" : "moon.fill")
                .monospacedDigit()
                .frame(minWidth: 64, alignment: .trailing)
        }
        .accessibilityLabel(model.sleepTimer == nil ? "Sleep timer" : "Sleep timer, \(sleepLabel)")
    }

    private var sleepLabel: String {
        guard let timer = model.sleepTimer else { return "Sleep" }
        if let remaining = timer.remaining { return Self.format(remaining.seconds.rounded(.up)) }
        return "Chapter end"
    }

    static func format(speed: Float) -> String {
        speed.formatted(.number.precision(.fractionLength(0 ... 2))) + "×"
    }

    /// Whole-book time; Chapters are in the list.
    private var scrubber: some View {
        let duration = model.info?.duration.seconds ?? 1
        let elapsed = scrubbing ?? model.currentTime.seconds
        return VStack(spacing: 4) {
            Slider(
                value: Binding { elapsed } set: { scrubbing = $0 },
                in: 0 ... max(duration, 1)
            ) { editing in
                if !editing, let scrubbing {
                    model.seek(to: .seconds(scrubbing))
                    self.scrubbing = nil
                }
            }
            HStack {
                Text(Self.format(elapsed))
                Spacer()
                Text("-" + Self.format(max(0, duration - elapsed)))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    static func format(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// The system's AirPlay and Bluetooth route picker.
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

private struct ChaptersView: View {
    let model: AudiobookPlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.info?.chapters ?? []) { chapter in
                Button {
                    model.go(to: chapter)
                    dismiss()
                } label: {
                    HStack {
                        Text(chapter.title)
                        Spacer()
                        if chapter == model.chapter {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.tint)
                                .accessibilityLabel("Playing")
                        }
                        Text(AudiobookPlayerView.format(chapter.start.seconds))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct TracksView: View {
    let model: AudiobookPlayerModel
    @Environment(\.dismiss) private var dismiss

    static func title(_ track: AudiobookInfo.Track) -> String {
        track.title ?? "Track \(track.index + 1)"
    }

    var body: some View {
        NavigationStack {
            List(model.info?.tracks ?? []) { track in
                Button {
                    model.go(to: track)
                    dismiss()
                } label: {
                    HStack {
                        Text(Self.title(track))
                        Spacer()
                        if track == model.track {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.tint)
                                .accessibilityLabel("Playing")
                        }
                        Text(AudiobookPlayerView.format(track.duration.seconds))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct CoverArt: View {
    let cover: Cover?
    let library: Library?

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.fill.tertiary)
                    .overlay { Image(systemName: "headphones").font(.largeTitle).foregroundStyle(.secondary) }
            }
        }
        .task(id: cover) {
            guard let cover, let data = await library?.image(for: cover) else { return }
            image = UIImage(data: data)
        }
    }
}
