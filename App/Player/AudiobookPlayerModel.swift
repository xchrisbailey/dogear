import AVFoundation
import DogearCore
import MediaPlayer
import os
import UIKit

/// Streams a Server audiobook, or plays its Download, keeps the listener's Position on the device and shares it with
/// Grimmory's web player.
///
/// A single-file audiobook is one player item at Track 0; a folder audiobook queues one item per
/// Track from the playing one onwards, so the next Track is preloaded and starts without a gap.
/// `currentTime` is always whole-book time; the Position maps it to a Track and the milliseconds
/// into it. Items carry the access token in their URL, so whenever it changes they're rebuilt and
/// playback seeks back to the same second.
@Observable
final class AudiobookPlayerModel {
    enum State {
        case opening
        case ready
        case failed(String)
    }

    private(set) var state: State = .opening
    private(set) var info: AudiobookInfo?
    private(set) var currentTime: Duration = .zero
    private(set) var isPlaying = false
    /// The stream stopped and couldn't be recovered; shown instead of silently stopping.
    private(set) var problem: String?
    /// Kept on the player, not the item, so it survives the rebuild when the token changes.
    private(set) var speed: Float
    private(set) var sleepTimer: SleepTimer?

    let title: String
    private let author: String?
    private let audiobook: any AudiobookSource
    private let positions: Positions?
    private let sharedPositions: SharedPositions?
    private let cover: () async -> Data?

    private let player = AVQueuePlayer()
    private var stream: AudiobookStream?
    private var streams: Task<Void, Never>?
    /// Reauthorizing once per failure: a failure that survives a fresh token isn't about the token.
    private var hasReauthorized = false
    private var itemStatus: [NSKeyValueObservation] = []
    /// Where each queued item starts in the whole Book file.
    private var itemStarts: [ObjectIdentifier: Duration] = [:]
    private var timeControl: NSKeyValueObservation?
    private var timeObservers: [Any] = []
    private var failureObserver: (any NSObjectProtocol)?
    private var sessionObservers: [any NSObjectProtocol] = []
    /// Set when an interruption (a call, Siri) stopped playback, so its end can resume it.
    private var interruptedWhilePlaying = false
    private var lastTick: ContinuousClock.Instant?
    private var recording: Task<Void, Never>?
    private var artwork: MPMediaItemArtwork?
    /// While an item is rebuilt or a seek lands, the player reports times and pauses that aren't
    /// the listener's, which must not be saved as their Position.
    private var repositioning = 0

    private static let saveInterval = CMTime(seconds: 5, preferredTimescale: 1)
    static let speeds: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    static let skipBack: Duration = .seconds(15)
    static let skipForward: Duration = .seconds(30)
    private static let speedKey = "playbackSpeed"
    private static let log = Logger(subsystem: "com.xchrisbailey.Dogear", category: "Player")

    init(
        audiobook: any AudiobookSource, title: String, author: String?,
        positions: Positions?, sharedPositions: SharedPositions?, cover: @escaping () async -> Data?
    ) {
        self.audiobook = audiobook
        self.title = title
        self.author = author
        self.positions = positions
        self.sharedPositions = sharedPositions
        self.cover = cover
        let saved = UserDefaults.standard.float(forKey: Self.speedKey)
        speed = Self.speeds.contains(saved) ? saved : 1
        player.defaultRate = speed
    }

    var chapter: AudiobookInfo.Chapter? {
        info?.chapter(at: currentTime)
    }

    /// The Track playing, for folder audiobooks.
    var track: AudiobookInfo.Track? {
        info?.track(at: currentTime)
    }

    var bookFileID: Int? { info?.bookFileID }

