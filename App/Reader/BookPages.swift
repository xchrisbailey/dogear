import DogearCore
@preconcurrency import ReadiumNavigator
import SwiftUI
import UIKit

/// Readium's EPUB navigator, with its pages turned like paper.
///
/// Readium still lays out every page and owns the location. A turn takes a picture of the page
/// being left, moves Readium without its own animation, then swings the picture (forward) or the
/// new page itself (backward) about the spine. Positions, Contents jumps and sync never see it.
struct BookPages: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController
    let style: PageTurnStyle
    let toggleControls: () -> Void

    func makeUIViewController(context: Context) -> BookPagesController {
        BookPagesController(navigator: navigator)
    }

    func updateUIViewController(_ controller: BookPagesController, context: Context) {
        controller.style = style
        controller.toggleControls = toggleControls
    }
}

final class BookPagesController: UIViewController, UIGestureRecognizerDelegate {
    var style = PageTurnStyle.flip
    var toggleControls: () -> Void = {}

    private let navigator: EPUBNavigatorViewController
    /// The live page, hinged at the spine so it can swing in on a turn back.
    private let page = UIView()
    private var queue = PageTurnQueue()
    private var dragging: Dragging?

    /// A whole turn by tap or key. Only a quarter turn is ever seen: past upright, the page is
    /// off the spine side of the screen.
    private static let turnTime = 0.42
    private static let fadeTime = 0.22
    private static let upright = CGFloat.pi / 2
    /// Readium has moved once its call returns; the web view paints a frame or two later.
    private static let paintDelay = Duration.milliseconds(60)
    /// A finger still for this long has stopped, whatever speed it arrived at.
    private static let rest = 0.1

    init(navigator: EPUBNavigatorViewController) {
        self.navigator = navigator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var rightToLeft: Bool { navigator.presentation.readingProgression == .rtl }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        // Perspective for everything hinged inside.
        view.layer.sublayerTransform.m34 = -1 / 1700

        view.addSubview(page)
        addChild(navigator)
        navigator.view.frame = page.bounds
        navigator.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        page.addSubview(navigator.view)
        navigator.didMove(toParent: self)

        navigator.addObserver(.tap { [weak self] event in
            self?.tapped(at: event.location) ?? false
        })
        navigator.addObserver(.key { [weak self] event in
            self?.pressed(event) ?? false
        })

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Mid-turn the hinged views carry a transform; they're laid out again once it lands.
        guard queue.isIdle else { return }
        hinge(page)
    }

    /// Sizes `leaf` to the page and pins its spine edge, so a rotation swings it like a page.
    private func hinge(_ leaf: UIView) {
        leaf.layer.anchorPoint = CGPoint(x: rightToLeft ? 1 : 0, y: 0.5)
        leaf.bounds = view.bounds
        leaf.center = CGPoint(x: rightToLeft ? view.bounds.maxX : view.bounds.minX, y: view.bounds.midY)
    }

    /// `progress` 0 lies flat on the book, 1 stands upright on the spine, edge-on to the reader.
    private func swing(_ leaf: UIView, to progress: CGFloat) {
        let angle = Self.upright * progress * (rightToLeft ? 1 : -1)
        leaf.transform3D = progress == 0 ? CATransform3DIdentity : CATransform3DMakeRotation(angle, 0, 1, 0)
    }

    // MARK: Taps and keys

    private func tapped(at point: CGPoint) -> Bool {
        guard style != .none else {
            toggleControls()
            return true
        }
        switch PageTap(x: point.x, width: view.bounds.width, rightToLeft: rightToLeft) {
        case let .turn(turn): request(turn)
        case .controls: toggleControls()
        }
        return true
    }

    private func pressed(_ event: KeyEvent) -> Bool {
        guard event.phase == .down, event.modifiers.isEmpty else { return false }
        switch event.key {
        case .arrowDown, .space: request(.forward)
        case .arrowUp: request(.backward)
        case .arrowRight: request(rightToLeft ? .backward : .forward)
        case .arrowLeft: request(rightToLeft ? .forward : .backward)
        default: return false
        }
        return true
    }

    private func request(_ turn: PageTurn) {
        guard let first = queue.request(turn) else { return }
        Task {
            await perform(first)
            await drain()
        }
    }

