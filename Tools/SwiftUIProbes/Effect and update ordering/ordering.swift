// Probe (2026-10-24): when SwiftUI runs view effects — onAppear, onChange(of:),
// onPreferenceChange, onGeometryChange(for:of:action:), onScrollGeometryChange,
// .task — relative to body evaluation, layout, rendering and the frame that
// reaches the screen.
//
// One case a process, in an on-screen borderless window (a display link needs a
// screen). run.sh builds this file and runs every case, writing <case>.out:
//   xcrun swiftc -target arm64-apple-macos15.0 ordering.swift -o "$TMPDIR/ordering"
//   PROBE_STACKS=1 OS_ACTIVITY_DT_MODE=YES "$TMPDIR/ordering" appear 2>&1
// Cases: appear change chain selfloop prefloop geofeedback geocount geoscroll
// geolist bodywrite (see `cases` at the bottom).
//
// Every line is one event, numbered in the order it happened:
//   seq  f<display-link callbacks so far>  ms-since-start  event  [context]
// The context says what the event ran inside: the NSHostingView subclass's
// layout() or updateConstraints(), a body (traced(_:_:) below), a custom
// Layout's sizeThatFits/placeSubviews, or the layer-tree capture.
// Events come from:
//   body …               a body evaluation (traced at the top of the body)
//   Layout[…]            TraceLayout.sizeThatFits / placeSubviews
//   (GeometryReader …)   a GeometryReader's content closure
//   DRAW …               a Canvas renderer: SwiftUI drawing that view's content
//   host.*               NSHostingView overrides (updateConstraints, layout,
//                        needsLayout set to true, viewWillDraw)
//   runloop: …           main run-loop observers at the lowest and highest
//                        order of every activity, so that AppKit's, Core
//                        Animation's and SwiftUI's own observers run between
//                        "… observers begin" and "… observers done"; a line is
//                        printed only for an activity in which something happened
//   CA post-commit …     a Core Animation post-commit handler, armed from the
//                        host's layout(): the transaction holding what was just
//                        drawn has been committed to the render server
//   committed layer tree the colour of a few pixels of the host's sublayers,
//                        rendered (CALayer.render(in:)) right after that commit
//   ── vsync f<n>        the host's CADisplayLink fired; runs of callbacks with no
//                        event between are collapsed. A callback cannot run while
//                        the main thread is busy, so f counts callbacks, not vsyncs
//   stack of …           (PROBE_STACKS) the stack that led to an event, once each
import AppKit
import Observation
import QuartzCore
import SwiftUI

// MARK: - The log

var seq = 0
var frameCount = 0
var t0 = CACurrentMediaTime()
var inHostLayout = 0
var inHostConstraints = 0
var inBody = 0
var inLayoutProtocol = 0
var capturing = false
var eventsSinceVsync = 0
var idleVsyncs = 0
var stopAfterMs = 1500.0

func log(_ text: String) {
    if let activity = pendingActivity {
        pendingActivity = nil
        emit("runloop: " + (activity.hasPrefix("after ") ? activity : activity + " observers begin"))
    }
    emit(text)
}

func emit(_ text: String) {
    eventsInActivity += 1
    seq += 1
    eventsSinceVsync += 1
    var context: [String] = []
    if inHostConstraints > 0 { context.append("in host.updateConstraints") }
    if inHostLayout > 0 { context.append("in host.layout") }
    if inBody > 0 { context.append("in a body") }
    if inLayoutProtocol > 0 { context.append("in Layout") }
    if capturing { context.append("in capture") }
    if !Thread.isMainThread { context.append("OFF MAIN THREAD") }
    let head = String(format: "%4d f%-3d %7.1f  ", seq, frameCount, (CACurrentMediaTime() - t0) * 1000)
    fputs(head + text + (context.isEmpty ? "" : "   [" + context.joined(separator: ", ") + "]") + "\n", stderr)
}

