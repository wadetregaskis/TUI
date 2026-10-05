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
//  the rows after it keep their identities as it comes and goes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
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
}
