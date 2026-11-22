//  🖥️ TUI — A Terminal UI framework for Swift
//  AnyViewStateLifetimeTests.swift
//
//  An `AnyView` whose erased type changes starts its new content's state
//  afresh, as SwiftUI's does; the same type wrapped again keeps it.
//
//  An `AnyView` draws its content at its own identity, and a view's `@State`
//  is kept at its identity by declaration index, with no type in the key: a
//  screen erased one frame and another the next found the first one's boxes.
//  Text typed in one step of a wizard showed in the next (VIEWS-2, H-08).
//
//  Measured on macOS 15.8.3, `Tools/SwiftUIProbes/AnyView type swap (H-08)/anyview.out`:
//  a swap to another type, back again, or to the first type inside another
//  (`A().padding(1)`) is a new view with new state; the same type in a new
//  `AnyView` keeps its state.
//
//  And what goes is only what the content made: a procedural core that draws
//  several erased views in turn at its own identity, as the search field
//  draws its suggestions' labels, keeps its own slots there across frames and
//  across its labels changing. (The first version dropped every declaration-
//  order value at the identity, and the field's suggestions menu never stayed
//  open: `SearchTokensTests`.)
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport
@testable import TUIView

/// What the views below leave behind for the test to read and write.
@MainActor
private final class Handles {
    var which: Binding<Int>?
    var tick: Binding<Int>?
    var writers: [String: (String) -> Void] = [:]
}

/// A view whose first `@State` is a string the test writes.
private struct ScreenA: View {
    @State private var text = ""
    let handles: Handles
    var body: some View {
        handles.writers["A"] = { text = $0 }
        return Text(verbatim: "A[\(text)]")
    }
}

/// The same state layout as ``ScreenA``, another type.
private struct ScreenB: View {
    @State private var text = ""
    let handles: Handles
    var body: some View {
        handles.writers["B"] = { text = $0 }
        return Text(verbatim: "B[\(text)]")
    }
}

/// A view a step down: its state lives below the `AnyView`'s identity, in a
/// body of the same type as ``ScreenD``'s.
private struct ScreenC: View {
    let handles: Handles
    var body: some View {
        HStack { Field(name: "C", handles: handles) }
    }
}

/// ``ScreenC`` under another name.
private struct ScreenD: View {
    let handles: Handles
    var body: some View {
        HStack { Field(name: "D", handles: handles) }
    }
}

private struct Field: View {
    let name: String
    let handles: Handles
    @State private var text = ""
    var body: some View {
        handles.writers[name] = { text = $0 }
        return Text(verbatim: "\(name)[\(text)]")
    }
}

/// The erased screen, chosen by `which`, beside a marker whose column says
/// how wide the screen was laid out.
private struct Swapper: View {
    @State private var which = 0
    @State private var tick = 0
    let handles: Handles

    var body: some View {
        handles.which = $which
        handles.tick = $tick
        return HStack(spacing: 0) {
            screen()
            Text(verbatim: "|\(tick)")
        }
    }

    private func screen() -> AnyView {
        switch which {
        case 0: AnyView(ScreenA(handles: handles))
        case 1: AnyView(ScreenB(handles: handles))
        case 2: AnyView(ScreenC(handles: handles))
        case 3: AnyView(ScreenD(handles: handles))
        default: AnyView(ScreenA(handles: handles).padding(.leading, 1))
        }
    }
}

@MainActor
@Suite("An AnyView's content keeps its state only while its type stays")
struct AnyViewStateLifetimeTests {
    private func app(_ handles: Handles) -> TestApp {
        TestApp(width: 40, height: 4) { Swapper(handles: handles) }
    }

    /// The screen's line with the marker on it; reading the screen draws the
    /// frames the writes asked for.
    private func line(_ app: TestApp) -> String {
        app.screen.line(containing: "|") ?? "\(app.screen)"
    }

    private func show(_ which: Int, _ handles: Handles, _ app: TestApp) {
        _ = app.screen
        handles.which?.wrappedValue = which
        _ = app.screen
    }

    private func write(_ name: String, _ text: String, _ handles: Handles, _ app: TestApp) {
        _ = app.screen
        handles.writers[name]?(text)
        _ = app.screen
    }

    @Test("The same type wrapped again keeps its state")
    func sameTypeKeepsState() {
        let handles = Handles()
        let app = app(handles)
        write("A", "Ann", handles, app)
        #expect(line(app).hasPrefix("A[Ann]|"), "precondition: \(line(app))")
        handles.tick?.wrappedValue += 1
        #expect(line(app).hasPrefix("A[Ann]|1"), "\(line(app))")
    }

    @Test("A swap to another type starts afresh, and so does the swap back")
    func swapStartsAfresh() {
        let handles = Handles()
        let app = app(handles)
        write("A", "Ann", handles, app)
        show(1, handles, app)
        #expect(line(app).hasPrefix("B[]|"), "B was handed A's state: \(line(app))")
        write("B", "Bo", handles, app)
        #expect(line(app).hasPrefix("B[Bo]|"), "precondition: \(line(app))")
        show(0, handles, app)
        #expect(line(app).hasPrefix("A[]|"), "A came back with old state: \(line(app))")
    }

