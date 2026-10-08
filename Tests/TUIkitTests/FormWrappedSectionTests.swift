//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FormWrappedSectionTests.swift
//
//  A `Form` reads its content through a `Group`, an `if` and an `if`/`else`,
//  as SwiftUI's does: a section in one is laid out as the same section written
//  bare (measured on macOS 15.8, `D1S/probe2/form`, in both styles). Until
//  then the form drew such a wrapper as one plain row: since a `Section`
//  outside a `List` became its parts (decisions B16), a section in an `if`
//  lost its form header styling, and a `Toggle` in one never had its place in
//  the control column. An `if` keeps one place among the form's elements, so
//  the rows after it keep their identities as it comes and goes. So does a
//  view of the app's own whose body is a section or several rows — the
//  usual way a form is factored (`D1S/probe2/formcomposite`) — its `@State`
//  kept.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitView

/// Records the identity path it renders under.
@MainActor
private final class PathCapture {
    var path = ""
}

private struct PathProbe: View, Renderable {
    let capture: PathCapture
    var body: Never { fatalError("PathProbe renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        capture.path = context.identity.path
        return FrameBuffer(text: "probe")
    }
}

/// A form's section as a view of the app's own, the usual way a form is
/// factored.
private struct General: View {
    var body: some View {
        Section("Advanced") {
            Toggle("Verbose", isOn: .constant(true))
            LabeledContent("Level") { Text("3") }
        }
    }
}

/// A view of the app's own whose body is two of the form's rows, with
/// `@State` of its own behind one of them.
private struct Pair: View {
    @State private var on = false
    var body: some View {
        LabeledContent("Name") { Text("x") }
        Toggle("Wi-Fi", isOn: $on)
    }
}

/// The same linked list built at run time, with no view of the app's own in
/// it: each node an `AnyView` of a `Group` of a row and an `if` around the
/// next. Built from the innermost node out, so making it recurses nowhere.
@MainActor
private func erasedNestedRows(depth: Int) -> AnyView {
    var chain = AnyView(Text("L\(depth)"))
    for level in stride(from: depth - 1, through: 0, by: -1) {
        let next: AnyView? = chain
        chain = AnyView(
            Group {
                Text("L\(level)")
                if let next { next }
            })
    }
    return chain
}

/// A view of the app's own nested in itself through its body's rows, a level
/// deeper each time, to `depth`: a linked list, each node a row and an `if`
/// around the next.
private struct NestedRows: View {
    let level: Int
    let depth: Int
    var body: some View {
        Text("L\(level)")
        if level < depth { Self(level: level + 1, depth: depth) }
    }
}

@MainActor
@Suite("A form looks through a Group and an if")
struct FormWrappedSectionTests {

