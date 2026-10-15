//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ForEachSubviewsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitForms
@testable import TUIkitFoundation
@testable import TUIkitPickers
@testable import TUIkitTestSupport
@testable import TUIkitTextInput

// MARK: - Fixtures

/// The identity each probe rendered at, by name.
@MainActor
private final class IdentityLog {
    var paths: [String: Set<String>] = [:]
}

/// Draws its name, and records the identity it drew at.
private struct Probe: View, Renderable {
    let name: String
    let log: IdentityLog

    var body: Never { fatalError("Probe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        log.paths[name, default: []].insert(context.identity.path)
        return FrameBuffer(text: name)
    }
}

/// Counts how many rows a loop built.
@MainActor
private final class BuildCount {
    var rows = 0
}

private struct Named: Identifiable, Equatable {
    let id: String
}

// MARK: - Suite

/// `ForEach(subviews:content:)`: one row per member, identified by its
/// `Subview.ID`, resolved where the loop is drawn.
@MainActor
@Suite("ForEach over subviews")
struct ForEachSubviewsTests {

    private func render(_ view: some View, width: Int = 40, height: Int = 10) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map(\.stripped)
    }

    @Test("One row per member, in a stack")
    func rowsInAStack() {
        let lines = render(
            HStack(spacing: 1) {
                ForEach(subviews: Group { Text("a"); Text("b"); Text("c") }) { subview in
                    subview
                }
            })
        #expect(lines == ["a b c"])
    }

    @Test("Each row draws its member with the row's modifiers")
    func rowModifiers() {
        let lines = render(
            VStack(alignment: .leading) {
                ForEach(subviews: Group { Text("a"); Text("b") }) { subview in
                    subview.padding(.leading, 2)
                }
            })
        #expect(lines == ["  a", "  b"])
    }

    @Test("Alone, the rows stack vertically")
    func alone() {
        #expect(render(ForEach(subviews: Group { Text("a"); Text("b") }) { $0 }) == ["a", "b"])
    }

    @Test("A row reads its member's container values")
    func containerValues() {
        let lines = render(
            VStack {
                ForEach(subviews: ForEach([3, 4], id: \.self) { Text("\($0)") }) { subview in
                    Text("tag \(subview.containerValues.tag(for: Int.self) ?? -1)")
                }
            })
        #expect(lines == ["tag 3", "tag 4"])
    }

    /// SwiftUI takes an `AnyView` apart (the compatibility guide's Subviews
    /// row, measured), so the tag of the view it erases is the member's.
    @Test("A member that is an AnyView has the tag of the view it erases")
    func anyViewMemberCarriesItsTag() {
        let lines = render(
            VStack {
                ForEach(subviews: Group { AnyView(Text("a").tag(7)); Text("b").tag(8) }) { subview in
                    Text("tag \(subview.containerValues.tag(for: Int.self) ?? -1)")
                }
            })
        #expect(lines == ["tag 7", "tag 8"])
    }

    @Test("A row's identity follows its member across a reorder")
    func identityFollowsMember() {
        let log = IdentityLog()
        func draw(_ items: [Named]) {
            _ = render(
                VStack {
                    ForEach(subviews: ForEach(items) { Text($0.id) }) { subview in
                        Probe(name: "row-\(subview.containerValues.tag(for: String.self) ?? "?")", log: log)
                    }
                })
        }
        draw([Named(id: "a"), Named(id: "b")])
        draw([Named(id: "b"), Named(id: "a")])
        #expect(log.paths["row-a"]?.count == 1)
        #expect(log.paths["row-b"]?.count == 1)
        #expect(log.paths["row-a"] != log.paths["row-b"])
    }

    @Test("Rows and the members they draw never share an identity")
    func rowsAndMembersApart() {
        let log = IdentityLog()
        _ = render(
            VStack {
                ForEach(subviews: Probe(name: "member", log: log)) { subview in
                    HStack {
                        Probe(name: "row", log: log)
                        subview
                    }
                }
            })
        let member = log.paths["member"] ?? []
        let row = log.paths["row"] ?? []
        #expect(!member.isEmpty && !row.isEmpty)
        #expect(member.isDisjoint(with: row))
    }

    @Test("In a lazy stack, only the rows drawn are built")
    func lazyStackStaysWindowed() {
        let built = BuildCount()
        let lines = render(
            ScrollView {
                LazyVStack {
                    ForEach(
                        subviews: ForEach(0..<2000) { index -> Text in
                            built.rows += 1
                            return Text("\(index)")
                        }
                    ) { $0 }
                }
            },
            height: 5)
        #expect(lines.first?.split(separator: " ").first == "0", "\(lines)")
        #expect(built.rows > 0)
        #expect(built.rows < 200, "built \(built.rows) rows to draw 5")
    }

    // MARK: - The walks that read rows without drawing them

    /// `List` and `Form` ask a `ForEach` for its rows without a context; a
    /// loop over subviews has none to give them, and must give none rather
    /// than rows it cannot account for. (A `Picker` and a text field's
    /// suggestions read their content's members in the context they are drawn
    /// in, so they see the loop's; a `TabView` takes tabs, which a loop over
    /// subviews is not, so it does not compile there.)
    @Test("A walk without a context sees no rows, and suggestions, read in one, see the loop's")
    func contextlessWalksSeeNothing() {
        let loop = ForEach(subviews: Group { Text("a"); Text("b") }) { $0 }
        #expect(textSuggestionEntries(of: loop, in: makeRenderContext(width: 10, height: 4)).count == 2)
        #expect(loop.extractFormElements(in: makeRenderContext(width: 10, height: 4)).isEmpty)
        #expect(loop.listRowCount == 0)
        #expect(loop.keyedElementCount == 0)
    }

    /// Each either draws the loop's members, if it lays its content out as
    /// views somewhere, or draws none of them — never one without the other,
    /// and never traps on a count it cannot reconcile.
    @Test("Inside a List, Picker, Form or suggestions, the loop does not trap")
    func containersThatReadRows() {
        let loop = ForEach(subviews: Group { Text("alpha"); Text("beta") }) { $0 }
        for view in [
            AnyView(List { loop }),
            AnyView(Picker("Pick", selection: .constant(0)) { loop }.pickerStyle(.radioGroup)),
            AnyView(Form { loop }),
            AnyView(TextField("Field", text: .constant("")).textInputSuggestions { loop }),
        ] {
            let lines = render(view, height: 12)
            let alpha = lines.contains { $0.contains("alpha") }
            let beta = lines.contains { $0.contains("beta") }
            #expect(alpha == beta, "\(lines)")
        }
    }
}
