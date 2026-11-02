//  🖥️ TUI — A Terminal UI framework for Swift
//  _ImageCore+Animation.swift
//
//  A file of several frames plays by itself: its frames decoded once in the
//  background, the one showing chosen by the frame clock, and a wake asked for
//  the next, re-declared only while the view is drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIImage

// MARK: - Playback

/// What one view's playing picture holds: its frames, when they started, and
/// what it has made of them. A class changed in place, as ``ImagePixelPin`` is,
/// so a frame's bookkeeping asks for no further frame.
///
/// **What it can hold.** The frames, at most ``AnimatedImageDecoder/byteBudget``
/// (``FramePlan``). Their glyph conversions, at most ``artByteBudget``. In the
/// terminal, which keeps each frame it was sent, at most ``terminalByteBudget``
/// of pixels and here ``placedFrameBudget`` of what the store remembers of them;
/// a frame past those is sent again each time it comes round, as one picture
/// replacing the last. All of it goes when the view disappears
/// (``stop(token:lifecycle:store:)``).
final class ImageAnimationPlayback {
    /// The most bytes of glyph conversions kept across the frames. Past it a
    /// frame is converted each time it shows.
    static let artByteBudget = 16 << 20

    /// The most bytes of pixels left in the terminal: a fifth of kitty's default
    /// quota for one image store, for one picture.
    static let terminalByteBudget = 64 << 20

    /// The most bytes the image store keeps here for the frames in the terminal.
    static let placedFrameBudget = 16 << 20

    /// What the store keeps of a picture per cell: its small copy
    /// (`DerivedImages`, 32 bytes) and a placeholder cell's spelling.
    private static let placedBytesPerCell = 48

    fileprivate enum Progress {
        /// Not looked at since it appeared.
        case unasked
        /// Worth decoding, once it is known to be shown.
        case candidate
        case decoding
        /// One picture, or none a decoder here can play.
        case still
        case ready(AnimatedImage)
    }

    fileprivate var progress = Progress.unasked
    /// What ``progress`` is of.
    fileprivate var source: ImageSource?
    fileprivate var startedAt: Int64?
    /// When it stopped for not being shown, which comes off the time it has
    /// played.
    fileprivate var pausedAt: Int64?
    /// Whether the scroll view it is in shows any of it, `nil` until it says.
    /// Off the end of a stack's window a view is not drawn at all; this is the
    /// rest, an eager stack's views, drawn whole and cut to the viewport.
    fileprivate var isShown: Bool?
    /// Each frame's conversion, under ``artByteBudget``.
    private var art: [Int: ImageRenderCache] = [:]
    private var artBytes = 0
    /// How many frames have a store token of their own.
    private var placedFrames = 0

    /// The token the frames decode under, beside the view's own.
    static func decodeToken(_ token: String) -> String { token + "-frames" }

    private static func frameToken(_ token: String, _ index: Int) -> String { "\(token)-frame-\(index)" }

    /// Lets go of everything, for a picture that will start again from its first
    /// frame if it comes back: the view's disappear handler, or a new source.
    func stop(token: String, lifecycle: LifecycleManager, store: TerminalImageStore?) {
        lifecycle.cancelTask(token: Self.decodeToken(token))
        for index in 0..<placedFrames { store?.release(token: Self.frameToken(token, index)) }
        placedFrames = 0
        progress = .unasked
        startedAt = nil
        pausedAt = nil
        isShown = nil
        art = [:]
        artBytes = 0
    }

    /// The token frame `index` of `frameCount` goes to the store under, sent at
    /// `pixelBytes` in a box of `cells`: its own, which keeps it in the terminal
    /// for the next time round, where the budgets allow, and otherwise the
    /// view's, whose picture the next frame replaces. The first frames are the
    /// ones kept: evicting in turn would keep none of a loop too long to fit.
    func storeToken(
        _ token: String, frame index: Int, of frameCount: Int, pixelBytes: Int, cells: Int, store: TerminalImageStore
    ) -> String {
        let placed = min(
            frameCount, Self.terminalByteBudget / max(1, pixelBytes),
            Self.placedFrameBudget / max(1, cells * Self.placedBytesPerCell))
        if placed < placedFrames {
            for index in placed..<placedFrames { store.release(token: Self.frameToken(token, index)) }
        }
        placedFrames = placed
        return index < placed ? Self.frameToken(token, index) : token
    }