    func open() async {
        guard case .opening = state else { return }
        let info: AudiobookInfo
        do {
            info = try await audiobook.info()
        } catch let error where error == .forbidden || error == .notFound {
            state = .failed(error.errorDescription ?? "Couldn't load this audiobook.")
            return
        } catch {
            state = .failed("Couldn't load this audiobook. Check your connection and try again.")
            return
        }
        self.info = info
        currentTime = await resumeTime(bookFileID: info.bookFileID)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        } catch {
            Self.log.error("Audio session category failed: \(error.localizedDescription)")
        }
        observePlayer()
        observeSession()
        configureRemoteCommands()
        state = .ready
        record(share: false)
        streams = Task { [audiobook] in
            for await stream in await audiobook.streamUpdates() {
                self.rebuild(with: stream)
            }
        }
        if let data = await cover(), let image = UIImage(data: data) {
            artwork = Self.artwork(image)
            updateNowPlaying()
        }
    }

    /// Where to start: the newer of this device's Position and the Shared position (ADR 0002).
    /// Offline, only the device's.
    private func resumeTime(bookFileID: Int) async -> Duration {
        let local = await positions?.latest(bookFileID: bookFileID)
        let shared = try? await sharedPositions?.latest(.audiobook, bookID: audiobook.bookID, bookFileID: bookFileID)
        let newest = [local, shared].compactMap(\.self).max { $0.recordedAt < $1.recordedAt }
        guard case let .audiobook(location)? = newest?.location else { return .zero }
        return info?.time(of: location) ?? .zero
    }

    // MARK: Playback

    func play() {
        try? AVAudioSession.sharedInstance().setActive(true)
        problem = nil
        // After a failure, the listener's retry gets its own fresh-token attempt.
        if player.currentItem == nil, let stream {
            hasReauthorized = false
            rebuild(with: stream)
        }
        player.play()
    }

    func pause() {
        player.pause()
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func seek(to time: Duration) {
        let time = max(.zero, min(time, info?.duration ?? time))
        let trackChanged = info?.track(at: time) != track
        currentTime = time
        if let info { sleepTimer?.moved(to: time, in: info) }
        // The queue only holds the playing Track onwards, so another Track needs a new queue.
        if trackChanged, let stream {
            requeue(with: stream)
        } else {
            reposition()
        }
        updateNowPlaying()
        record(share: true)
    }

    func go(to chapter: AudiobookInfo.Chapter) {
        seek(to: chapter.start)
    }

    func go(to track: AudiobookInfo.Track) {
        seek(to: track.start)
    }

    /// Back when `interval` is negative. Whole-book time, so it crosses Chapters and Tracks alike.
    func skip(by interval: Duration) {
        guard let info else { return }
        seek(to: info.skip(from: currentTime, by: interval))
    }

    func setSpeed(_ speed: Float) {
        self.speed = speed
        UserDefaults.standard.set(speed, forKey: Self.speedKey)
        // `defaultRate` is what `play()` uses, including after an item rebuild.
        player.defaultRate = speed
        if isPlaying { player.rate = speed }
        updateNowPlaying()
    }

    func setSleepTimer(_ mode: SleepTimer.Mode?) {
        guard let info, let mode else {
            sleepTimer = nil
            return
        }
        sleepTimer = SleepTimer(mode, at: currentTime, in: info)
    }

    /// A new token (or a retry after a failure): a fresh item at the same second, playing if it was.
    private func rebuild(with stream: AudiobookStream) {
        guard stream != self.stream || player.currentItem == nil else { return }
        requeue(with: stream)
    }

    /// Fresh items from the Track at `currentTime` onwards, seeked to it, playing if it was.
    private func requeue(with stream: AudiobookStream) {
        guard let info else { return }
        let resume = isPlaying || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        Self.log.info("Building player items at \(self.currentTime.seconds, format: .fixed(precision: 1)) s")
        self.stream = stream
        let queue: [(url: URL, start: Duration)] = if let playing = info.track(at: currentTime) {
            info.tracks.filter { $0.index >= playing.index }.map { (stream.track($0.index), $0.start) }
        } else {
            [(stream.wholeBook, .zero)]
        }
        repositioning += 1
        player.removeAllItems()
        itemStatus = []
        itemStarts = [:]
        for (url, start) in queue {
            let item = AVPlayerItem(url: url)
            item.audioTimePitchAlgorithm = .timeDomain
            itemStarts[ObjectIdentifier(item)] = start
            watch(item)
            player.insert(item, after: nil)
        }
        repositioning -= 1
        reposition()
        if resume { player.play() }
    }

    /// Where the playing item starts in the whole Book file.
    private var itemStart: Duration {
        player.currentItem.flatMap { itemStarts[ObjectIdentifier($0)] } ?? .zero
    }

    /// Seeks to `currentTime` exactly, ignoring the player's reports until it lands.
    private func reposition() {
        repositioning += 1
        player.seek(to: CMTime(currentTime - itemStart), toleranceBefore: .zero, toleranceAfter: .zero) { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.repositioning -= 1
                if self.repositioning == 0 { self.playingChanged(self.player.timeControlStatus != .paused) }
            }
        }
    }

    /// An invalid token fails the item without any error log or notification from the player
    /// itself, so the item's status is watched directly.
    private func watch(_ item: AVPlayerItem) {
        itemStatus.append(item.observe(\.status) { @Sendable [weak self] item, _ in
            let status = item.status
            let reason = item.error?.localizedDescription
            Task { @MainActor in self?.itemStatusChanged(status, reason: reason) }
        })
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status, reason: String?) {
        switch status {
        case .readyToPlay:
            Self.log.info("Player item ready")
            hasReauthorized = false
            problem = nil
        case .failed:
            Self.log.error("Player item failed: \(reason ?? "no error")")
            Task { await recover() }
        default:
            break
        }
    }

    /// A refused token looks like any other failure from the player, so a fresh token is tried
    /// once before the listener is told.
    private func recover() async {
        guard let stream else { return }
        guard !hasReauthorized else {
            fail()
            return
        }
        hasReauthorized = true
        do {
            let fresh = try await audiobook.reauthorize(afterRejecting: stream)
            self.stream = nil
            rebuild(with: fresh)
        } catch {
            fail()
        }
    }

    private func fail() {
        player.pause()
        player.removeAllItems()
        isPlaying = false
        problem = "Playback stopped: couldn't stream this audiobook. Check your connection and try again."
        record(share: true)
        updateNowPlaying()
    }

    private func observePlayer() {
        timeControl = player.observe(\.timeControlStatus) { @Sendable [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in self?.playingChanged(playing) }
        }
        timeObservers.append(player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { @Sendable [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        })
        // Saved every few seconds while playing, as Grimmory's web player does.
        timeObservers.append(player.addPeriodicTimeObserver(forInterval: Self.saveInterval, queue: .main) { @Sendable [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, self.repositioning == 0 else { return }
                self.record(share: true)
            }
        })
        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main
        ) { @Sendable [weak self] _ in
            MainActor.assumeIsolated { Task { await self?.recover() } }
        }
    }

    private func tick(_ time: CMTime) {
        guard repositioning == 0, player.currentItem != nil, time.isNumeric else { return }
        let previous = (chapter, track)
        currentTime = itemStart + .seconds(time.seconds)
        if (chapter, track) != previous { updateNowPlaying() }
        runSleepTimer()
    }

    /// Counts wall-clock listening, so a pause doesn't use up the timer and 2× doesn't halve it.
    private func runSleepTimer() {
        let now = ContinuousClock.now
        defer { lastTick = isPlaying ? now : nil }
        guard isPlaying, let lastTick, sleepTimer != nil else { return }
        if sleepTimer?.played(lastTick.duration(to: now), to: currentTime) == true {
            Self.log.info("Sleep timer stopped playback")
            sleepTimer = nil
            pause()
        }
    }

    private func playingChanged(_ playing: Bool) {
        guard repositioning == 0, playing != isPlaying else { return }
        isPlaying = playing
        lastTick = playing ? .now : nil
        updateNowPlaying()
        if !playing { record(share: true) }
    }

    // MARK: Interruptions and headphones

    private func observeSession() {
        let center = NotificationCenter.default
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { @Sendable [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated { self?.interrupted(type, options: options) }
        })
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { @Sendable [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            // Headphones unplugged or disconnected: never carry on out loud.
            guard reason == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { self?.pause() }
        })
    }

    private func interrupted(_ type: AVAudioSession.InterruptionType?, options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            // The system has already paused the player; `isPlaying` still says whether it was playing.
            interruptedWhilePlaying = isPlaying
            pause()
        case .ended:
            // The system says whether resuming suits the interruption (yes after a call, no after
            // another app took over playback).
            if interruptedWhilePlaying, options.contains(.shouldResume) { play() }
            interruptedWhilePlaying = false
        default:
            break
        }
    }

    // MARK: Positions

    private func record(share: Bool) {
        guard let info else { return }
        let location = Position.Location.audiobook(info.location(at: currentTime))
        // Chained so a slow save can't land after a newer one and win.
        recording = Task { [previous = recording, positions, sharedPositions, bookID = audiobook.bookID, bookFileID = info.bookFileID] in
            await previous?.value
            guard let positions else {
                // Without the on-device store there's no Outbox; sharing directly is the best left.
                if share {
                    let position = Position(bookFileID: bookFileID, location: location, recordedAt: Date())
                    try? await sharedPositions?.push(position, bookID: bookID)
                }
                return
            }
            if share {
                _ = try? await positions.record(location, bookFileID: bookFileID, bookID: bookID)
                // Failures stay in the Outbox. A refresh here also hands the player a new token.
                if let sharedPositions { try? await positions.flushOutbox(to: sharedPositions) }
            } else {
                _ = try? await positions.recordLanding(location, bookFileID: bookFileID)
            }
        }
    }

    /// Stops playback and pushes where the listener stopped.
    func close() async {
        if isPlaying || player.currentItem != nil {
            player.pause()
            isPlaying = false
            record(share: true)
        }
        streams?.cancel()
        for observer in timeObservers { player.removeTimeObserver(observer) }
        timeObservers = []
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
        for observer in sessionObservers { NotificationCenter.default.removeObserver(observer) }
        sessionObservers = []
        sleepTimer = nil
        player.removeAllItems()
        itemStatus = []
        itemStarts = [:]
        timeControl = nil
        clearRemoteCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        await recording?.value
    }

    // MARK: Lock screen and Control Center

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayback()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: .seconds(event.positionTime))
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipBack.seconds)]
        center.skipBackwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? Self.skipBack.seconds
            self?.skip(by: .seconds(-interval))
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipForward.seconds)]
        center.skipForwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? Self.skipForward.seconds
            self?.skip(by: .seconds(interval))
            return .success
        }
        center.changePlaybackRateCommand.supportedPlaybackRates = Self.speeds.map { NSNumber(value: $0) }
        center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            self.setSpeed(event.playbackRate)
            return .success
        }
        for command in Self.remoteCommands(center) {
            command.isEnabled = true
        }
        // The lock screen shows skip buttons only while track buttons are off.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    private func clearRemoteCommands() {
        for command in Self.remoteCommands(.shared()) {
            command.removeTarget(nil)
        }
    }

    private static func remoteCommands(_ center: MPRemoteCommandCenter) -> [MPRemoteCommand] {
        [
            center.playCommand, center.pauseCommand, center.togglePlayPauseCommand, center.changePlaybackPositionCommand,
            center.skipBackwardCommand, center.skipForwardCommand, center.changePlaybackRateCommand,
        ]
    }

    /// Elapsed time and rate only on changes; the system extrapolates in between.
    private func updateNowPlaying() {
        guard let info else { return }
        var nowPlaying: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: info.duration.seconds,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime.seconds,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(speed) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(speed),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let author { nowPlaying[MPMediaItemPropertyArtist] = author }
        if let chapter {
            nowPlaying[MPMediaItemPropertyAlbumTitle] = chapter.title
            nowPlaying[MPNowPlayingInfoPropertyChapterNumber] = chapter.index
            nowPlaying[MPNowPlayingInfoPropertyChapterCount] = info.chapters.count
        } else if let track {
            nowPlaying[MPMediaItemPropertyAlbumTitle] = track.title ?? "Track \(track.index + 1)"
        }
        if let artwork { nowPlaying[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
    }

    // The system asks for artwork off the main thread, so the closure mustn't be main-actor isolated.
    private nonisolated static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

private extension CMTime {
    init(_ duration: Duration) {
        self = CMTime(seconds: duration.seconds, preferredTimescale: 1000)
    }
}
