//  🖥️ TUI — A Terminal UI framework for Swift
//  DepthLimitTests.swift
//
//  A page nested too deeply for the stack, through the real frame path: what
//  it draws, what it reports, and what comes back when it is shallower.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUIView

/// Further than any stack holds, debug or release, on any platform CI runs.
private let farPastTheLimit = 100_000

/// A leaf with state, its button the one way to change it.
private struct Tally: View {
    var mark: LimitMark?
    @State private var count = 0

    var body: some View {
        Button("tally \(count)") { count += 1 }
            .onAppear { mark?.appearances += 1 }
            .onDisappear { mark?.disappearances += 1 }
    }
}

/// A `VStack` in a `VStack`, `depth` levels, with nothing but the leaf to draw:
/// the shape that left a blank page.
private struct BareNest: View {
    let level: Int
    let depth: Int
    var mark: LimitMark?

    var body: some View {
        if level >= depth {
            Tally(mark: mark)
        } else {
            VStack { Self(level: level + 1, depth: depth, mark: mark) }
        }
    }
}

/// ``BareNest`` with every level erased, as a tree built at run time is.
private struct ErasedNest: View {
    let level: Int
    let depth: Int

    var body: some View {
        if level >= depth {
            AnyView(Tally())
        } else {
            AnyView(VStack { Self(level: level + 1, depth: depth) })
        }
    }
}

/// ``BareNest`` through a loop.
private struct LoopNest: View {
    let level: Int
    let depth: Int

    var body: some View {
        if level >= depth {
            Tally()
        } else {
            VStack { ForEach(0..<1, id: \.self) { _ in Self(level: level + 1, depth: depth) } }
        }
    }
}

/// A tree that is one long chain.
private struct OutlineChainNode: Identifiable {
    let id: Int
    var children: [Self]?
}

/// A page around a deep view: what is above and below it must still draw.
private struct Page<Content: View>: View {
    let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("top of the page")
            content
            Text("bottom of the page")
        }
    }
}

/// A page whose nesting can change, with a button above the nesting.
private struct ChangingDepth: View {
    @State private var depth = farPastTheLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("shallower") { depth = 10 }
            BareNest(level: 0, depth: depth)
        }
    }
}

// The recursive views that never stop, each a way through the walk: containers,
// a body that is itself, erasure, members read through, sections read through,
// form rows read through, and two children at every level, which the stack alone
// does not bound.
private struct ForeverStack: View { var body: some View { VStack { Self() } } }
private struct ForeverSelf: View { var body: Self { Self() } }
private struct ForeverErased: View { var body: some View { AnyView(Self()) } }
private struct ForeverGroup: View { var body: some View { Group { Self() } } }
private struct ForeverLoop: View { var body: some View { ForEach(0..<1, id: \.self) { _ in Self() } } }
private struct ForeverPadded: View { var body: some View { Self().padding(1) } }
private struct ForeverCondition: View {
    @State private var goesOn = true
    var body: some View { if goesOn { Self() } }
}
private struct ForeverSection: View { var body: some View { Section { Self() } } }
private struct ForeverForm: View { var body: some View { Form { Self() } } }
private struct ForeverTwice: View { var body: some View { VStack { Self(); Self() } } }
private struct ForeverAround: View { var body: some View { Text("x").background { Self() } } }

/// `TestApp`'s first frame of `view`, on an ordinary screen.
@MainActor
private func screen(of view: some View) -> TestScreen {
    let app = TestApp(width: 80, height: 24) { view }
    return app.screen
}

/// How many of the depth limit's reports have been made in this process.
private func reportCount() -> Int {
    SoftTrap.recorded.count { $0.hasPrefix("Views are nested too deeply to draw") }
}

/// Where a test moves the limit to, the stack pointer at the view that marks it:
/// the same views can then be past the limit and not, with their identities and
/// values unchanged, as a change of thread can make them.
@MainActor
private final class LimitMark {
    var stackPointer: UInt = 0
    var appearances = 0
    var disappearances = 0
}