var stacksLogged: Set<String> = []
/// Prints, once per name, the frames of the current stack that are not the probe's own or the Swift runtime's: what
/// drove the call. SwiftUI's internal functions have no exported symbols, so a SwiftUI frame prints as the nearest
/// exported symbol before it, which names the right neighbourhood at best; AppKit's and Core Animation's are exact.
func logStackOnce(_ name: String) {
    guard ProcessInfo.processInfo.environment["PROBE_STACKS"] != nil, stacksLogged.insert(name).inserted else { return }
    let frames = Thread.callStackSymbols.dropFirst(2).compactMap { line -> String? in
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 4 else { return nil }
        let module = String(parts[1])
        guard ["AppKit", "QuartzCore", "CoreFoundation", "HIToolbox", "libdispatch.dylib", "SwiftUI", "SwiftUICore",
               "AttributeGraph"].contains(module) else { return nil }
        return module + " " + parts[3...].prefix(while: { $0 != "+" }).joined(separator: " ")
    }
    fputs("          stack of \(name): " + frames.filter { !$0.contains("NSPerformVisuallyAtomicChange") && !$0.contains("_block_invoke") }.prefix(22).joined(separator: " <- ") + "\n", stderr)
}

/// Runs a body's content between two marks, so that anything nested in it says "in a body".
func traced<V: View>(_ name: @autoclosure () -> String, @ViewBuilder _ make: () -> V) -> V {
    log("body " + name())
    if inHostLayout == 0 && inHostConstraints == 0 {
        logStackOnce("a body outside host.layout, " + (currentActivity.map { "in the \($0) observers" } ?? "outside run-loop observers"))
    }
    inBody += 1
    defer { inBody -= 1 }
    return make()
}

func fmt(_ size: CGSize) -> String { "\(fmt(size.width))x\(fmt(size.height))" }
func fmt(_ value: CGFloat) -> String {
    if !value.isFinite { return value > 0 ? "inf" : "-inf" }
    return value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
}
func fmt(_ value: CGFloat?) -> String { value.map { fmt($0) } ?? "nil" }
func fmt(_ proposal: ProposedViewSize) -> String { "\(fmt(proposal.width))x\(fmt(proposal.height))" }

// MARK: - Hooks

final class ProbeHost: NSHostingView<AnyView> {
    override func updateConstraints() {
        log("host.updateConstraints begin")
        inHostConstraints += 1
        super.updateConstraints()
        inHostConstraints -= 1
        log("host.updateConstraints end")
    }
    override func layout() {
        log("host.layout begin")
        logStackOnce("host.layout")
        inHostLayout += 1
        super.layout()
        inHostLayout -= 1
        log("host.layout end")
        armCommitHandler("host.layout")
    }
    override var needsLayout: Bool {
        didSet { if needsLayout && !oldValue { log("host.needsLayout = true") } }
    }
    override func viewWillDraw() {
        log("host.viewWillDraw")
        logStackOnce("host.viewWillDraw")
        super.viewWillDraw()
        armCommitHandler("host.viewWillDraw")
    }
}

final class Ticker: NSObject {
    @objc func tick(_ link: CADisplayLink) {
        frameCount += 1
        if eventsSinceVsync > 0 {
            if idleVsyncs > 0 { fputs("          (\(idleVsyncs) vsyncs with no event)\n", stderr) }
            idleVsyncs = 0
            log("── vsync f\(frameCount)")
            eventsSinceVsync = 0
        } else {
            idleVsyncs += 1
        }
    }
}

/// Points sampled after each commit, as (name, x, y) in the host's flipped coordinates.
var samplePoints: [(String, Int, Int)] = [("pixel", 4, 4)]

func colourName(_ colour: NSColor?) -> String {
    guard let c = colour?.usingColorSpace(.sRGB) else { return "none" }
    let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
    if c.alphaComponent < 0.5 { return "clear" }
    if r > 0.7 && g < 0.4 && b < 0.4 { return "RED" }
    if g > 0.5 && r < 0.4 && b < 0.5 { return "GREEN" }
    if b > 0.7 && r < 0.4 { return "BLUE" }
    return String(format: "rgb(%.2f,%.2f,%.2f)", r, g, b)
}

