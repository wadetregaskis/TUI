//  🖥️ TUI — A Terminal UI framework for Swift
//  TestApp.swift
//
//  An app or a view held live for a test: real frames, real input, and a clock
//  that moves only when told to.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Synchronization
import TUIApp
import TUICore
import TUIFoundation

/// An app or a view running in a test, with no terminal.
///
/// Make one, act on it, and read its ``screen``:
///
/// ```swift
/// import Testing
/// import TUITesting
///
/// @MainActor
/// @Test func counts() {
///     let app = TestApp(width: 40, height: 10) { Counter() }
///     app.press(.space)
///     #expect(app.screen.contains("Count: 1"))
/// }
/// ```
///
/// It runs what a running app runs: the same render loop, focus system and
/// input chain. `@State` lasts from frame to frame, `.onAppear` and `.task`
/// run, a key goes to the control with the focus, and a click goes to what the
/// last frame drew at that cell. Only the terminal is missing.
///
/// Each action draws the frames it causes before it returns, so what you read
/// afterwards is up to date. The first frame is drawn the first time you look
/// or act, and the clock stands still until you call ``advance(by:)``.
///
/// What it draws does not depend on how fast the machine is. A running app
/// times its views and keeps more of those it finds slow, so how often a body
/// runs there varies with the machine and its load. A `TestApp` times nothing,
/// so a test that counts body evaluations or draws gets the same count on a
/// laptop as on a busy CI runner.
///
/// Nor does it depend on where the tests run. A running app draws in the
/// colours its environment says the terminal has: none under `NO_COLOR`, which
/// `swift test` sets whenever its output is not a terminal, and what `TERM`
/// and `COLORTERM` say elsewhere. A `TestApp` draws in 24-bit colour, so
/// ``TestScreen/styledLines`` are the same in a terminal, down a pipe and on CI.
/// To see it in fewer colours, pin them around the test:
///
/// ```swift
/// ColorDepth.withCurrent(.noColor) {
///     let app = TestApp { Counter() }
///     // app.screen.styledLines keep bold and underline, and no colours.
/// }
/// ```
///
/// An app that sets ``ColorDepth/current`` itself, from a `--color` flag say,
/// is drawn in 24-bit colour here too, so pin the depth to test what it sets.
/// ``ColorDepth/cap`` still applies, as it does in a running app.
@MainActor
public final class TestApp {
    /// The engine: the render loop and input chain over an in-memory terminal.
    /// `package`, for what the framework's own tests read of an app's insides.
    package let headless: HeadlessApp

    /// The frame at which ``screen`` was last read, and what it read.
    private var screenCache: (frame: Int, screen: TestScreen)?

    /// The wall clock when the clock read zero. See ``date``.
    private var startDate = Date()

    /// Runs `content` as the whole of a window, from the top-left corner.
    ///
    /// A `WindowGroup` centres what is smaller than the window. Here a view
    /// starts at row 0, column 0, so the rows you read do not move when the
    /// view changes size. A view that fills the space it is offered fills the
    /// window either way. To test the centring too, test your ``App``.
    ///
    /// `content` is called for every frame, as an app's `body` is, and a view's
    /// `@State` lasts across those calls. Change what a view shows the way your
    /// app does, with `@State` or an `@Observable` model: as in a running app, a
    /// plain variable that changes can go unnoticed by a part of the screen TUI
    /// has kept from an earlier frame.
    ///
    /// An `@AppStorage` that names no store reads and writes a store of this
    /// instance's, in memory, so a test leaves nothing behind in your real
    /// preferences. `.defaultAppStorage(_:)` in `content` overrides it. TUI's
    /// own settings, as the View menu and the settings panel save them, are
    /// kept there too, and the person's settings for all programs are never
    /// read.
    ///
    /// - Parameters:
    ///   - width: The terminal's width, in cells.
    ///   - height: The terminal's height, in rows.
    ///   - content: The view to run.
    public init<Content: View>(
        width: Int = 80, height: Int = 24, @ViewBuilder content: @escaping () -> Content
    ) {
        undoManager = UndoManager()
        headless = HeadlessApp(
            TestViewHost(content: content), width: width, height: height, undoManager: undoManager)
        useInMemoryAppStorage()
    }

    /// Runs a whole app, its scenes and its window's bars included, laid out as
    /// it is in a terminal.
    ///
    /// An `@AppStorage` that names no store reads and writes a store of this
    /// instance's, in memory, unless the app's scene or views set their own.
    ///
    /// - Parameters:
    ///   - app: The app to run. It is never launched, so no `main` runs.
    ///   - width: The terminal's width, in cells.
    ///   - height: The terminal's height, in rows.
    public init<A: App>(_ app: A, width: Int = 80, height: Int = 24) {
        undoManager = UndoManager()
        headless = HeadlessApp(app, width: width, height: height, undoManager: undoManager)
        useInMemoryAppStorage()
    }