/// Six levels of `VStack` above a ``Tally``, under a view that records where in
/// the stack it was drawn: far enough down that the leaf is well past a limit
/// put there, whatever the build's frames. Kept by `.equatable()`, whose value
/// never changes, so only the limit's own clear can drop what it kept.
private struct MarkedChain: View, Equatable {
    let mark: LimitMark

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.mark === rhs.mark }

    var body: some View {
        mark.stackPointer = StackGuard.currentStackPointer()
        return VStack { BareNest(level: 0, depth: 6, mark: mark) }
    }
}

/// A button to draw another frame with, above ``MarkedChain``.
private struct MarkedPage: View {
    let mark: LimitMark
    @State private var pokes = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("poke \(pokes)") { pokes += 1 }
            MarkedChain(mark: mark).equatable()
        }
    }
}

@MainActor
@Suite("Depth limit")
struct DepthLimitTests {
    /// Runs `body` with the guard's floor at `floor`, on the running thread's
    /// real stack, and puts it back. The extent is seeded first: it is `.unseeded`
    /// until something on this thread asks.
    private func withFloor(at floor: UInt?, _ body: () -> Void) {
        _ = StackGuard.hasHeadroom()
        let saved = StackGuard.cachedExtent
        defer { StackGuard.cachedExtent = saved }
        // No floor given: no headroom anywhere on the stack.
        StackGuard.cachedExtent = StackGuard.StackExtent(low: saved.low, floor: floor ?? saved.high - 1, high: saved.high)
        body()
    }

    // MARK: - What it draws

    @Test("A page too deep draws what is above and below it, and says so")
    func deepPageDrawsItsTopAndANotice() {
        let page = screen(of: Page(content: BareNest(level: 0, depth: farPastTheLimit)))
        #expect(page.contains("top of the page"))
        #expect(page.contains("bottom of the page"))
        #expect(page.contains(DepthLimit.notice))
        #expect(!page.contains("tally"))
    }

    /// The shape that was blank: nothing but the deep view, so that every level
    /// above stood on the size measured below the limit.
    @Test("Nothing but a view too deep is still not a blank page")
    func bareNestIsNotBlank() {
        #expect(screen(of: BareNest(level: 0, depth: farPastTheLimit)).contains(DepthLimit.notice))
    }

    @Test("Every way down draws the page and the notice", arguments: 0..<3)
    func everyWayDown(way: Int) {
        let page =
            switch way {
            case 0: screen(of: Page(content: ErasedNest(level: 0, depth: farPastTheLimit)))
            case 1: screen(of: Page(content: LoopNest(level: 0, depth: farPastTheLimit)))
            default: screen(of: Page(content: List { BareNest(level: 0, depth: farPastTheLimit) }))
            }
        #expect(page.contains("top of the page"))
        #expect(page.contains(DepthLimit.notice))
    }

    /// A page takes every row and column long before the limit here, so the place
    /// the walk stops has no room for the notice. The frame says so all the same.
    @Test("A notice with no room where it falls goes on the last row")
    func noticeWithNoRoomWhereItFalls() {
        let app = TestApp(width: 80, height: 24) { ForeverPadded() }
        #expect(app.screen.line(containing: DepthLimit.notice) != nil)
        let row = app.screen.location(of: DepthLimit.notice)?.y
        #expect(row == 23 || row == 0, "at \(String(describing: row))")
    }

