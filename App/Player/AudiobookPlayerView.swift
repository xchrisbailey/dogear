import DogearCore
import SwiftUI

/// Full-screen player for one audiobook Book file.
struct AudiobookPlayerView: View {
    @State var model: AudiobookPlayerModel
    let cover: Cover?
    let library: Library?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isShowingChapters = false
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
                        Button("Chapters", systemImage: "list.bullet") { isShowingChapters = true }
                            .disabled(model.info?.chapters.isEmpty ?? true)
                    }
                }
                .sheet(isPresented: $isShowingChapters) {
                    ChaptersView(model: model)
                }
                .task { await model.open() }
                .onDisappear { Task { await model.close() } }
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
                Text(model.chapter?.title ?? " ")
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
            Button(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                model.togglePlayback()
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 56))
            .buttonStyle(.plain)
        }
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