    /// The conversion kept of frame `index`.
    func conversion(ofFrame index: Int) -> ImageRenderCache? { art[index] }

    /// Keeps `conversion` of frame `index`, within the budget.
    func keep(_ conversion: ImageRenderCache, ofFrame index: Int) {
        let bytes = conversion.art.lines.reduce(0) { $0 + $1.utf8.count }
        let replaced = art[index].map { $0.art.lines.reduce(0) { $0 + $1.utf8.count } } ?? 0
        guard artBytes - replaced + bytes <= Self.artByteBudget else { return }
        art[index] = conversion
        artBytes += bytes - replaced
    }
}

/// The frame of a playing picture this render draws.
struct PlayingFrame {
    let image: RGBAImage
    let decode: ImageDecodeID
    let index: Int
    let frameCount: Int
    /// The file's size: what the picture is laid out as, the same before its
    /// frames arrive and however far they were scaled down.
    let canvas: (width: Int, height: Int)
    let playback: ImageAnimationPlayback
}

// MARK: - Choosing the frame

extension _ImageCore {
    /// The box holding this view's ``ImageAnimationPlayback``.
    func animationPlayback(context: RenderContext) -> StateBox<ImageAnimationPlayback> {
        context.stateStorage!.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: Self.animationStateIndex),
            default: ImageAnimationPlayback())
    }

    /// The frame to draw instead of the still picture that was loaded, or `nil`
    /// to draw that: a file that holds no animation a decoder here can play, or
    /// frames still decoding, or nothing to animate for.
    ///
    /// Reduce Motion shows the still, the file's first frame, as a playing
    /// picture is motion nobody asked for. So does a drawing with no scheduler (a
    /// one-off snapshot, which could never wake to draw the next), and a measure,
    /// which has no business starting anything and is the same size either way.
    ///
    /// Each frame that draws one asks for a render when the next is due, rounded
    /// up to a tick of 1/60 s, so it coincides with everything else animating. A
    /// view not drawn asks for nothing, so it stops by itself: off the window of
    /// a scroll view, under a `.hidden()`, or gone. So does one a scroll view
    /// draws but does not show, and one past its last play. A page with none on
    /// it has nothing to wake for.
    func playingFrame(token: String, context: RenderContext) -> PlayingFrame? {
        guard !context.isMeasuring, decoded == nil, resizing?.slices != true, case .file(let path) = source,
            !context.environment.accessibilityReduceMotion, context.environment.animationScheduler != nil,
            context.canWatchScrollVisibility, let lifecycle = context.environment.lifecycle
        else { return nil }
        let box = animationPlayback(context: context)
        let playback = box.value
        let store = context.environment.terminalImageStore
        playback.begin(source, token: token, lifecycle: lifecycle, store: store) {
            AnimatedImageDecoder.mayAnimate(atPath: path)
        }
        if playback.startsDecoding {
            let maxPixelCount = context.environment.imageMaxPixelCount
            lifecycle.startTask(token: ImageAnimationPlayback.decodeToken(token), priority: .userInitiated) {
                let animation = await Self.decodedAnimation(path: path, maxPixelCount: maxPixelCount)
                await MainActor.run {
                    // As a load's result: a source changed since, or a view
                    // gone, must not have this land on it.
                    guard !Task.isCancelled else { return }
                    playback.finishDecoding(animation)
                    // A write, to ask for the frame that first draws them.
                    box.value = playback
                }
            }
        }
        guard let animation = playback.animation else { return nil }
        let now = context.environment.frameNowNanos
        let elapsed = playback.elapsed(at: now) {
            // The still has given way to the frames, in the terminal too.
            store?.release(token: token)
        }
        let position = animation.position(atElapsed: elapsed)
        if playback.isPlaying, let next = position.nextChange {
            context.requestWake(
                token: "picture-frame-" + token,
                atNanos: AnimationClock.nanoseconds(ofNextTickMultiple: 1, after: now &+ (next &- elapsed) &- 1))
        }
        let frame = animation.frames[position.index]
        return PlayingFrame(
            image: frame.image, decode: frame.decode, index: position.index, frameCount: animation.frames.count,
            canvas: (animation.width, animation.height), playback: playback)
    }

    /// `picture` as this view's drawing, watched for whether a scroll view shows
    /// any of it, where it holds frames to play or to decode. A report that
    /// changes anything asks for a frame: to start, or to carry on.
    func watchingVisibility(of picture: FrameBuffer, context: RenderContext) -> FrameBuffer {
        guard context.canWatchScrollVisibility, decoded == nil, case .file = source else { return picture }
        let box = animationPlayback(context: context)
        let playback = box.value
        guard playback.watchesVisibility else { return picture }
        return context.watchingScrollVisibility(
            // Any of it at all, for which the threshold has only to be above 0:
            // at 0 every view counts as shown.
            threshold: .leastNonzeroMagnitude,
            action: { isShown in
                guard playback.isShown != isShown else { return }
                playback.isShown = isShown
                box.value = playback
            },
            draw: { picture })
    }

    /// Reads and decodes the frames off the main actor, as a load's pixels are.
    @concurrent
    private static func decodedAnimation(path: String, maxPixelCount: Int?) async -> AnimatedImage? {
        AnimatedImageDecoder.decode(atPath: path, maxPixelCount: maxPixelCount)
    }
}