    /// One row: a measure that answered more would push what is around it off the
    /// screen, and one that answered zero is what left the page blank.
    @Test("A measure past the limit answers the notice's size")
    func measurePastTheLimit() {
        var environment = EnvironmentValues()
        environment.stateStorage = StateStorage()
        environment.renderCache = RenderCache(valueHashPlans: .tui())
        let context = RenderContext(availableWidth: 80, availableHeight: 24, environment: environment)
        let noticeWidth = DepthLimit.notice.strippedLength
        withFloor(at: nil) {
            let offered = measureChild(Text("x"), proposal: ProposedSize(width: nil, height: nil), context: context)
            #expect(offered == .fixed(noticeWidth, 1))
            let narrow = measureChild(Text("x"), proposal: ProposedSize(width: 3, height: 0), context: context)
            #expect(narrow == .fixed(3, 0))
        }
    }

    /// A `List` over a tree lays its open rows out flat, so a tree's depth is not
    /// the view's: what the report tells an app to use must not hit the limit.
    @Test("A List over a deep tree, open all the way down, stops nowhere")
    func outlineIsFlat() {
        let trips = StackGuard.truncationCount
        var node = OutlineChainNode(id: 2_000, children: nil)
        for id in stride(from: 1_999, through: 0, by: -1) {
            node = OutlineChainNode(id: id, children: [node])
        }
        let root = node
        let app = TestApp(width: 80, height: 24) {
            List([root], children: \.children) { Text("row \($0.id)") }
        }
        app.press(.tab)
        app.press(.right, modifiers: .option)
        #expect(app.screen.contains("row 1"), "the tree is open")
        #expect(!app.screen.contains(DepthLimit.notice))
        #expect(StackGuard.truncationCount == trips)
    }

    // MARK: - Below the limit

    @Test("Below the limit nothing is cut, reported or changed")
    func belowTheLimit() {
        let reports = reportCount()
        let trips = StackGuard.truncationCount
        let app = TestApp(width: 80, height: 24) { Page(content: BareNest(level: 0, depth: 20)) }
        #expect(app.screen.contains("tally 0"))
        #expect(!app.screen.contains(DepthLimit.notice))
        #expect(StackGuard.truncationCount == trips)
        #expect(reportCount() == reports)
        // A `VStack` of one child draws that child, so the nesting changes nothing.
        let flat = TestApp(width: 80, height: 24) { Page(content: Tally()) }
        #expect(app.screen.text == flat.screen.text)
    }

    // MARK: - The report

    @Test("One report at most, however many frames and levels stop")
    func reportedOnce() {
        let reports = reportCount()
        let app = TestApp(width: 80, height: 24) { BareNest(level: 0, depth: farPastTheLimit) }
        #expect(app.screen.contains(DepthLimit.notice))
        app.resize(width: 60, height: 20)
        #expect(app.screen.contains(DepthLimit.notice))
        _ = screen(of: ErasedNest(level: 0, depth: farPastTheLimit))
        #expect(reportCount() <= reports + 1)
        #expect(reportCount() >= 1)
    }