    @Test("A swap drops the state below the AnyView's identity too")
    func swapDropsStateBelow() {
        let handles = Handles()
        let app = app(handles)
        show(2, handles, app)
        write("C", "Cy", handles, app)
        #expect(line(app).contains("C[Cy]"), "precondition: \(line(app))")
        show(3, handles, app)
        #expect(line(app).contains("D[]"), "D was handed C's state: \(line(app))")
        show(2, handles, app)
        #expect(line(app).contains("C[]"), "C came back with old state: \(line(app))")
    }

    @Test("The first type inside another is another type")
    func wrappedInAModifierIsAnotherType() {
        let handles = Handles()
        let app = app(handles)
        write("A", "Ann", handles, app)
        show(4, handles, app)
        #expect(line(app).hasPrefix(" A[]|"), "\(line(app))")
    }
}

// MARK: - A core drawing several erased views at its own identity

/// What the labels and the core below leave behind for the test.
@MainActor
private final class LabelHandles {
    var labels: Binding<[Int]>?
    var tick: Binding<Int>?
    var coreSlot: StateBox<String>?
    var writers: [String: (Int) -> Void] = [:]
}

/// A label with state of its own, so its content makes some.
private struct LabelP: View {
    @State private var count = 0
    let handles: LabelHandles
    var body: some View {
        handles.writers["P"] = { count = $0 }
        return Text(verbatim: "P\(count)")
    }
}

/// ``LabelP`` under another name.
private struct LabelQ: View {
    @State private var count = 0
    let handles: LabelHandles
    var body: some View {
        handles.writers["Q"] = { count = $0 }
        return Text(verbatim: "Q\(count)")
    }
}

/// A procedural core that keeps a slot of its own at its identity, at a
/// declaration-order index (as a text field keeps its handler), and draws
/// each label in turn at that same identity, as the search field draws its
/// suggestions' labels.
private struct LabelsCore: View, Renderable {
    let labels: [AnyView]
    let handles: LabelHandles

    var body: Never { fatalError("LabelsCore renders via Renderable") }

    /// Past the labels' own `@State` (index 0), so the two never share a box.
    private static let slotIndex = 7

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let slot = context.stateStorage?.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: Self.slotIndex), default: "")
        handles.coreSlot = slot
        let drawn = labels.map { $0.renderToBuffer(context: context).lines.first ?? "" }
        let line = "core[\(slot?.value ?? "-")] " + drawn.joined(separator: " ") + "|"
        return FrameBuffer(lines: [line])
    }
}

/// The core, with its labels chosen by `labels` (0 is ``LabelP``, 1 ``LabelQ``), which start as given.
private struct LabelsHost: View {
    @State private var labels: [Int]
    @State private var tick = 0
    let handles: LabelHandles

    init(labels: [Int], handles: LabelHandles) {
        _labels = State(initialValue: labels)
        self.handles = handles
    }

    var body: some View {
        handles.labels = $labels
        handles.tick = $tick
        let erased = labels.map { $0 == 0 ? AnyView(LabelP(handles: handles)) : AnyView(LabelQ(handles: handles)) }
        return VStack {
            LabelsCore(labels: erased, handles: handles)
            Text(verbatim: "tick \(tick)")
        }
    }
}

@MainActor
@Suite("A core drawing erased views at its own identity keeps its own state")
struct ErasedLabelsAtOneIdentityTests {
    private func line(_ app: TestApp) -> String {
        app.screen.line(containing: "core[") ?? "\(app.screen)"
    }

    private func show(_ labels: [Int], _ handles: LabelHandles, _ app: TestApp) {
        _ = app.screen
        handles.labels?.wrappedValue = labels
        _ = app.screen
    }

    @Test("Several labels of two types at one identity, in any order, keep the core's slot")
    func severalLabelsKeepTheCoresSlot() {
        let handles = LabelHandles()
        let app = TestApp(width: 40, height: 4) { LabelsHost(labels: [0, 1], handles: handles) }
        _ = app.screen
        handles.coreSlot?.value = "open"
        #expect(line(app).hasPrefix("core[open] P0 Q0|"), "precondition: \(line(app))")
        for frame in 1...3 {
            handles.tick?.wrappedValue = frame
            #expect(line(app).hasPrefix("core[open]"), "frame \(frame): \(line(app))")
        }
        for labels in [[1, 0], [1], [0], [0, 1], [1]] {
            show(labels, handles, app)
            #expect(line(app).hasPrefix("core[open]"), "labels \(labels): \(line(app))")
        }
    }

    @Test("One label at the core's identity changing type starts afresh, and the core keeps its slot")
    func oneLabelSwapKeepsTheCoresSlot() {
        let handles = LabelHandles()
        let app = TestApp(width: 40, height: 4) { LabelsHost(labels: [0], handles: handles) }
        _ = app.screen
        handles.coreSlot?.value = "open"
        handles.writers["P"]?(5)
        #expect(line(app).hasPrefix("core[open] P5|"), "precondition: \(line(app))")
        show([1], handles, app)
        #expect(line(app).hasPrefix("core[open] Q0|"), "Q was handed P's state, or the core lost its own: \(line(app))")
        show([0], handles, app)
        #expect(line(app).hasPrefix("core[open] P0|"), "\(line(app))")
    }
}