    private func useInMemoryAppStorage() {
        let store = TestAppStorage()
        headless.configureEnvironment { $0.defaultAppStorage = DefaultAppStorage(store) }
        // TUI's own settings for the program too, as a running app keeps them
        // beside its `@AppStorage`; none for all programs.
        headless.keepSettings(programStore: store, allProgramsFile: nil)
    }

    // MARK: - Reading

    /// What is on the screen now.
    ///
    /// A frame the app has asked for since the last one is drawn first, as a
    /// running app's loop would have drawn it by the time anyone looked: what
    /// a test changes outside a key press or a click, such as an undo through
    /// ``undoManager`` or a write to an `@Observable` model a view read, shows
    /// here as it would on a terminal.
    public var screen: TestScreen {
        start()
        drawAskedFrames()
        if let screenCache, screenCache.frame == headless.framesDrawn { return screenCache.screen }
        let screen = TestScreen(styledLines: headless.screen)
        screenCache = (headless.framesDrawn, screen)
        return screen
    }

    /// The ID of the control that has the keyboard focus, or `nil` when none has.
    ///
    /// Give a control an ID you can compare with `.focusID(_:)`. One you have
    /// not named has an ID made from its place in the view tree, which is good
    /// for comparing against an earlier reading and little else.
    public var focusedID: String? {
        start()
        drawAskedFrames()
        return headless.focusedID
    }

    /// The text the app last put on the clipboard, or `nil` before it has
    /// copied anything.
    ///
    /// Every copy the app makes lands here: a text field's ⌃C, a `.copyable`
    /// view's, a menu item that calls `\.copyToClipboard`. Nothing reaches the
    /// clipboard of the machine the test runs on, nor a terminal.
    public var clipboard: String? {
        start()
        return headless.lastCopiedText
    }

    /// The app's undo manager, which `@Environment(\.undoManager)` reads.
    ///
    /// A running app has one, made as it starts, and so does a `TestApp`: the
    /// undo keys (⌃Z) undo through it, the status bar shows its undo and redo
    /// items, and a `DocumentGroup` empties it when New or Open replaces the
    /// document. Read it to check what an action left to undo:
    ///
    /// ```swift
    /// app.press(.character("k"), modifiers: .control)
    /// #expect(app.undoManager.canUndo)
    /// ```
    ///
    /// An undo or redo through it draws as one by key does: what it changes
    /// shows on the next read of the ``screen``, as a running app draws it.
    public let undoManager: UndoManager

    /// The title the app has given the terminal's window, or `nil` while it
    /// has given none and the window shows its own.
    ///
    /// The window in front's scene title — `WindowGroup("Notes")`'s, a
    /// `DocumentGroup` window's document name with "Edited" while it has
    /// unsaved changes — or a root `.navigationTitle` that no top bar shows.
    /// It is not on the ``screen``: a terminal draws it in its own title bar
    /// or tab.
    public var windowTitle: String? {
        start()
        drawAskedFrames()
        return headless.terminalWindowTitle
    }

    /// Whether the app has asked to quit, by its quit key, its Quit menu item
    /// or its last window closing.
    ///
    /// A running app would end there. A test has no process to end, so the app
    /// carries on drawing.
    public var hasRequestedQuit: Bool { headless.quitsRequested > 0 }

    /// Changes the terminal's size, as resizing its window does, and draws the
    /// frames that causes.
    public func resize(width: Int, height: Int) {
        start()
        headless.resize(width: width, height: height)
        drawFrames()
    }

    // MARK: - Time

    /// How much time has passed since the app started: what ``advance(by:)``
    /// has added. It is the only clock the frames read.
    public var elapsed: Duration { .nanoseconds(headless.lastFrameNanos) }

    /// The wall clock the frames read, which is what a `TimelineView` shows.
    ///
    /// It starts at the machine's clock when the app is made, since a view may
    /// well compare it with `Date()`, and moves with ``advance(by:)``. Set it
    /// for a test of a particular date or time, and the next frame reads it.
    public var date: Date {
        get { startDate.addingTimeInterval(TimeInterval(headless.lastFrameNanos) / 1e9) }
        set { startDate = newValue.addingTimeInterval(-TimeInterval(headless.lastFrameNanos) / 1e9) }
    }