    /// Where a running app's report goes, whose terminal is its screen. In a
    /// process of its own, whose `TUI_DIAGNOSTICS_FILE` is read for the first time
    /// here and which has made no report yet, so the count is exact. The file's
    /// contents come back on stderr, the one thing an exit test can hand over.
    @Test("One report to TUI_DIAGNOSTICS_FILE, saying why and what to do")
    func reportReachesTheDiagnosticsFile() async {
        let result = await #expect(processExitsWith: .success, observing: [\.standardErrorContent]) {
            let contents = await MainActor.run {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("depth-limit-\(UUID().uuidString).log")
                ProcessWideState.setEnvironment("TUI_DIAGNOSTICS_FILE", to: url.path)
                let app = TestApp(width: 80, height: 24) { BareNest(level: 0, depth: farPastTheLimit) }
                _ = app.screen
                app.resize(width: 60, height: 20)
                _ = app.screen
                _ = screen(of: ErasedNest(level: 0, depth: farPastTheLimit))
                defer { try? FileManager.default.removeItem(at: url) }
                return (try? Data(contentsOf: url)) ?? Data()
            }
            FileHandle.standardError.write(contents)
        }
        let text = String(bytes: result?.standardErrorContent ?? [], encoding: .utf8) ?? ""
        #expect(text.components(separatedBy: "Views are nested too deeply to draw").count == 2, "\(text)")
        #expect(text.contains("the stack ran short"), "why")
        #expect(text.contains("needs a case where it stops"), "what to do")
    }

    // MARK: - When it is shallower again

    @Test("A page that becomes shallower draws in full, and its leaf works")
    func shallowerDrawsInFull() throws {
        let app = TestApp(width: 80, height: 24) { ChangingDepth() }
        #expect(app.screen.contains(DepthLimit.notice))
        try app.click("shallower")
        #expect(!app.screen.contains(DepthLimit.notice))
        #expect(app.screen.contains("tally 0"))
        try app.click("tally 0")
        #expect(app.screen.contains("tally 1"))
    }

    /// Where the limit falls is the thread's stack as much as the tree: the same
    /// views can be past it one frame and not the next. What was cut comes back
    /// with its state, and the notice is not kept: the `.equatable()` chain's
    /// value and identity stay the same, so nothing but the limit's own clear can
    /// drop the buffer it was drawn into.
    @Test("What was past the limit comes back with its state, and no notice is kept")
    func stateComesBack() throws {
        let mark = LimitMark()
        let app = TestApp(width: 80, height: 24) { MarkedPage(mark: mark) }
        try app.click("tally 0")
        #expect(app.screen.contains("tally 1"))
        #expect(mark.stackPointer != 0)

        // A new width, for a walk the kept buffer cannot serve.
        withFloor(at: mark.stackPointer) {
            app.resize(width: 70, height: 24)
            #expect(app.screen.contains(DepthLimit.notice), "the limit is above the leaf")
            #expect(!app.screen.contains("tally"))
            #expect(mark.disappearances == 1, "as a view leaving the screen does")
        }

        // The limit is back where it was, and the page's next frame at this width
        // would serve what the last one kept, if it had kept it.
        try app.click("poke 0")
        #expect(app.screen.contains("poke 1"))
        #expect(!app.screen.contains(DepthLimit.notice), "nothing kept the notice")
        #expect(app.screen.contains("tally 1"), "the leaf's state came back with it")
        #expect(mark.appearances == 2)
    }

    // MARK: - Never a crash

    /// Each of these, or the walk it goes by, ran off the end of the stack or
    /// never finished its first frame.
    @Test("A recursive view that never stops does not crash or hang", arguments: 0..<11)
    func neverStops(shape: Int) {
        let page =
            switch shape {
            case 0: screen(of: Page(content: ForeverStack()))
            case 1: screen(of: Page(content: ForeverSelf()))
            case 2: screen(of: Page(content: ForeverErased()))
            case 3: screen(of: Page(content: ForeverGroup()))
            case 4: screen(of: Page(content: ForeverLoop()))
            case 5: screen(of: Page(content: ForeverPadded()))
            case 6: screen(of: Page(content: ForeverCondition()))
            case 7: screen(of: Page(content: List { ForeverSection() }))
            case 8: screen(of: Page(content: ForeverForm()))
            case 9: screen(of: Page(content: ForeverTwice()))
            default: screen(of: Page(content: ForeverAround()))
            }
        #expect(page.contains("top of the page"))
        #expect(page.contains(DepthLimit.notice))
    }

    /// An `AnyView` of an `AnyView`, built before the walk: no `body` on the way
    /// down, so nothing but the `AnyView`'s own guard stops the draw, and its
    /// value hash runs out of stack at every level on the way.
    @Test("An erased chain built at run time does not crash or hang")
    func erasedChainBuiltAtRunTime() {
        var chain = AnyView(Text("end of the chain"))
        for _ in 0..<20_000 {
            chain = AnyView(chain)
        }
        let page = screen(of: Page(content: chain))
        #expect(page.contains("top of the page"))
        #expect(page.contains(DepthLimit.notice))
    }
}