    /// The form drawn, styling and all.
    private func drawn(_ view: some View) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: 40, height: 20)).lines
    }

    @ViewBuilder
    private func advanced() -> some View {
        Section("Advanced") {
            Toggle("Verbose", isOn: .constant(true))
            LabeledContent("Level") { Text("3") }
        }
    }

    @Test("A section in an if, a Group or an if/else arm draws as the same section bare, in both styles")
    func wrappedSectionsDrawAsBare() {
        let flag = true
        for grouped in [false, true] {
            func styled(_ form: some View) -> [String] {
                grouped ? drawn(form.formStyle(.grouped)) : drawn(form.formStyle(.columns))
            }
            let bare = styled(Form { LabeledContent("Name") { Text("x") }; advanced() })
            let inIf = styled(Form { LabeledContent("Name") { Text("x") }; if flag { advanced() } })
            let inGroup = styled(Form { LabeledContent("Name") { Text("x") }; Group { advanced() } })
            let inArm = styled(
                Form {
                    LabeledContent("Name") { Text("x") }
                    if flag { advanced() } else { Text("never") }
                })
            #expect(inIf == bare, "grouped \(grouped), if: \(inIf.map(\.stripped))")
            #expect(inGroup == bare, "grouped \(grouped), Group: \(inGroup.map(\.stripped))")
            #expect(inArm == bare, "grouped \(grouped), if/else: \(inArm.map(\.stripped))")
        }
    }

    @Test("A false if adds nothing, and a row after it keeps its identity as the if comes and goes")
    func ifKeepsItsPlace() {
        let capture = PathCapture()
        func form(_ show: Bool) -> some View {
            Form {
                if show { advanced() }
                PathProbe(capture: capture)
            }
        }
        let hidden = drawn(form(false)).map(\.stripped)
        #expect(!hidden.contains { $0.contains("Advanced") })
        let hiddenPath = capture.path
        let shown = drawn(form(true)).map(\.stripped)
        #expect(shown.contains { $0.contains("Advanced") })
        #expect(capture.path == hiddenPath, "\(capture.path) vs \(hiddenPath)")
    }

    // MARK: - A collapsible section

    /// The expansion a collapsible section is bound to.
    @MainActor
    private final class Expansion {
        var isExpanded: Bool
        init(_ isExpanded: Bool) { self.isExpanded = isExpanded }
        var binding: Binding<Bool> { Binding(get: { self.isExpanded }, set: { self.isExpanded = $0 }) }
    }

    @Test("A collapsible section in a form draws its header behind a triangle, and its rows only while expanded")
    func collapsibleSection() {
        for grouped in [false, true] {
            func form(_ expansion: Expansion) -> [String] {
                let form = Form {
                    Section("Advanced", isExpanded: expansion.binding) {
                        Toggle("Verbose", isOn: .constant(true))
                    }
                }
                return (grouped ? drawn(form.formStyle(.grouped)) : drawn(form.formStyle(.columns)))
                    .map(\.stripped)
            }
            let open = form(Expansion(true))
            #expect(open.contains { $0.contains("▼") && $0.contains("Advanced") }, "grouped \(grouped): \(open)")
            #expect(open.contains { $0.contains("Verbose") }, "grouped \(grouped): \(open)")
            let closed = form(Expansion(false))
            #expect(closed.contains { $0.contains("▶") && $0.contains("Advanced") }, "grouped \(grouped): \(closed)")
            #expect(!closed.contains { $0.contains("Verbose") || $0.contains("╭") }, "grouped \(grouped): \(closed)")
        }
    }

    @Test("A collapsible section's header in a form is a focus stop that Return toggles, wrapped in an if too")
    func collapsibleHeaderToggles() {
        let expansion = Expansion(false)
        let flag = true
        let view = Form {
            if flag {
                Section("Advanced", isExpanded: expansion.binding) { Text("Inside") }
            }
        }
        let context = makeRenderContext(width: 40, height: 10)
        _ = renderToBuffer(view, context: context)
        guard let manager = context.environment.focusManager,
            let header = manager.registeredFocusIDsInActiveSection().first
        else {
            Issue.record("the header is no focus stop")
            return
        }
        manager.focus(id: header)
        _ = renderToBuffer(view, context: context)
        #expect(manager.dispatchKeyEvent(KeyEvent(key: .enter)))
        #expect(expansion.isExpanded, "Return opened the section")
        let open = renderToBuffer(view, context: context).lines.map(\.stripped)
        #expect(open.contains { $0.contains("Inside") }, "\(open)")
    }

    // MARK: - A view of the app's own

    @Test("A section in a view of the app's own draws as the same section bare, in both styles")
    func sectionInAViewOfTheAppsOwn() {
        for grouped in [false, true] {
            func styled(_ form: some View) -> [String] {
                grouped ? drawn(form.formStyle(.grouped)) : drawn(form.formStyle(.columns))
            }
            let bare = styled(Form { LabeledContent("Name") { Text("x") }; advanced() })
            let own = styled(Form { LabeledContent("Name") { Text("x") }; General() })
            #expect(own == bare, "grouped \(grouped): \(own.map(\.stripped))")
        }
    }

    @Test("A view of the app's own whose body is rows gives the form those rows, and keeps its @State")
    func rowsOfAViewOfTheAppsOwn() throws {
        let bare = drawn(
            Form {
                LabeledContent("Name") { Text("x") }
                Toggle("Wi-Fi", isOn: .constant(false))
            }.formStyle(.columns))
        let own = drawn(Form { Pair() }.formStyle(.columns))
        #expect(own == bare, "\(own.map(\.stripped))")

        let view = Form { Pair() }
        let context = makeRenderContext(width: 40, height: 10)
        _ = renderToBuffer(view, context: context)
        let manager = try #require(context.environment.focusManager)
        let toggle = try #require(manager.registeredFocusIDsInActiveSection().first)
        manager.focus(id: toggle)
        _ = renderToBuffer(view, context: context)
        #expect(manager.dispatchKeyEvent(KeyEvent(key: .space)))
        let after = renderToBuffer(view, context: context).lines.map(\.stripped)
        let on = drawn(
            Form {
                LabeledContent("Name") { Text("x") }
                Toggle("Wi-Fi", isOn: .constant(true))
            }.formStyle(.columns)
        ).map(\.stripped)
        #expect(after.filter { $0.contains("Wi-Fi") } == on.filter { $0.contains("Wi-Fi") }, "\(after)")
    }

    @Test("A view of the app's own nested in itself deeper than the stack holds is read as far as the stack allows")
    func deeplyNestedViewIsReadAsFarAsTheStackAllows() {
        // Far deeper than any stack holds: the form's walk reads through each
        // level's body, and without a guard on that descent it takes the
        // whole test process down. The walk alone, as the form starts it:
        // the level it stops at is then the render's to draw, whole.
        let walk = makeRenderContext(width: 40, height: 10).withChildIdentity(type: _FormContentWalk.self)
        let rows = formRows(of: formElements(from: NestedRows(level: 0, depth: 100_000), in: walk))
        #expect(rows.count > 100, "the levels the stack holds are read through: \(rows.count) rows")
        #expect(rows.count < 100_000, "the walk stopped short of the innermost level")
        // The level it stopped at is one row, drawn whole: the view there,
        // whichever of a level's views the stack ran short at — the level
        // itself, its body's rows, or the `if` around the next.
        guard case .plain? = rows.last?.kind else {
            Issue.record("the last row is no plain row")
            return
        }
    }

    /// The guard above sat on a view of the app's own read through, and the
    /// walk descends as deep through an `AnyView`, a `Group` and an `if` —
    /// each read through by an extractor of its own that asks the walk again.
    /// A chain of them built at run time has no view of the app's own to stop
    /// at, and overflowed the stack the same way.
    @Test("A chain of erased views deeper than the stack holds is read as far as the stack allows")
    func deeplyNestedErasedChainIsReadAsFarAsTheStackAllows() {
        // Deep enough that the walk would need several times the stack,
        // shallow enough that releasing the chain — one node inside the
        // next — fits in it.
        let depth = 10_000
        let chain = erasedNestedRows(depth: depth)
        let walk = makeRenderContext(width: 40, height: 10).withChildIdentity(type: _FormContentWalk.self)
        let rows = formRows(of: formElements(from: chain, in: walk))
        #expect(rows.count > 100, "the levels the stack holds are read through: \(rows.count) rows")
        #expect(rows.count < depth, "the walk stopped short of the innermost level")
        // The level it stopped at is one row, drawn whole.
        guard case .plain? = rows.last?.kind else {
            Issue.record("the last row is no plain row")
            return
        }
    }
}