    /// Moves the clock on by `duration`, drawing every frame the app asks for
    /// on the way, and one at the end.
    ///
    /// An animation asks for frames while it plays, so an animation of a second
    /// has played out after `advance(by: .seconds(1))`, and half way through
    /// after half that. A `TimelineView`, a long press, a tooltip's delay and a
    /// blinking cursor move on it too. This takes no real time beyond drawing:
    /// an hour with nothing animating is one frame.
    ///
    /// A change the test made itself since the last frame, rather than through
    /// an event — a model's property set in the test, under `withAnimation` or
    /// not — is drawn first, at the instant it was made, as a running app's
    /// loop draws it at once: an animation it starts plays over the time this
    /// moves on.
    ///
    /// Work that runs on the real clock does not move on it, such as a
    /// `Task.sleep` in `.task`. Hand such a view a ``TestClock``, or wait for
    /// what it does with ``wait(for:timeout:)``.
    public func advance(by duration: Duration) {
        start()
        // An event draws the frames it causes before it returns; a change the
        // test made in its own code has asked for its frame and waits. Drawn
        // only at the target, it began its animation there: `withAnimation {
        // model.showing = true }` then `advance(by: .seconds(1))` drew the
        // arriving row at the first instant of its transition, blank, and a
        // moved value where it started.
        if headless.takeFrameRequest() { drawFrames() }
        let target = headless.lastFrameNanos &+ max(0, Self.nanoseconds(in: duration))
        while let wake = headless.nextWake(after: headless.lastFrameNanos), wake <= target {
            drawFrames(atNanos: wake)
        }
        drawFrames(atNanos: target)
    }

    private static func nanoseconds(in duration: Duration) -> Int64 {
        let (seconds, attoseconds) = duration.components
        return seconds &* 1_000_000_000 &+ attoseconds / 1_000_000_000
    }

    // MARK: - Waiting

    /// Draws frames until the screen shows `text`, for work that runs on its
    /// own time, such as a `.task` that loads something.
    ///
    /// A frame is drawn only when the app asks for one, as a running app's
    /// is: a write to a `@State`, to an `@Observable` property a view read,
    /// or to `@AppStorage` asks for one. A view reading a plain variable —
    /// neither `@State` nor an `@Observable`'s property — that is changed
    /// outside an event asks for none, so a wait for what it would draw times
    /// out, where a running app would go on showing the old value. Make the
    /// variable `@State` or a property of an `@Observable`.
    ///
    /// - Parameters:
    ///   - text: What to wait for, as ``TestScreen/contains(_:)`` finds it.
    ///   - timeout: How long to wait before giving up. It is only there to end
    ///     a test that would otherwise hang, so it is long, and a passing test
    ///     takes as long as the work does.
    /// - Throws: ``TestAppError`` if `timeout` passes first, with the screen.
    public func wait(for text: String, timeout: Duration = .seconds(60)) async throws {
        try await wait(until: { self.screen.contains(text) }, timeout: timeout, waitingFor: "“\(text)” on the screen")
    }

    /// Draws frames until `condition` is true, for work that runs on its own
    /// time, such as a `.task` that loads something.
    ///
    /// A frame is drawn only when the app asks for one, so a view reading a
    /// plain variable changed outside an event is not redrawn: see
    /// ``wait(for:timeout:)``.
    ///
    /// - Parameters:
    ///   - condition: What to wait for. Read ``screen`` in it, or your own state.
    ///   - timeout: How long to wait before giving up. It is only there to end
    ///     a test that would otherwise hang, so it is long, and a passing test
    ///     takes as long as the work does.
    /// - Throws: ``TestAppError`` if `timeout` passes first, with the screen.
    public func wait(until condition: @MainActor () -> Bool, timeout: Duration = .seconds(60)) async throws {
        try await wait(until: condition, timeout: timeout, waitingFor: "the condition")
    }

    private func wait(
        until condition: @MainActor () -> Bool, timeout: Duration, waitingFor what: String
    ) async throws {
        start()
        var wait = HangBreaker(timeout: timeout)
        while !condition() {
            guard !wait.hasTripped else {
                throw TestAppError("Gave up waiting for \(what) after \(wait.report()). The screen:\n\(screen)")
            }
            let turn = wait.nextTurn()
            // Mostly a yield: work on the main actor needs only that. Every so
            // often a nap, for work on the pool; a frame is drawn only when the
            // app has asked for one, as a running app's render loop draws.
            if wait.isOverdue || turn.isMultiple(of: 50) {
                try? await Task.sleep(for: .milliseconds(1))
            } else {
                await Task.yield()
            }
            if headless.takeFrameRequest() { drawFrames() }
        }
    }

    // MARK: - Frames

    /// Draws the first frame, unless a frame has been drawn.
    package func start() {
        if headless.framesDrawn == 0 { drawFrames() }
    }

