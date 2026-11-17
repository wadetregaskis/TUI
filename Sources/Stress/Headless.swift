//  🖥️ TUI — A Terminal UI framework for Swift
//  Headless.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUI
import TUICore

// MARK: - Headless runners

/// No-PTY entry points: render scenarios via `renderToBuffer` without a
/// terminal. `--selfcheck` is a smoke test (renders each scenario once);
/// `--bench` is the profiling instrument — a counted render loop suitable for
/// `xctrace --launch` (no debugger attach needed), mirroring the existing
/// `Tools/Profiling/RenderHarness`.
enum Headless {

    /// A checksum over the frame's *content*, not merely its dimensions.
    ///
    /// The dimensions are a constant for a given viewport — 120 + 40 + 40 for
    /// every scenario, at every scale — so a checksum built from them cannot
    /// tell a fully rendered frame from an empty one. That is exactly how this
    /// harness came to report healthy-looking numbers on Linux while rendering
    /// nothing at all: only a top-level buffer collapsing to 0x0 showed up, and
    /// any partial collapse would not have.
    ///
    /// Hashing the bytes keeps the optimiser from eliding the render loop (the
    /// checksum's original job) *and* makes the printed number a correctness
    /// signal: identical output hashes identically, on every run and every
    /// platform. Deliberately not `String.hashValue`, which is seeded per
    /// process and so differs between two runs of the same work.
    ///
    /// Eight bytes a step, from each line's contiguous UTF-8 storage, so the
    /// hash's serial multiply runs once per word rather than once per byte:
    /// byte by byte it was 20.6% of a `dashboard` profile. The checksum is
    /// outside the timed region, so it never moved a bench's numbers — only
    /// every share a profile of one reports, which it understated by as much.
    /// Each line's length closes its words, so where the lines break counts.
    private static func contentChecksum(_ buffer: FrameBuffer) -> Int {
        contentChecksum(lines: buffer.lines)
    }