    /// Runs the turn that waited while one was in the air, and any that waited behind it.
    private func drain() async {
        while let next = queue.finished() {
            await perform(next)
        }
        hinge(page)
    }

    private func perform(_ turn: PageTurn) async {
        switch style {
        case .none:
            await move(turn)
        case .fade:
            await fade(turn)
        case .flip:
            let flight = await lift(turn)
            await land(flight, complete: true, over: Self.turnTime, curve: .curveEaseInOut)
        }
    }

    @discardableResult
    private func move(_ turn: PageTurn) async -> Bool {
        let options = NavigatorGoOptions(animated: false)
        return switch turn {
        case .forward: await navigator.goForward(options: options)
        case .backward: await navigator.goBackward(options: options)
        }
    }

    // MARK: The turn

    /// A page off the book, part-way through a turn.
    private struct Flight {
        let turn: PageTurn
        /// False at the first and last page: there is nothing to turn to.
        let moved: Bool
        /// The picture of the page being left. Turning forward it is the leaf that swings;
        /// turning back it lies underneath while the live page swings in over it.
        let picture: UIView
        /// The shadow the swinging leaf casts on the page under it.
        let shadow: UIView
        /// Dims the swinging leaf as it turns from the light.
        let dimmer: UIView
    }

    /// Takes the picture, moves Readium underneath it, and leaves the leaf lying where it started.
    private func lift(_ turn: PageTurn) async -> Flight? {
        guard let snapshot = navigator.view.snapshotView(afterScreenUpdates: false) else {
            await move(turn)
            return nil
        }
        let shadow = UIView(frame: view.bounds)
        shadow.backgroundColor = .black
        // Turning back it lies over the picture while Readium moves, before `set` first runs.
        shadow.alpha = 0
        shadow.isUserInteractionEnabled = false
        let dimmer = UIView(frame: view.bounds)
        dimmer.backgroundColor = .black
        dimmer.alpha = 0
        dimmer.isUserInteractionEnabled = false

        let picture: UIView
        switch turn {
        case .forward:
            picture = UIView()
            hinge(picture)
            snapshot.frame = picture.bounds
            picture.addSubview(snapshot)
            picture.addSubview(dimmer)
            view.addSubview(shadow)
            view.addSubview(picture)
        case .backward:
            picture = snapshot
            picture.frame = view.bounds
            view.insertSubview(picture, belowSubview: page)
            view.insertSubview(shadow, belowSubview: page)
            page.addSubview(dimmer)
            swing(page, to: 1)
        }
        let flight = Flight(turn: turn, moved: await move(turn), picture: picture, shadow: shadow, dimmer: dimmer)
        set(flight, to: 0)
        try? await Task.sleep(for: Self.paintDelay)
        return flight
    }

    /// `progress` 0 is the page being left lying flat, 1 the page arrived at lying flat.
    private func set(_ flight: Flight, to progress: CGFloat) {
        switch flight.turn {
        case .forward:
            swing(flight.picture, to: progress)
            flight.dimmer.alpha = 0.3 * progress
            flight.shadow.alpha = 0.35 * (1 - progress)
        case .backward:
            swing(page, to: 1 - progress)
            flight.dimmer.alpha = 0.3 * (1 - progress)
            flight.shadow.alpha = 0.35 * progress
        }
    }

    /// Finishes the turn, or puts the page back and returns Readium to where it was.
    private func land(_ flight: Flight?, complete: Bool, over duration: TimeInterval, curve: UIView.AnimationOptions) async {
        guard let flight else { return }
        if !flight.moved {
            // First or last page: it lifts a little and settles back.
            // Turning back, the live page is the one lying there, so it starts flat.
            set(flight, to: edge(flight.turn, 0))
            await animate(0.14, .curveEaseOut) { self.set(flight, to: self.edge(flight.turn, 0.1)) }
            await animate(0.2, .curveEaseIn) { self.set(flight, to: self.edge(flight.turn, 0)) }
        } else {
            await animate(duration, curve) { self.set(flight, to: complete ? 1 : 0) }
            if !complete {
                await move(flight.turn == .forward ? .backward : .forward)
                try? await Task.sleep(for: Self.paintDelay)
            }
        }
        flight.picture.removeFromSuperview()
        flight.shadow.removeFromSuperview()
        flight.dimmer.removeFromSuperview()
        swing(page, to: 0)
    }

