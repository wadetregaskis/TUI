//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextSuggestionsResolutionTests.swift
//
//  A text field's suggestions are found where SwiftUI finds them (deviation
//  V7, fixed by the owner's ruling of 2026-10-13). They used to be read by
//  asking the builder's TYPE, and only seven types answered — a `Text`, a
//  `Divider`, `EmptyView`, a tuple, a `ForEach`, an `if`/`else` and an `if` —
//  so suggestions inside a view of the app's own, a `Group`, a `Section` or an
//  `AnyView`, and a completion with a modifier written after it, were not
//  there: the field offered fewer or none, with no warning. They are now read
//  as the builder's members, as `Group(subviews:)` resolves them, as a
//  `Picker`'s options are.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitTextInput

@MainActor
@Suite("A text field's suggestions, wherever they are written")
struct TextSuggestionsResolutionTests {
    /// Suggestions in a view of the app's own.
    private struct CitySuggestions: View {
        var body: some View {
            ForEach(["Paris", "Rome"], id: \.self) { Text($0) }
        }
    }

    /// A suggestion that is a view of the app's own, drawing one `Text`.
    private struct CityRow: View {
        let name: String
        var body: some View { Text(name) }
    }

    private func entries(_ suggestions: some View) -> [_TextSuggestionEntry] {
        textSuggestionEntries(of: suggestions, in: makeRenderContext(width: 40, height: 12))
    }

    /// Each entry as the menu would read it: an option's explicit completion
    /// (or its label's text), `[token]` for a token, `—` for a rule.
    private func described(_ entries: [_TextSuggestionEntry]) -> [String] {
        let context = makeRenderContext(width: 40, height: 2)
        func text(_ label: AnyView) -> String {
            (label.renderToBuffer(context: context).lines.first ?? "").stripped
                .trimmingCharacters(in: .whitespaces)
        }
        return entries.map { entry in
            switch entry {
            case .option(let completion, let label): completion ?? text(label)
            case .token(let token, _): "[\(token)]"
            case .divider: "—"
            }
        }
    }

    @Test("Suggestions inside a view of the app's own are found")
    func appsOwnView() {
        #expect(described(entries(CitySuggestions())) == ["Paris", "Rome"])
    }

    @Test("A suggestion that is a view of the app's own fills the field with its text")
    func appsOwnRow() {
        #expect(described(entries(CityRow(name: "Oslo"))) == ["Oslo"])
    }

    @Test("Suggestions inside a Group or an AnyView are found")
    func groupAndAnyView() {
        let grouped = entries(
            Group {
                Text("Paris")
                Text("Rome")
            })
        #expect(described(grouped) == ["Paris", "Rome"])
        let erased = entries(
            Group {
                AnyView(Text("Paris").textInputCompletion("paris, fr"))
                Text("Rome")
            })
        #expect(described(erased) == ["paris, fr", "Rome"])
    }

    @Test("A modifier written after the completion keeps it")
    func modifierAfterCompletion() {
        let found = entries(
            Group {
                Text("Paris").textInputCompletion("paris, fr").bold()
                Text("Rome").textInputCompletion("roma, it").padding(.leading, 1)
            })
        #expect(described(found) == ["paris, fr", "roma, it"])
    }

    @Test("Each section's suggestions are found, a rule setting each apart")
    func sections() {
        let found = entries(
            Group {
                Section("Favourites") { Text("Paris") }
                Section("Recent") {
                    Text("Rome")
                    Text("Oslo")
                }
            })
        #expect(described(found) == ["Paris", "—", "Rome", "Oslo"])
    }

    @Test("Only the branch an if takes contributes suggestions")
    func conditional() {
        func found(recent: Bool) -> [String] {
            described(
                entries(
                    Group {
                        Text("Paris")
                        if recent {
                            Divider()
                            Text("Rome")
                        }
                    }))
        }
        #expect(found(recent: true) == ["Paris", "—", "Rome"])
        #expect(found(recent: false) == ["Paris"])
    }

    @Test("A search token given with searchCompletion is found through a modifier after it")
    func tokenThroughModifier() {
        let found = entries(
            Group {
                Text("Apple").containerValue(\.searchTokenCompletion, SearchTokenCompletion(token: "apple")).bold()
                Text("Pear")
            })
        #expect(described(found) == ["[apple]", "Pear"])
    }

    @Test("A field under suggestions in a view of the app's own opens a menu of them")
    func menuEndToEnd() {
        final class TextBox {
            var value = ""
            var binding: Binding<String> { Binding(get: { self.value }, set: { self.value = $0 }) }
        }
        let tui = TUIContext()
        let focus = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = focus
        env.applyRuntimeServices(from: tui)
        env.terminalWidth = 60
        env.terminalHeight = 20
        let box = TextBox()
        let field = TextField("City", text: box.binding)
            .focusID("city")
            .textInputSuggestions { CitySuggestions() }
            .frame(width: 24)
        func render() -> FrameBuffer {
            let context = RenderContext(availableWidth: 60, availableHeight: 20, environment: env, tuiContext: tui)
            focus.beginRenderPass()
            let buffer = renderToBuffer(field, context: context)
            focus.endRenderPass()
            return buffer
        }
        _ = render()
        focus.focus(id: "city")
        _ = render()
        _ = focus.dispatchKeyEvent(KeyEvent(key: .down))
        let screen = render().compositingOverlays(maxWidth: 60, maxHeight: 20, palette: env.palette)
            .lines.map(\.stripped).joined(separator: "\n")
        #expect(screen.contains("Paris") && screen.contains("Rome"), "\(screen)")
    }
}