/// Renders the host's layer tree as it stands — the model layers, which after a commit are what the render
/// server has — into a bitmap, without asking any view to lay out or draw (cacheDisplay would: it runs
/// host.layout(), so it is not used).
@MainActor func sample(_ host: NSView) -> String {
    capturing = true
    defer { capturing = false }
    guard let layer = host.layer else { return "no layer" }
    let width = Int(host.bounds.width), height = Int(host.bounds.height)
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return "no context" }
    // The host's own layer is left out: rendering it asks the host to display (viewWillDraw). Its sublayers
    // hold SwiftUI's drawing.
    for sublayer in layer.sublayers ?? [] {
        context.saveGState()
        context.translateBy(x: sublayer.frame.minX, y: sublayer.frame.minY)
        sublayer.render(in: context)
        context.restoreGState()
    }
    guard let data = context.data else { return "no data" }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    if let row = sampleRedEdgeRow {
        let edge = (0..<width).first { x in
            let o = (row * width + x) * 4
            return bytes[o] > 180 && bytes[o + 1] < 100 && bytes[o + 3] > 128
        }
        return "red begins at x=" + (edge.map(String.init) ?? "none")
    }
    return samplePoints.map { name, x, y in
        // Every point sampled is mid-height or a uniform fill, so whether row 0 is the top does not matter.
        let offset = (y * width + x) * 4
        let colour = NSColor(srgbRed: CGFloat(bytes[offset]) / 255, green: CGFloat(bytes[offset + 1]) / 255,
                             blue: CGFloat(bytes[offset + 2]) / 255, alpha: CGFloat(bytes[offset + 3]) / 255)
        return "\(name)=\(colourName(colour))"
    }.joined(separator: " ")
}

var hostForSampling: NSView?
/// For geofeedback: the row on which the sample reports where the red sibling begins.
var sampleRedEdgeRow: Int?

func activityName(_ activity: CFRunLoopActivity) -> String {
    switch activity {
    case .entry: "entry"
    case .beforeTimers: "beforeTimers"
    case .beforeSources: "beforeSources"
    case .beforeWaiting: "beforeWaiting"
    case .afterWaiting: "afterWaiting"
    case .exit: "exit"
    default: "activity \(activity.rawValue)"
    }
}

/// Two observers of every main run-loop activity, one first (order CFIndex.min) and one last (CFIndex.max), so that
/// the observers AppKit and Core Animation run (the display cycle, the implicit transaction's commit) run between
/// them. The first only notes the activity; the line is printed before the next event, so that an idle activity
/// prints nothing. The last prints a line, and samples the layer tree, when something was logged since the first.
var pendingActivity: String?
/// The run-loop activity whose observers are running, if any (set by the first observer, cleared by the last).
var currentActivity: String?

/// What CFRunLoop does after an activity's observers, when it is not more observers.
func follows(_ activity: CFRunLoopActivity) -> String? {
    switch activity {
    case .beforeSources: "after beforeSources: CFRunLoop blocks, version-0 sources, and main-queue work already waiting"
    case .afterWaiting: "after afterWaiting: the timer, main-queue work or port that woke the loop"
    default: nil
    }
}
var eventsInActivity = 0

@MainActor func installObservers() {
    let all = CFRunLoopActivity.allActivities.rawValue
    let first = CFRunLoopObserverCreateWithHandler(nil, all, true, CFIndex.min) { _, activity in
        pendingActivity = activityName(activity)
        currentActivity = activityName(activity)
        eventsInActivity = 0
    }
    let last = CFRunLoopObserverCreateWithHandler(nil, all, true, CFIndex.max) { _, activity in
        currentActivity = nil
        pendingActivity = follows(activity)
        guard eventsInActivity > 0 else { return }
        log("runloop: \(activityName(activity)) observers done")
        eventsInActivity = 0
        pendingActivity = follows(activity)
    }
    CFRunLoopAddObserver(CFRunLoopGetMain(), first, .commonModes)
    CFRunLoopAddObserver(CFRunLoopGetMain(), last, .commonModes)
}