    private func fade(_ turn: PageTurn) async {
        guard let snapshot = navigator.view.snapshotView(afterScreenUpdates: false) else {
            await move(turn)
            return
        }
        snapshot.frame = view.bounds
        view.addSubview(snapshot)
        if await move(turn) {
            try? await Task.sleep(for: Self.paintDelay)
            await animate(Self.fadeTime, .curveEaseInOut) { snapshot.alpha = 0 }
        }
        snapshot.removeFromSuperview()
    }

    private func animate(_ duration: TimeInterval, _ curve: UIView.AnimationOptions, _ changes: @escaping () -> Void) async {
        await withCheckedContinuation { continuation in
            UIView.animate(withDuration: duration, delay: 0, options: [curve, .allowUserInteraction], animations: changes) { _ in
                continuation.resume()
            }
        }
    }

    // MARK: Dragging

    /// A page held by a finger. The picture is taken while the finger is already moving, so the
    /// leaf catches up with it once `lifting` is done.
    private final class Dragging {
        let drag: PageDrag
        var translation: CGFloat
        /// When the finger last moved. The recognizer still reports the speed of that movement
        /// after the finger has come to rest.
        var movedAt = CACurrentMediaTime()
        var flight: Flight?
        var lifting: Task<Void, Never>?

        init(drag: PageDrag, translation: CGFloat) {
            self.drag = drag
            self.translation = translation
        }
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: view).x
        switch pan.state {
        case .began, .changed:
            if let dragging {
                dragging.translation = translation
                dragging.movedAt = CACurrentMediaTime()
                follow(dragging)
            } else {
                begin(translation)
            }
        case .ended:
            // A page held still and let go isn't flicked.
            let rested = dragging.map { CACurrentMediaTime() - $0.movedAt > Self.rest } ?? false
            release(translation: translation, velocity: rested ? 0 : pan.velocity(in: view).x, cancelled: false)
        case .cancelled, .failed:
            release(translation: translation, velocity: 0, cancelled: true)
        default:
            break
        }
    }

    private func begin(_ translation: CGFloat) {
        guard let drag = PageDrag(translation: translation, width: view.bounds.width, rightToLeft: rightToLeft),
              queue.request(drag.turn) != nil
        else { return }
        let dragging = Dragging(drag: drag, translation: translation)
        self.dragging = dragging
        guard style == .flip else { return }
        dragging.lifting = Task {
            dragging.flight = await lift(drag.turn)
            follow(dragging)
        }
    }

    private func follow(_ dragging: Dragging) {
        guard let flight = dragging.flight else { return }
        let progress = dragging.drag.progress(translation: dragging.translation)
        // With nowhere to turn to, the page gives a little and no more.
        set(flight, to: flight.moved ? progress : edge(flight.turn, progress * 0.12))
    }

    /// Where a page that can't turn sits when lifted by `lift`.
    private func edge(_ turn: PageTurn, _ lift: CGFloat) -> CGFloat {
        turn == .forward ? lift : 1 - lift
    }

    private func release(translation: CGFloat, velocity: CGFloat, cancelled: Bool) {
        guard let dragging else { return }
        self.dragging = nil
        let drag = dragging.drag
        let complete = !cancelled && drag.completes(translation: translation, velocity: velocity)
        Task {
            await dragging.lifting?.value
            if style == .flip {
                let progress = drag.progress(translation: translation)
                let left = complete ? 1 - progress : progress
                await land(dragging.flight, complete: complete, over: max(0.12, Self.turnTime * left), curve: .curveEaseOut)
            } else if complete {
                await fade(drag.turn)
            }
            await drain()
        }
    }

    // MARK: UIGestureRecognizerDelegate

    /// Only a sideways drag on a paged Book with nothing in the air lifts a page. Anything else
    /// fails at once and Readium's own gestures carry on.
    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        // A drag across selected text is moving the selection's handles.
        guard style != .none, queue.isIdle, navigator.currentSelection == nil, let pan = recognizer as? UIPanGestureRecognizer else { return false }
        let velocity = pan.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y)
    }

    /// Readium's scroll views would slide the page under the finger; they wait for this to fail.
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other is UIPanGestureRecognizer && other.view is UIScrollView
    }
}