    /// ``contentChecksum(_:)`` over lines however they were drawn: a session's
    /// screen, for `--frame-checksums`.
    static func contentChecksum(lines: [String]) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for var line in lines {
            line.withUTF8 { hash = unsafe mixed(UnsafeRawBufferPointer($0), into: hash) }
        }
        return Int(truncatingIfNeeded: hash)
    }

    /// FNV-1a's step over `bytes` taken a little-endian word at a time, then
    /// the bytes that do not fill one, then their count.
    private static func mixed(_ bytes: UnsafeRawBufferPointer, into start: UInt64) -> UInt64 {
        let prime: UInt64 = 0x100_0000_01b3
        var hash = start
        var offset = 0
        while offset + 8 <= bytes.count {
            let word = unsafe UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
            hash = (hash ^ word) &* prime
            offset += 8
        }
        while offset < bytes.count {
            hash = unsafe (hash ^ UInt64(bytes[offset])) &* prime
            offset += 1
        }
        return (hash ^ UInt64(bytes.count)) &* prime
    }

    /// Whether a frame carries anything a reader would see. A frame of nothing
    /// but spaces and escape sequences is not a rendered scenario.
    private static func isBlank(_ buffer: FrameBuffer) -> Bool {
        !buffer.lines.contains { hasVisibleContent($0) }
    }

    /// Whether one line paints something visible, ignoring ANSI sequences.
    ///
    /// Skipping only the `ESC` byte is not enough, and getting this wrong
    /// defeats the check entirely: the *parameter* bytes of `ESC[48;5;236m`
    /// are ordinary printable characters, so a frame consisting of nothing but
    /// background fill would count as content and a blank render would sail
    /// through. The whole sequence has to be consumed — CSI parameters run
    /// until a final byte in 0x40...0x7E.
    private static func hasVisibleContent(_ line: String) -> Bool {
        var scalars = line.unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            guard scalar == "\u{1b}" else {
                // Above 0x20 is printable and not a space; 0x20 and below are
                // spaces, control characters, or the sequence remnants.
                if scalar.value > 0x20 { return true }
                continue
            }
            guard let introducer = scalars.next() else { break }
            // Only CSI (`ESC[`) carries parameter bytes that could be mistaken
            // for content; the two-byte escapes end at the introducer.
            if introducer == "[" {
                while let byte = scalars.next(), !(0x40...0x7E).contains(byte.value) {}
            }
        }
        return false
    }

    /// Builds a render environment. Each call is independent (fresh state +
    /// cache) so `--bench --cold` can reset between frames to measure the cold
    /// measure+render cost rather than the cache-warm steady state.
    ///
    /// Except for `valueHashPlans`, which the caller keeps and hands to every
    /// cache it makes, as a `TUIContext` keeps one for its own: a plan is a
    /// fact about a type, not a memo (`RenderCache.valueHashPlans`), so a
    /// `--cold` frame is one that misses every memo, not also one that sees
    /// every type for the first time — which an app does once per type, not
    /// once a frame.
    @MainActor
    private static func makeContext(
        cols: Int, rows: Int, channels: HeadlessInputChannels, valueHashPlans: ValueHashPlans
    ) -> RenderContext {
        var environment = EnvironmentValues()
        // The per-walk input registries the app wires: a key dispatcher, a
        // shortcut registry, a status bar and a mouse dispatcher. Without them a
        // bench measures a tree with its input half removed — a `Button`'s
        // `.keyboardShortcut` registered nothing and declared nothing, an
        // `onKeyEvent` trapped on its missing dispatcher, and every control that
        // answers the pointer skipped the hit-test handler, the feature request
        // and the region it emits in an app. Shared across `--cold` contexts,
        // because the frame loop empties them before every walk as `RenderLoop`
        // does.
        channels.install(into: &environment)
        environment.stateStorage = StateStorage()
        environment.renderCache = RenderCache(valueHashPlans: valueHashPlans)
        // Route through a real `TUIContext` so EVERY service the render pass
        // may reach is wired, not just the two the scenarios happened to need.
        // `.preference` force-unwraps its storage, so the `preferences`
        // scenario trapped on a context that had none — and nothing had
        // published a preference here before, which is how it stayed missing.
        // `.preference` force-unwraps its storage, so the `preferences`
        // scenario trapped without this. Nothing here had published a
        // preference before, which is how it stayed missing.
        environment.preferenceStorage = PreferenceStorage()
        // `TUI_PLAIN_TEXT=transliterate`, as the app runner writes it at the
        // root, so a bench can price spelling text in ASCII before layout.
        environment.respell(PlainTerminalText.respelling(in: ProcessInfo.processInfo.environment))
        // Through the installer, so the measure memo's gate — which reads the
        // tracker off the render cache, not out of the environment — is open
        // here as it is in the app. Getting this wrong is §27's disaster
        // verbatim: with the memo unreachable the bench measured a flat ~10%
        // regression of nothing at all. `beginRenderPass()` in the frame loop
        // does not clear the mirror, so installing once per context is enough,
        // warm and `--cold` alike.
        environment.installVolatileReadTracker(VolatileReadTracker())
        // Rooted at a TYPE, as `RenderLoop` roots the app, not at the
        // context's default raw path string. Every identity below a raw root
        // is raw-rooted, and for those `ViewIdentity.isAncestor(of:)` has to
        // render both full path strings and compare prefixes — so the end-of-
        // pass prune, which asks that of every retained root against every
        // unvisited entry, was 88–95% of a frame here and nothing in the app.
        return RenderContext(
            availableWidth: cols, availableHeight: rows, environment: environment,
            identity: ViewIdentity(rootType: BenchRoot.self))
    }

    /// Stamps the frame's one wall-clock date on `context`'s render cache, as
    /// `RenderLoop` and `ViewRenderer` stamp theirs, so a `TimelineView` in a
    /// scenario resolves its schedule once a walk, not once a read: left
    /// unstamped, it read `Date()` in the measure and again in the render, and
    /// a walk that began just short of an entry boundary laid out one entry and
    /// drew the next (`RenderCache.frameDate`).
    ///
    /// `date` is the wall clock's unless given: `--frame-checksums` gives the
    /// date of ``checksumDate(tick:)``.
    @MainActor
    private static func stampFrameDate(_ context: RenderContext, date: Date? = nil) {
        context.environment.renderCache?.frameDate = date ?? Date()
    }

    /// The date `--bench --frame-checksums` stamps on frame `tick`: a fixed
    /// date, moved on a 1/60 s frame a tick, as the run loop's animation clock
    /// is (``DrivenScenario/runsAnimationClock``). The wall clock's date made a
    /// scenario that shows the time draw different frames on every run —
    /// `app-shapes/timeline-rows`, whose `TimelineView`s draw a glyph for each
    /// eighth of a second, differed in all 60 frames between two runs of one
    /// binary — so `frame_parity.py` could not tell a change that drew
    /// differently from the clock moving on. The timings stay on the wall
    /// clock: without `--frame-checksums` nothing changes.
    private static func checksumDate(tick: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 + Double(tick) / 60)
    }

    /// The type the bench's identity tree is rooted at — a stand-in for the
    /// `App` type `RenderLoop` roots a real tree at.
    private enum BenchRoot {}

    /// One thing `--selfcheck` renders: a scenario, or one variant of a matrix
    /// scenario.
    ///
    /// A matrix scenario contributes one case per variant rather than one case,
    /// because the variant a config happens to select is not what wants
    /// checking — the whole space is. Thirty-odd `Table` shapes cost a second of
    /// wall clock here and are the only thing that renders every one of them.
    struct SelfcheckCase {
        let id: String
        let title: String
        let make: @MainActor () -> AnyView
        /// A driven case's view and its write (see ``DrivenScenario``).
        var drive: (@MainActor () -> DrivenScenario?)?
        /// Whether its page moves every tick (``ScenarioVariant/scrolls``).
        var scrolls = false
    }

    /// `scenario`'s driven form under `config`, deferred, when it has one.
    private static func driving(
        _ scenario: Scenario, _ config: StressConfig
    ) -> (@MainActor () -> DrivenScenario?)? {
        guard let drive = scenario.drive else { return nil }
        return { drive(config) }
    }

    /// Every scenario, with matrix scenarios expanded into their variants.
    @MainActor
    static func selfcheckCases(_ config: StressConfig) -> [SelfcheckCase] {
        Scenarios.all.flatMap { scenario -> [SelfcheckCase] in
            let variants = ScenarioVariants.variants(of: scenario.id)
            guard !variants.isEmpty else {
                return [SelfcheckCase(
                    id: scenario.id, title: scenario.title, make: { scenario.make(config) },
                    drive: driving(scenario, config))]
            }
            return variants.map { variant in
                var scoped = config
                scoped.variant = variant.id
                return SelfcheckCase(
                    id: "\(scenario.id)/\(variant.id)", title: variant.summary, make: { scenario.make(scoped) },
                    drive: driving(scenario, scoped), scrolls: variant.scrolls)
            }
        }
    }

    /// How many steps the selfcheck plays a session, verified against its
    /// cache-cleared twin.
    static let selfcheckSessionSteps = 150
    /// The selfcheck resizes the terminal under a session every this many
    /// steps.
    static let selfcheckResizeEvery = 37

    /// The steps the selfcheck plays `session`: 150, or for a perf case
    /// (`fullLength` false) as far as reaches every phase of its script and
    /// the first resize, which is 38 for every case so far. A case's job is
    /// its counts, which `--check-counts` plays in full; what the selfcheck
    /// adds is the cache-cleared twin over each phase and a resize, and the
    /// 112 steps more of fifty-nine cases cost the gate about four minutes,
    /// debug.
    /// `--full-cases` plays them 150 too.
    static func selfcheckSteps(of session: SessionDescriptor, fullLength: Bool) -> Int {
        guard !fullLength, let reach = session.stepsToEveryPhase else { return selfcheckSessionSteps }
        return min(selfcheckSessionSteps, max(reach, selfcheckResizeEvery + 1))
    }

    /// Renders every scenario (and every variant) once at a fixed size; prints
    /// dimensions. Returns the number that produced an empty buffer (a failure).
    /// `fullLength` plays the perf cases' sessions as long as every other's
    /// (``selfcheckSteps(of:fullLength:)``).
    @MainActor
    static func selfcheck(_ config: StressConfig, fullLength: Bool = false) -> Int {
        let clock = StressClock()
        var failures = 0
        let cases = selfcheckCases(config)
        let valueHashPlans = ValueHashPlans.tui()
        print("selfcheck — scale \(config.scale) seed \(config.seed) @ 120x40")
        for scenario in cases {
            let channels = HeadlessInputChannels()
            let context = makeContext(cols: 120, rows: 40, channels: channels, valueHashPlans: valueHashPlans)
            // A driven case's model moves between the two renders, so the
            // second — the one the verifier reads — follows a write.
            let driven = scenario.drive?()
            let view = AnyView((driven?.view ?? scenario.make()).environment(clock))
            let trimmedBefore = StackGuard.truncationCount
            // TWICE, with the pass lifecycle between, because a memo only
            // SERVES on a second render — so a one-render check never exercised
            // the buffer memo at all, and `TUI_VERIFY_RENDER_MEMO` had
            // nothing to verify. The second render is what the verifier reads.
            channels.beginWalk()
            context.environment.stateStorage?.beginRenderPass()
            context.environment.renderCache?.beginRenderPass()
            stampFrameDate(context)
            _ = renderFrame(view, context: context, channels: channels, cols: 120, rows: 40)
            context.environment.stateStorage?.endRenderPass()
            context.environment.renderCache?.removeInactive()
            driven?.advance(1)
            channels.beginWalk()
            context.environment.stateStorage?.beginRenderPass()
            context.environment.renderCache?.beginRenderPass()
            stampFrameDate(context)
            let buffer = renderFrame(view, context: context, channels: channels, cols: 120, rows: 40)
            context.environment.stateStorage?.endRenderPass()
            let staleServes = context.environment.renderCache?.renderMemoMismatches ?? []
            let trimmed = StackGuard.truncationCount - trimmedBefore
            let stood = scenario.scrolls && !movesOnTick(
                view, from: buffer, clock: clock, context: context, channels: channels)
            // Dimensions alone are too weak a check: a frame of the right size
            // holding nothing passes it, and so does one the stack guard cut
            // short, which draws a notice. Require visible content, and a whole
            // tree.
            let ok =
                buffer.width > 0 && buffer.height > 0 && !isBlank(buffer) && trimmed == 0
                && staleServes.isEmpty && !stood
            if !ok { failures += 1 }
            // Padded, never TRUNCATED: `padding(toLength:)` cuts a longer
            // string, which silently turned `size-wrapped-1000` into
            // `size-wrapped-100` — the id of a case that does not exist, beside
            // the one that does.
            let id = scenario.id.count >= 26
                ? scenario.id
                : scenario.id.padding(toLength: 26, withPad: " ", startingAt: 0)
            let why =
                trimmed > 0
                ? "  (stack guard stopped \(trimmed) descents)"
                : (isBlank(buffer)
                    ? "  (blank)"
                    : (staleServes.isEmpty
                        ? (stood ? "  (a scrolling page drew the same frame at the next tick)" : "")
                        : "  (STALE MEMO: \(staleServes.count))"))
            print("  \(ok ? "ok  " : "FAIL") \(id) \(buffer.width)x\(buffer.height)"
                + "  \(scenario.title)\(why)")
            for line in staleServes.prefix(3) { print("      \(line)") }
            channels.discard(context)
        }
        // Every session, played a short way with its cache-cleared twin and
        // the terminal resized under it: the one check here that a UI IN USE
        // draws what it should, frame after frame, and not only at rest.
        var sessionOptions = SessionRunner.Options()
        sessionOptions.verify = true
        sessionOptions.resizeEvery = selfcheckResizeEvery
        for session in Sessions.all {
            sessionOptions.steps = selfcheckSteps(of: session, fullLength: fullLength)
            let report = SessionRunner.run(session, config: config, options: sessionOptions.sized(for: session))
            let ok = report.passed
            if !ok { failures += 1 }
            // Padded, never truncated, as the scenarios' ids above are: a perf
            // case's id, `session/case:chat-eager-follow`, is longer than 26.
            let id = "session/\(session.id)"
            let padded = id.count >= 26 ? id : id.padding(toLength: 26, withPad: " ", startingAt: 0)
            print("  \(ok ? "ok  " : "FAIL") \(padded) \(report.steps) steps  \(session.summary)")
            if let mismatch = report.scriptMismatch { print("      \(mismatch)") }
            for divergence in report.divergences.prefix(3) { print("      " + divergence) }
            for problem in report.brokenExpectations.prefix(3) { print("      " + problem) }
            for (tag, seen) in report.knownIssues.sorted(by: { $0.key < $1.key }) {
                print("      known issue [\(tag)] on \(seen.frames) frames")
            }
            for stale in report.staleServes.prefix(3) { print("      STALE MEMO: " + stale) }
            for stale in report.staleSizes.prefix(3) { print("      STALE SIZE: " + stale) }
        }
        print(
            failures == 0
                ? "selfcheck: all \(cases.count) cases rendered (\(Scenarios.all.count) scenarios), "
                    + "and every session verified (\(Sessions.all.count))"
                : "selfcheck: \(failures) FAILED")
        return failures
    }

    /// Whether `view`, drawn `first` at tick 0, draws something else at tick
    /// 1: what a page that scrolls every tick must do, or its `--bench`
    /// timings are its first frame redrawn. The clock is put back.
    @MainActor
    private static func movesOnTick(
        _ view: AnyView, from first: FrameBuffer, clock: StressClock, context: RenderContext,
        channels: HeadlessInputChannels
    ) -> Bool {
        context.environment.renderCache?.removeInactive()
        clock.tick = 1
        defer { clock.tick = 0 }
        channels.beginWalk()
        context.environment.stateStorage?.beginRenderPass()
        context.environment.renderCache?.beginRenderPass()
        stampFrameDate(context)
        let next = renderFrame(view, context: context, channels: channels, cols: 120, rows: 40)
        context.environment.stateStorage?.endRenderPass()
        return contentChecksum(next) != contentChecksum(first)
    }

    /// One frame of `view`: the walk, the scene root's geometry correction,
    /// what the frame owes its geometry observers, the effects, and the walk
    /// made again while they wrote state (`FrameSettling`) — the part of
    /// `RenderLoop.render` a headless walk still needs — on the stack
    /// `RenderLoop` draws a frame on (`LargeStack`). On Windows's 1 MiB thread
    /// stack the selfcheck's `deep` scenario was cut 28 times (6.3.3,
    /// 2026-11-17), as the app's frames would have been.
    @MainActor
    private static func renderFrame(
        _ view: AnyView, context: RenderContext, channels: HeadlessInputChannels, cols: Int, rows: Int
    ) -> FrameBuffer {
        LargeStack.run { renderFrameHere(view, context: context, channels: channels, cols: cols, rows: rows) }
    }

    /// ``renderFrame(_:context:channels:cols:rows:)``, on the stack it is given.
    @MainActor
    private static func renderFrameHere(
        _ view: AnyView, context: RenderContext, channels: HeadlessInputChannels, cols: Int, rows: Int
    ) -> FrameBuffer {
        let storage = context.environment.stateStorage
        // The global space's origin, carried down when there are readers, as
        // `RenderLoop` carries it.
        let context = context.carryingGeometryRootOrigin()
        func walk() -> FrameBuffer {
            FrameSettling.settle(
                storage: storage, cache: context.environment.renderCache, lifecycle: context.environment.lifecycle,
                appState: nil,
                walk: { effects in
                    channels.drawSettlingRootGeometry(
                        width: cols, height: rows, stateStorage: storage, effects: effects
                    ) { renderToBuffer(view, context: context) }
                },
                endWalk: { channels.endFrame($0, stateStorage: storage) },
                // The per-walk registries, emptied as the frame loop empties
                // them before the first walk.
                beginRewalk: {
                    channels.beginWalk()
                    storage?.beginSceneRender()
                })
        }
        // In the pass, as `RenderLoop` draws a frame: a `@State` made in it
        // notes it (`StateStorage.inRenderPass(_:)`).
        guard let storage else { return walk() }
        return storage.inRenderPass(walk)
    }

    /// Prints how often the geometry owners drew their subtrees again, per
    /// frame and by owner kind — the acceptance metric of the A2 design
    /// study's prediction rungs. Silent for a scenario that corrected nothing,
    /// unless it is the one built to watch it.
    private static func printGeometryCorrections(
        from before: GeometryCorrections, to after: GeometryCorrections, frames: Int, always: Bool
    ) {
        let total = after.total - before.total
        guard always || total > 0 || after.residual > before.residual else { return }
        let divisor = Double(max(1, frames))
        let perFrame = { (count: Int) in (Double(count) / divisor).formatted(.fixed(2)) }
        print("  geometry corrections/frame: \(perFrame(total)) — named \(perFrame(after.named - before.named)), "
            + "scroll view \(perFrame(after.scrollView - before.scrollView)), "
            + "root \(perFrame(after.root - before.root)), layer \(perFrame(after.layer - before.layer)); "
            + "still wrong after one: \(after.residual - before.residual)")
    }

    /// Prints what the process held over a `--bench` loop, from `memory`'s
    /// samples and the process high-water mark.
    ///
    /// Peak is what has to FIT; mean is what the process typically holds. A
    /// cache that buys CPU by keeping buffers shows up here and nowhere else,
    /// which is why this is printed beside `cpu-per-frame` rather than in a
    /// separate tool. `rss-peak` is the process high-water mark (`ru_maxrss`),
    /// so it includes the build-up before the loop; the sampled pair describe
    /// the loop itself.
    private static func printMemory(_ memory: ProcessMemory.Samples) {
        guard let peak = ProcessMemory.peakResidentBytes() else { return }
        let mb = { (bytes: UInt64) in Double(bytes) / 1_048_576 }
        guard let mean = memory.meanBytes else {
            print("  rss-peak=\((mb(peak)).formatted(.fixed(1)))MB")
            return
        }
        print(
            "  rss-peak=\((mb(peak)).formatted(.fixed(1)))MB  rss-mean=\((mb(mean)).formatted(.fixed(1)))MB  "
                + "rss-sampled-peak=\((mb(memory.peakSampled)).formatted(.fixed(1)))MB")
        // The footprint is the number a freed buffer actually moves — see
        // `ProcessMemory.currentFootprintBytes()`. Printed beside the resident
        // figures rather than instead of them, because they answer different
        // questions and only one of them exists on Linux.
        if let meanFootprint = memory.meanFootprintBytes {
            print(
                "  footprint-mean=\((mb(meanFootprint)).formatted(.fixed(1)))MB  footprint-peak=\((mb(memory.peakFootprint)).formatted(.fixed(1)))MB")
        }
    }

    /// Prints the memos' totals and what the last walk left registered.
    ///
    /// The value-memo line is `RenderCache.stats`, which counts the buffer half
    /// AND the size half of `.equatable()` and the `ForEach` row memo together,
    /// so a scenario whose rows never store a buffer can still show stores and
    /// hits there. `TUI_DEBUG_RENDER=1` logs the buffer half alone. The totals
    /// include the warm-up (under `--cold`, they are the last frame's context
    /// only). Beside the key-handler count they say whether a scenario's
    /// registrations keep its rows out of the cache, which nothing else printed
    /// here can.
    @MainActor
    private static func printMemoTotals(
        _ cache: RenderCache?, channels: HeadlessInputChannels, frames: Int = 1
    ) {
        let memo = cache?.measureMemoTotals ?? (hits: 0, misses: 0)
        let lookups = memo.hits + memo.misses
        let memoRate: Double = lookups > 0 ? Double(memo.hits) / Double(lookups) * 100 : 0
        print("  measure memo: \(memo.hits) hits / \(lookups) lookups (\((memoRate).formatted(.fixed(1)))%)")
        let render = cache?.stats ?? RenderCache.Stats()
        print("  value memos (buffer + size): \(render.hits) hits / \(render.lookups) lookups, "
            + "\(render.stores) stores; handlers (last frame): \(channels.keyHandlerCount) key, "
            + "\(channels.mouseHandlerCount) mouse")
        // What the ROWS cost, which the line above cannot say: it sums the
        // buffer memo, the size memo and the row memo together, so a control
        // that composes every row from scratch and one that serves them all
        // look the same in it. Per frame, because the totals are cumulative
        // over the run and a per-frame number is the one worth comparing.
        let work = cache?.rowWork ?? RenderCache.RowWork()
        let divisor = Double(max(1, frames))
        let servedShare: Double =
            work.rendered + work.served > 0 ? Double(work.served) / Double(work.rendered + work.served) * 100 : 0
        print(
            "  rows/frame: \((Double(work.rendered) / divisor).formatted(.fixed(1))) composed, "
                + "\((Double(work.served) / divisor).formatted(.fixed(1))) served (\((servedShare).formatted(.fixed(0)))%), "
                + "\((Double(work.repainted) / divisor).formatted(.fixed(1))) of them repainted; "
                + "cell values/frame: \((Double(work.cellValues) / divisor).formatted(.fixed(1))); "
                + "bodies/frame: \((Double(work.bodies) / divisor).formatted(.fixed(1))); clears: \(render.clears) whole, "
                + "\(render.subtreeClears) subtree (\(render.clearVisits) entries visited)")
    }

    /// The scenario as `--bench` draws it: under `--stripes`, every table and
    /// list in it under one alternating-row behaviour — see
    /// `StressConfig.stripes`.
    @MainActor
    private static func benchView(_ scenario: some View, config: StressConfig) -> AnyView {
        config.stripes.map { AnyView(scenario.alternatingRowBackgrounds($0)) } ?? AnyView(scenario)
    }

    /// Renders one scenario `iterations` times and reports timing + a checksum
    /// (so the optimiser can't elide the loop). With `cold == true` a fresh
    /// state/cache is used each frame (worst-case measure+render); otherwise the
    /// cache stays warm across frames (steady state). The shared clock is bumped
    /// each frame so tick-driven scenarios (e.g. `churn`) actually churn.
    @MainActor
    static func bench(
        _ id: String,
        config: StressConfig,
        iterations: Int,
        cols: Int,
        rows: Int,
        cold: Bool,
        census countsObservation: Bool = false,
        frameChecksums: Bool = false,
        cacheSizesEvery: Int = 0
    ) -> Int {
        guard let scenario = Scenarios.byID(id) else {
            print("bench: unknown scenario '\(id)'. Known: \(Scenarios.all.map(\.id).joined(separator: ", "))")
            return 1
        }
        let clock = StressClock()
        let driven = scenario.drive?(config)
        let view = benchView((driven?.view ?? scenario.make(config)).environment(clock), config: config)

        // Warm up (build lazy state, prime caches) outside the timed region.
        let channels = HeadlessInputChannels()
        let valueHashPlans = ValueHashPlans.tui()
        var warm = makeContext(cols: cols, rows: rows, channels: channels, valueHashPlans: valueHashPlans)
        stampFrameDate(warm, date: frameChecksums ? checksumDate(tick: 0) : nil)
        _ = LargeStack.run { renderToBuffer(view, context: warm) }

        var tally = FrameTally()
        var blankFrames = 0
        let trimmedBefore = StackGuard.truncationCount
        // Accumulate only the render itself. Checking the frame is this
        // harness's own bookkeeping, and it is not cheap next to a cheap
        // scenario: measured at 6.0% of `dashboard`'s per-frame time against
        // 0.2% of `deep`'s. Timing it would tax the fast scenarios hardest and
        // show up as a regression that never happened.
        //
        // Timed twice, over the same region: the wall clock (what this always
        // reported) and the thread's CPU clock. Only the second is comparable
        // across runs on a machine that is doing anything else — see
        // ``threadCPUNanoseconds()``. The CPU reads bracket the wall reads so
        // the wall number still measures exactly the render.
        var ns: UInt64 = 0
        var cpuNs: UInt64 = 0
        var cpuMeasured = false
        // Resident size, sampled rather than integrated. Every 64th frame is
        // often enough to characterise a run that is thousands of frames long
        // and rare enough that the syscall does not land in the per-frame
        // number — and it is deliberately OUTSIDE the timed region, so the
        // CPU and wall figures still measure exactly the render.
        var memory = ProcessMemory.Samples()
        var memoCounts = MemoCounts()
        // `--census`: installed after the warm-up, so the loop is all it counts.
        let observation = BenchObservationCounter(
            requested: countsObservation, cold: cold, cache: warm.renderCache)
        let correctionsBefore = channels.geometryCorrections
        let settlingBefore = warm.stateStorage?.effectStage.settling
        for iteration in 0..<iterations {
            if iteration.isMultiple(of: 64) { memory.sample() }
            if cold {
                // Outside the timed region, as making its successor is: a cold
                // frame is one with nothing kept, and freeing what the last
                // one kept is not part of drawing this one.
                channels.discard(warm)
                warm = makeContext(cols: cols, rows: rows, channels: channels, valueHashPlans: valueHashPlans)
            }
            clock.tick &+= 1
            // A driven scenario's write, outside the timed region; what it
            // invalidates is paid in the frame, where an app pays it.
            driven?.advance(clock.tick)
            // The run loop's frame clock, for a scenario that asks for it
            // (``DrivenScenario/runsAnimationClock``): a tick a 1/60 s frame.
            if driven?.runsAnimationClock == true {
                warm.environment.animationFrame = AnimationFrame(
                    nowNanos: Int64(clock.tick) * 16_666_667, step: clock.tick / 3, canAnimate: true)
            }
            let countsBefore = MemoCounts(warm.renderCache)
            let cpuStart = threadCPUNanoseconds()
            let frameStart = MonotonicClock.nowNanoseconds
            // The live loop's per-pass lifecycle, timed as part of the frame
            // because it IS part of the frame: `RenderLoop` opens every pass
            // with these and closes it by pruning whatever the pass did not
            // mark alive. Without them this bench rendered into a cache that
            // was never pruned and a measure memo that was never emptied — so
            // an off-screen row's size was a hit here and a miss in the app,
            // and the per-pass measure memo grew by every miss forever (2,400
            // entries a frame on `kitchensink`; millions over a profile),
            // which put dictionary resizes in profiles of code that has none.
            // The key channels are emptied first, as `RenderLoop` empties them
            // before each walk, so every frame re-registers into empty ones.
            channels.beginWalk()
            warm.stateStorage?.beginRenderPass()
            warm.renderCache?.beginRenderPass()
            stampFrameDate(warm, date: frameChecksums ? checksumDate(tick: clock.tick) : nil)
            let buffer = renderFrame(view, context: warm, channels: channels, cols: cols, rows: rows)
            warm.stateStorage?.endRenderPass()
            warm.renderCache?.removeInactive()
            ns &+= MonotonicClock.nowNanoseconds - frameStart
            if let cpuStart, let cpuEnd = threadCPUNanoseconds() {
                cpuNs &+= cpuEnd &- cpuStart
                cpuMeasured = true
            }
            memoCounts.add(from: countsBefore, to: MemoCounts(warm.renderCache))
            let frameChecksum = contentChecksum(buffer)
            tally.add(frameChecksum)
            // Each frame's own, for `Tools/Profiling/frame_parity.py`: two builds
            // that must draw alike are compared frame by frame, and the sum above
            // can say only that some frame differs. And the tables, every so often.
            printAfterFrame(iteration, checksum: frameChecksums ? frameChecksum : nil, warm, cacheSizesEvery)
            if isBlank(buffer) { blankFrames += 1 }
        }
        let trimmed = StackGuard.truncationCount - trimmedBefore

        let totalMs = Double(ns) / 1_000_000
        let perFrameUs = Double(ns) / 1_000 / Double(max(1, iterations))
        print("bench scenario=\(id) scale=\(config.scale) size=\(cols)x\(rows) "
            + "iters=\(iterations) cold=\(cold)")
        print(
            "  total=\((totalMs).formatted(.fixed(1)))ms  per-frame=\((perFrameUs).formatted(.fixed(1)))µs  "
                + "(\((1_000_000 / max(0.001, perFrameUs)).formatted(.fixed(0))) fps-equiv)  checksum=\(tally.checksum)")
        if cpuMeasured {
            let cpuPerFrameUs = Double(cpuNs) / 1_000 / Double(max(1, iterations))
            let ofWall: Double = perFrameUs > 0 ? cpuPerFrameUs / perFrameUs * 100 : 0
            print("  cpu-per-frame=\((cpuPerFrameUs).formatted(.fixed(1)))µs  (\((ofWall).formatted(.fixed(1)))% of wall)")
        }
        memory.sample()
        printMemory(memory)
        printMemoTotals(warm.renderCache, channels: channels, frames: iterations)
        print(memoCounts.report(frames: iterations))
        printGeometryCorrections(
            from: correctionsBefore, to: channels.geometryCorrections, frames: iterations,
            always: id == GeometryScenario.descriptor.id)
        // How often the frames' effects wrote state, so a frame was walked
        // again before it was written (`FrameSettling`). A `--cold` frame has
        // a context of its own, so its count is its own frame's.
        if !cold, let before = settlingBefore, let after = warm.stateStorage?.effectStage.settling {
            print("  effects: \(after.delta(since: before))")
        }
        MemoCounts.printValueHashCensus(of: warm.renderCache)
        observation?.report(frames: iterations)
        // `TUI_VERIFY_MEASURE_MEMO=1` re-measures every memo hit and reports
        // any the fresh measurement disagrees with — the direct check on the
        // memo's cross-budget claim, run over whichever scenario is at hand.
        let mismatches = warm.renderCache?.measureMemoMismatches ?? []
        if !mismatches.isEmpty {
            print("  MEASURE MEMO MISMATCHES (\(mismatches.count)):")
            for line in mismatches { print("    \(line)") }
        }
        if let prune = warm.renderCache?.lastPruneSummary {
            print("  prune (last frame): \(prune)")
        }

        // A timing is only a measurement of the scenario if the scenario was
        // actually drawn. Reporting these as a failure rather than a note is
        // the point: this harness spent its Linux life timing an empty render
        // loop and exiting 0, so nothing downstream ever noticed.
        if blankFrames > 0 {
            print("  FAIL: \(blankFrames)/\(iterations) frames rendered nothing — "
                + "the timing above measures an empty loop, not \(id)")
        }
        if trimmed > 0 {
            // Worth failing loudly rather than noting: truncation makes the
            // render *faster*, so it reads as a good result. Measured here —
            // `deep` at scale 200 on a 512 KB stack came back in 4.9 ms/frame
            // against 2317 ms/frame for the same scenario on 8 MB.
            print("  FAIL: the stack guard stopped \(trimmed) descents — the tree was cut "
                + "short, so this is not a profile of \(id) at scale \(config.scale). "
                + "Raise the stack (ulimit -s) or lower --scale.")
        }
        // First, so it is asked (and prints) whatever else failed.
        return stoodStill(id, config: config, frames: iterations, tally: tally) || blankFrames > 0 || trimmed > 0 ? 1 : 0
    }

    /// What `--bench` keeps of its frames' checksums: their sum, printed so
    /// the optimiser cannot elide the loop, and whether any differed from the
    /// first.
    struct FrameTally {
        private(set) var checksum = 0
        private(set) var moved = false
        private var first: Int?

        mutating func add(_ frame: Int) {
            checksum = checksum &+ frame
            if let first { moved = moved || frame != first } else { first = frame }
        }
    }

    /// Whether `id` scrolls every tick (``ScenarioVariant/scrolls``) and yet
    /// drew one frame throughout, printing why that fails the run: its timing
    /// is its first frame redrawn. SCROLL-FIT's pulled pages did so, unnoticed,
    /// for three lanes (a bound `ScrollPosition` acted on once).
    @MainActor
    private static func stoodStill(_ id: String, config: StressConfig, frames: Int, tally: FrameTally) -> Bool {
        guard frames > 1, !tally.moved, !ScenarioVariants.variants(of: id).isEmpty,
            ScenarioVariants.resolve(config, in: id)?.scrolls == true
        else { return false }
        print("  FAIL: every frame drew the same page — \(id) scrolls every tick, so the timing above "
            + "measures its first frame redrawn, not scrolling")
        return true
    }
}