/// Core Animation's commit handlers (SPI: +[CATransaction addCommitHandler:forPhase:], the hook AppKit's display
/// cycle itself uses). Registered from the host's layout and draw hooks, a post-commit handler says when the
/// transaction that carries what was just laid out has been committed to the render server.
let commitPhasePostCommit: Int32 = 2
var commitHandlerArmed = false
func armCommitHandler(_ reason: String) {
    guard !commitHandlerArmed else { return }
    let selector = NSSelectorFromString("addCommitHandler:forPhase:")
    guard let method = class_getClassMethod(CATransaction.self, selector) else { return }
    typealias Fn = @convention(c) (AnyClass, Selector, @escaping @convention(block) () -> Void, Int32) -> Void
    let call = unsafeBitCast(method_getImplementation(method), to: Fn.self)
    commitHandlerArmed = true
    call(CATransaction.self, selector, {
        commitHandlerArmed = false
        log("CA post-commit handler: the transaction is committed (armed by \(reason))")
        MainActor.assumeIsolated { if let host = hostForSampling { log("  committed layer tree: " + sample(host)) } }
    }, commitPhasePostCommit)
}

// MARK: - Views shared by the cases

struct TraceLayout: Layout {
    var name: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        inLayoutProtocol += 1
        defer { inLayoutProtocol -= 1 }
        log("Layout[\(name)].sizeThatFits proposal=\(fmt(proposal)) begin")
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        let size = CGSize(width: proposal.width ?? sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).reduce(0, +))
        log("Layout[\(name)].sizeThatFits -> \(fmt(size))")
        return size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        inLayoutProtocol += 1
        defer { inLayoutProtocol -= 1 }
        log("Layout[\(name)].placeSubviews bounds=\(fmt(bounds.size))")
        var y = bounds.minY
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: size.height))
            y += size.height
        }
    }
}

/// A Canvas whose renderer logs: it runs when SwiftUI renders this view's content.
struct Marker: View {
    let label: String
    var body: some View {
        Canvas { _, size in log("DRAW \(label) (canvas \(fmt(size)))") }
            .frame(width: 8, height: 8)
    }
}

struct IntKey: PreferenceKey {
    static let defaultValue = -1
    static func reduce(value: inout Int, nextValue: () -> Int) { value = max(value, nextValue()) }
}

// MARK: - Case appear: one view with every effect; onAppear writes the state the body draws

struct AppearChild: View {
    let loaded: Bool
    var body: some View {
        traced("AppearChild loaded=\(loaded)") {
            Text(loaded ? "loaded" : "loading")
                .onAppear { log("AppearChild.onAppear") }
                .preference(key: IntKey.self, value: loaded ? 1 : 0)
        }
    }
}