    /// Draws the frames the app has asked for since the last one, if it has
    /// asked for any: what a running app's loop does whenever the app asks,
    /// so what the test reads is what a terminal would show. Without it, a
    /// change made between events — an undo the test made through
    /// ``undoManager``, say — stayed off the screen until the next input.
    private func drawAskedFrames() {
        if drawsAskedFramesOnRead, headless.takeFrameRequest() { drawFrames() }
    }

    /// Whether reading the screen draws the frames the app has asked for
    /// first (``drawAskedFrames()``). The framework's own tests that draw
    /// each frame by hand, at an instant of their choosing, and ask whether
    /// the app wanted another, turn it off: they read what they drew.
    package var drawsAskedFramesOnRead = true

    /// Draws the frames a change causes, at the clock's present reading, or at
    /// `nanos`: one, and more for as long as a frame asks for another, as a
    /// `.onChange` that writes `@State` does.
    ///
    /// Bounded, because a view that asks for a frame on every frame would
    /// otherwise never let the test go. A running app would go on drawing it,
    /// and this draws enough of those frames to show it.
    func drawFrames(atNanos nanos: Int64? = nil) {
        let at = nanos ?? headless.lastFrameNanos
        for _ in 0..<Self.framesPerChange {
            _ = headless.takeFrameRequest()
            let asked = headless.framesAsked
            drawFrame(atNanos: at)
            if !headless.takeFrameRequest(), headless.framesAsked == asked { break }
        }
    }

    /// Draws a frame at the depth the test pinned with `ColorDepth.withCurrent`,
    /// else at `drawnColorDepth`: never at what the environment says, which
    /// differs from one run of a test to the next (see the type's discussion).
    private func drawFrame(atNanos nanos: Int64) {
        ColorDepth.withCurrent(ColorDepth.taskPin ?? Self.drawnColorDepth) {
            headless.frame(atNanos: nanos, date: startDate.addingTimeInterval(TimeInterval(nanos) / 1e9))
        }
    }

    /// The colours a frame is drawn with when the test pinned none: millions.
    static let drawnColorDepth = ColorDepth.truecolor

    private static let framesPerChange = 8

    // MARK: - Teardown

    /// The tasks `.task` started end with the app, as they do with a running
    /// one, rather than running on into the next test.
    isolated deinit {
        headless.lifecycle.reset()
    }
}

// MARK: - Hosting a view

/// The app a ``TestApp`` of a view runs: the view, as the whole of a window.
///
/// `App` requires `init()`, for `@main`. This app is never launched, only handed
/// to ``HeadlessApp`` with its content; the one `init()` builds has nothing on it.
private struct TestViewHost<Content: View>: App {
    let content: (() -> Content)?

    init(content: @escaping () -> Content) { self.content = content }

    init() { content = nil }

    var body: some Scene {
        WindowGroup {
            if let content {
                content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

// MARK: - Errors

/// What a ``TestApp`` throws when it cannot do what a test asked, such as
/// clicking text that is not on the screen.
///
/// There is nothing to catch: mark the test `throws`, and the test fails on that
/// line with the message, which shows the screen. This works in Swift Testing
/// and in XCTest alike, so this module depends on neither.
public struct TestAppError: Error, CustomStringConvertible, Sendable {
    /// What went wrong, with what was on the screen if that matters.
    public let description: String

    init(_ description: String) { self.description = description }
}

// MARK: - App storage

/// The store of a ``TestApp``'s `@AppStorage`: JSON in a dictionary, as the file
/// store writes it, so a value reads back as it would from there.
private final class TestAppStorage: StorageBackend {
    private let entries = Mutex<[String: (data: Data?, key: StoredKey)]>([:])

    /// The ``sceneStateStore``, in memory too, or `nil` for a store that is
    /// itself one.
    private let sceneState: TestAppStorage?

    init(keepsSceneState: Bool = true) {
        sceneState = keepsSceneState ? TestAppStorage(keepsSceneState: false) : nil
    }

    /// Where the app's `@SceneStorage` keeps its values: a store of its own,
    /// as the built-in stores keep them.
    var sceneStateStore: any StorageBackend { sceneState ?? self }

    func entry<T: Codable>(forKey key: String, as type: T.Type) -> (value: T?, key: StoredKey) {
        let entry = entries.withLock { entries in
            let entry = entries[key] ?? (nil, StoredKey())
            entries[key] = entry
            return entry
        }
        return (entry.data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }, entry.key)
    }

    func store<T: Codable>(_ value: T, forKey key: String) -> StoredKey {
        let data = try? JSONEncoder().encode(value)
        return entries.withLock { entries in
            let stored = entries[key]?.key ?? StoredKey()
            entries[key] = (data, stored)
            return stored
        }
    }

    func remove(forKey key: String) -> StoredKey? {
        entries.withLock { entries in
            entries[key]?.data = nil
            return entries[key]?.key
        }
    }

    func synchronize() {}
}