extension ImageAnimationPlayback {
    /// Starts on `source`, if it is not what this is of, and looks at the file
    /// (`mayAnimate`) if nobody has since it appeared.
    func begin(
        _ source: ImageSource, token: String, lifecycle: LifecycleManager, store: TerminalImageStore?,
        mayAnimate: () -> Bool
    ) {
        if self.source != source {
            // Kept: the view has not moved, so a scroll view has no change to
            // report, and the new picture would wait for one for ever.
            let wasShown = isShown
            stop(token: token, lifecycle: lifecycle, store: store)
            isShown = wasShown
            self.source = source
        }
        if case .unasked = progress { progress = mayAnimate() ? .candidate : .still }
    }

    /// Whether the frames are to be decoded now, which it answers once: the file
    /// may hold some, and it is shown. A scroll view's report comes when the frame
    /// that first drew it is done, so one drawn where nobody can see it decodes
    /// nothing.
    var startsDecoding: Bool {
        guard case .candidate = progress, isShown == true else { return false }
        progress = .decoding
        return true
    }

    /// Whether there is anything a scroll view's report would change.
    var watchesVisibility: Bool {
        switch progress {
        case .unasked, .still: false
        case .candidate, .decoding, .ready: true
        }
    }

    /// The frames, where they have been decoded.
    var animation: AnimatedImage? {
        if case .ready(let animation) = progress { return animation }
        return nil
    }

    /// Whether the time is running, not stopped for a scroll view not showing it.
    var isPlaying: Bool { isShown != false }

    /// How long the frames have played by `now`: from now, the first time it is
    /// asked, when `starting` runs too. The time it is not shown does not count,
    /// so it carries on from where it stopped.
    func elapsed(at now: Int64, starting: () -> Void) -> Int64 {
        guard let startedAt else {
            startedAt = now
            starting()
            return 0
        }
        if isPlaying, let pausedAt {
            self.startedAt = startedAt &+ (now &- pausedAt)
            self.pausedAt = nil
        } else if !isPlaying, pausedAt == nil {
            pausedAt = now
        }
        return (pausedAt ?? now) &- (self.startedAt ?? now)
    }

    /// Takes in what the decode came back with.
    func finishDecoding(_ animation: AnimatedImage?) {
        progress = animation.map { .ready($0) } ?? .still
    }
}