struct AppearRoot: View {
    @State var loaded = false
    var body: some View {
        traced("AppearRoot loaded=\(loaded)") {
            TraceLayout(name: "outer") {
                AppearChild(loaded: loaded)
                GeometryReader { proxy in
                    traced("(GeometryReader content) size=\(fmt(proxy.size))") {
                        Marker(label: "loaded=\(loaded)")
                    }
                }
                .frame(height: 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(loaded ? Color.green : Color.red)
            .onGeometryChange(for: CGSize.self) { proxy in
                log("onGeometryChange of: size=\(fmt(proxy.size))")
                return proxy.size
            } action: { size in
                log("onGeometryChange action: \(fmt(size))")
            }
            .onPreferenceChange(IntKey.self) { value in log("onPreferenceChange \(value)") }
            .onAppear {
                log("onAppear (loaded=\(loaded)) -> loaded = true")
                logStackOnce("onAppear")
                loaded = true
            }
            .onChange(of: loaded) { old, new in log("onChange(loaded) \(old) -> \(new)") }
            .task {
                log("task starts: main thread=\(pthread_main_np() != 0) isolation=\(String(describing: #isolation)) priority=\(Task.currentPriority)")
                await Task.yield()
                log("task after Task.yield()")
                try? await Task.sleep(for: .milliseconds(1))
                log("task after Task.sleep(1 ms)")
            }
            .task(priority: .background) {
                log("task(priority: .background) starts: main thread=\(pthread_main_np() != 0) isolation=\(String(describing: #isolation))")
            }
        }
    }
}

// MARK: - Case change: a write from outside; onChange (left) and onPreferenceChange (right) write the drawn state

@Observable final class Driver {
    var flag = false
    var prefFlag = false
}
let driver = Driver()

struct PrefSource: View {
    let driver: Driver
    var body: some View {
        traced("PrefSource prefFlag=\(driver.prefFlag)") {
            Color.clear.preference(key: IntKey.self, value: driver.prefFlag ? 1 : 0)
        }
    }
}

struct ChangeRoot: View {
    let driver: Driver
    @State var phase = "A"
    @State var fromPreference = 0
    var body: some View {
        traced("ChangeRoot flag=\(driver.flag) phase=\(phase) fromPreference=\(fromPreference)") {
            HStack(spacing: 0) {
                (phase == "B" ? Color.green : Color.red)
                    .overlay(Marker(label: "left phase=\(phase)"))
                (fromPreference == 1 ? Color.green : Color.red)
                    .overlay(Marker(label: "right fromPreference=\(fromPreference)"))
                    .background(PrefSource(driver: driver))
            }
            .onChange(of: driver.flag) { _, new in
                log("onChange(flag) -> \(new): phase = B")
                logStackOnce("onChange(flag)")
                phase = "B"
            }
            .onPreferenceChange(IntKey.self) { value in
                log("onPreferenceChange \(value): fromPreference = \(value)")
                MainActor.assumeIsolated { fromPreference = value }
            }
        }
    }
}

// MARK: - Case chain: onAppear sets s[0]; onChange(s[i]) sets s[i+1], through 100 distinct onChange modifiers

struct ChainStep: View {
    let index: Int
    @Binding var values: [Int]
    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .onChange(of: values[index]) {
                log("onChange(s[\(index)]) -> s[\(index + 1)] = 1")
                if index + 1 < values.count { values[index + 1] = 1 }
            }
    }
}

struct ChainRoot: View {
    @State var values = Array(repeating: 0, count: 100)
    var body: some View {
        traced("ChainRoot ones=\(values.reduce(0, +))") {
            VStack(spacing: 0) {
                ForEach(0..<values.count, id: \.self) { ChainStep(index: $0, values: $values) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(values.last == 1 ? Color.green : Color.red)
            .overlay(Marker(label: "last=\(values.last!)"))
            .onAppear {
                log("onAppear -> s[0] = 1")
                values[0] = 1
            }
        }
    }
}

// MARK: - Case selfloop: one onChange(of: x) that increments x, up to 200

struct SelfLoopRoot: View {
    let driver: Driver
    @State var x = 0
    var body: some View {
        traced("SelfLoopRoot x=\(x)") {
            Color.red
                .overlay(Marker(label: "x=\(x)"))
                .onChange(of: x) { old, new in
                    log("onChange(x) saw \(old) -> \(new)" + (new < 200 ? " -> x = \(new + 1)" : ", stops"))
                    if new < 200 { x = new + 1 }
                }
                .onAppear {
                    log("onAppear -> x = 1")
                    x = 1
                }
                .onChange(of: driver.flag) {
                    log("onChange(flag): x = 100")
                    x = 100
                }
        }
    }
}

// MARK: - Case prefloop: onPreferenceChange writes the state the preference is made from, up to 200

struct PrefLoopRoot: View {
    @State var n = 0
    var body: some View {
        traced("PrefLoopRoot n=\(n)") {
            Color.red
                .overlay(Marker(label: "n=\(n)"))
                .preference(key: IntKey.self, value: n)
                .onPreferenceChange(IntKey.self) { value in
                    log("onPreferenceChange \(value)" + (value < 200 ? " -> n = \(value + 1)" : ", stops"))
                    MainActor.assumeIsolated { if value < 200 { n = value + 1 } }
                }
        }
    }
}

// MARK: - Case geofeedback: a reader's width feeds, through onGeometryChange and @State, the width beside it

struct GeoFeedbackRoot: View {
    @State var readerWidth: CGFloat = 0
    var body: some View {
        traced("GeoFeedbackRoot readerWidth=\(fmt(readerWidth))") {
            HStack(spacing: 0) {
                GeometryReader { proxy in
                    traced("(GeometryReader content) size=\(fmt(proxy.size))") {
                        Color.blue.frame(width: proxy.size.width / 2, height: proxy.size.width / 4)
                            .overlay(Marker(label: "reader content for \(fmt(proxy.size))"))
                    }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    log("onGeometryChange of: width=\(proxy.size.width)")
                    return proxy.size.width
                } action: { width in
                    log("onGeometryChange action: \(width) -> readerWidth")
                    readerWidth = width
                }
                Color.red.frame(width: readerWidth / 2)
            }
            .frame(width: 400, height: 300)
        }
    }
}

// MARK: - Case geocount: an onGeometryChange action that changes the geometry it reads, to a new value every time

struct GeoCountRoot: View {
    @State var sibling: CGFloat = 0
    var body: some View {
        traced("GeoCountRoot sibling=\(fmt(sibling))") {
            HStack(spacing: 0) {
                Color.blue
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        log("onGeometryChange action: \(fmt(width))" + (sibling < 300 ? " -> sibling = \(fmt(sibling + 1))" : ", stops"))
                        if sibling < 300 { sibling += 1 }
                    }
                Color.red.frame(width: sibling)
            }
            .frame(width: 400, height: 300)
        }
    }
}

// MARK: - Case geoscroll: a reader in a ScrollView, with onScrollGeometryChange

struct GeoScrollRoot: View {
    var body: some View {
        traced("GeoScrollRoot") {
            ScrollView {
                VStack(spacing: 0) {
                    GeometryReader { proxy in
                        traced("(GeometryReader content, in ScrollView) size=\(fmt(proxy.size))") {
                            Color.blue.frame(height: proxy.size.width / 4)
                                .overlay(Marker(label: "scroll reader for \(fmt(proxy.size))"))
                        }
                    }
                    ForEach(0..<20, id: \.self) { Text("row \($0)").frame(height: 20) }
                }
            }
            .onScrollGeometryChange(for: CGSize.self) { geometry in
                log("onScrollGeometryChange of: contentSize=\(fmt(geometry.contentSize)) container=\(fmt(geometry.containerSize))")
                return geometry.contentSize
            } action: { old, new in
                log("onScrollGeometryChange action: \(fmt(old)) -> \(fmt(new))")
            }
            .onAppear { log("ScrollView onAppear") }
        }
    }
}

// MARK: - Case geolist: readers in List rows, alone and as a background

struct GeoListRoot: View {
    var body: some View {
        traced("GeoListRoot") {
            List {
                GeometryReader { proxy in
                    traced("(GeometryReader content, a List row alone) size=\(fmt(proxy.size))") {
                        Marker(label: "list row reader for \(fmt(proxy.size))")
                    }
                }
                Text("a row with a reader behind")
                    .background(GeometryReader { proxy in
                        traced("(GeometryReader content, behind a List row's text) size=\(fmt(proxy.size))") {
                            Color.clear
                        }
                    })
                    .onGeometryChange(for: CGSize.self) { proxy in
                        log("List row onGeometryChange of: \(fmt(proxy.size))")
                        return proxy.size
                    } action: { log("List row onGeometryChange action: \(fmt($0))") }
                    .onAppear {
                        log("List row onAppear")
                        logStackOnce("List row onAppear")
                    }
            }
        }
    }
}

// MARK: - Case bodywrite: a body writes @State, in its first evaluation and again in one after an outside write

var bodyWrites = 0

struct BodyWriteRoot: View {
    let driver: Driver
    @State var n = 0
    var body: some View {
        traced("BodyWriteRoot n=\(n) flag=\(driver.flag) prefFlag=\(driver.prefFlag)") {
            let _ = {
                if bodyWrites == 0 || (bodyWrites == 1 && driver.flag) {
                    bodyWrites += 1
                    log("body writes n = \(bodyWrites)")
                    n = bodyWrites
                    log("body after the write reads n=\(n)")
                }
            }()
            (n >= 1 ? Color.green : Color.red)
                .overlay(Marker(label: "n=\(n)"))
                .onChange(of: n) { old, new in log("onChange(n) \(old) -> \(new)") }
        }
    }
}

// MARK: - Running a case

let cases: [String: (String, () -> AnyView)] = [
    "appear": ("one view with every effect; onAppear sets loaded = true", { AnyView(AppearRoot()) }),
    "change": ("an outside write; onChange and onPreferenceChange write the drawn state", { AnyView(ChangeRoot(driver: driver)) }),
    "chain": ("100 onChange modifiers, each setting the next one's value", { AnyView(ChainRoot()) }),
    "selfloop": ("onChange(of: x) sets x + 1, to 200; at 0.5 s an outside write leads to x = 100", { AnyView(SelfLoopRoot(driver: driver)) }),
    "prefloop": ("onPreferenceChange sets the value its preference is made from, + 1, to 200", { AnyView(PrefLoopRoot()) }),
    "geofeedback": ("a reader's width, through onGeometryChange and @State, sets its sibling's width", { AnyView(GeoFeedbackRoot()) }),
    "geocount": ("an onGeometryChange action widens the sibling by 1 each time, to 300: every value new", { AnyView(GeoCountRoot()) }),
    "geoscroll": ("a GeometryReader in a ScrollView, and onScrollGeometryChange", { AnyView(GeoScrollRoot()) }),
    "geolist": ("GeometryReaders in List rows", { AnyView(GeoListRoot()) }),
    "bodywrite": ("a body writes @State; at 0.5 s an outside write re-runs the body, which writes again; at 1 s another re-runs it to read n", { AnyView(BodyWriteRoot(driver: driver)) }),
]

let name = CommandLine.arguments.dropFirst().first ?? "appear"
guard let (summary, make) = cases[name] else {
    fputs("cases: \(cases.keys.sorted().joined(separator: " "))\n", stderr)
    exit(2)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    if name == "change" { samplePoints = [("left", 50, 100), ("right", 350, 100)] }
    if name == "geofeedback" { sampleRedEdgeRow = 150 }
    DispatchQueue.main.async {
        fputs("case \(name): \(summary)\n", stderr)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        installObservers()
        t0 = CACurrentMediaTime()
        log("making the NSHostingView")
        let host = ProbeHost(rootView: make())
        log("NSHostingView made; setting the window's contentView")
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        window.contentView = host
        hostForSampling = host
        let ticker = Ticker()
        host.displayLink(target: ticker, selector: #selector(Ticker.tick(_:))).add(to: .main, forMode: .common)
        log("ordering the window front")
        window.orderFrontRegardless()
        log("window ordered front; the turn that made it ends next")
        if ["selfloop", "bodywrite"].contains(name) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                log("TRIGGER: driver.flag = true (outside any update)")
                driver.flag = true
            }
        }
        if name == "bodywrite" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                log("TRIGGER: driver.prefFlag = true (outside any update; the body reads it, and n)")
                driver.prefFlag = true
            }
        }
        if name == "change" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                log("TRIGGER 1: driver.flag = true (outside any update)")
                driver.flag = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                log("TRIGGER 2: driver.prefFlag = true (outside any update)")
                driver.prefFlag = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + stopAfterMs / 1000) {
            if idleVsyncs > 0 { fputs("          (\(idleVsyncs) vsyncs with no event)\n", stderr) }
            fputs("end of case \(name)\n", stderr)
            withExtendedLifetime((window, ticker)) { exit(0) }
        }
    }
    app.run()
}
