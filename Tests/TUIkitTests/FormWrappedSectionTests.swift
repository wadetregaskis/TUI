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
}