/// One line of what a run observed and what the observation leases did, per
/// `unit` (a frame, a step): registrations armed, fired, cancelled and alive
/// at the end, over every kind of reader; the lease bookkeeping —
/// computations opened, leases made, kept results used, scopes that read a
/// sentinel; and how many view types the cache knows to read. What
/// `Stress --bench --census` and `--session --census` print.
func observationCountsLine(
    _ counts: ObservationCensus.Counts, leases: ObservationLeases.Counts, since start: ObservationLeases.Counts,
    readingTypes: Int, per units: Int, unit: String
) -> String {
    let each = Double(max(1, units))
    let kinds = ObservationCensus.Kind.allCases
    let armed = kinds.reduce(0) { $0 + counts.armed($1) }
    let fired = kinds.reduce(0) { $0 + counts.fired($1) }
    let cancelled = kinds.reduce(0) { $0 + counts.cancelled($1) }
    let per = { (count: Int) in (Double(count) / each).formatted(.fixed(2)) }
    return "observation per \(unit): armed \(per(armed)), fired \(per(fired)), cancelled \(per(cancelled)) "
        + "(alive at the end \(counts.live)); leases per \(unit): "
        + "computations \(per(leases.computations - start.computations)), "
        + "made \(per(leases.leasesMade - start.leasesMade)), uses \(per(leases.uses - start.uses)), "
        + "sentinel scopes \(per(leases.sentinelScopes - start.sentinelScopes)); reading types \(readingTypes)"
}

/// What `Stress --bench --census` counts over the timed loop: the
/// observation registrations the frames armed, fired and cancelled, and what
/// the observation leases did to decide when each may go — counts, not
/// times, so two builds compare on any machine.
///
/// `nil` unless asked for, and for a `--cold` run, whose cache is replaced
/// every frame.
@MainActor
private struct BenchObservationCounter {
    private let cache: RenderCache
    private let census = ObservationCensus()
    private let leasesBefore: ObservationLeases.Counts

    init?(requested: Bool, cold: Bool, cache: RenderCache?) {
        guard requested, !cold, let cache else { return nil }
        self.cache = cache
        leasesBefore = cache.leases.counts
        cache.observationCensus = census
    }

    /// Prints the line, per frame of `frames`.
    func report(frames: Int) {
        print(
            "  " + observationCountsLine(
                census.snapshot, leases: cache.leases.counts, since: leasesBefore,
                readingTypes: cache.readingTypes.count, per: frames, unit: "frame"))
    }
}
