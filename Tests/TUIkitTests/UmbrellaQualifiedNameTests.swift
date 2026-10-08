//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UmbrellaQualifiedNameTests.swift
//
//  An app spells `TUIkit.X` to reach TUIkit's `X` past a type of its own with
//  the same name. Since step B1 of the module split the TUIkit module declares
//  nothing: `X` is TUIkitFoundation's, or a lower module's, reached through the
//  umbrella's `@_exported import`s. Qualified lookup does go through them —
//  probe t14 of the plan's step 0b measured it on Swift 6.2.4 (Xcode and
//  swift.org) and 6.3.3 (Linux) — and this file keeps that probe's shapes as a
//  test, so a carve that broke one would stop it compiling. It imports only
//  `TUIkit`, as an app does: no `@testable`, no lower module.
//
//  t14 measured one re-export. Since step B2 a type of TUIkitStrings or
//  TUIkitTerminalHost is two away: the umbrella re-exports TUIkitFoundation,
//  which re-exports those modules (the umbrella names neither). The second
//  test spells such types through the umbrella, so it is the measurement of
//  that case, and a carve that dropped a re-export below the umbrella would
//  stop it compiling too.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkit

/// An app's own `Label`, beside TUIkit's.
private enum Client {
    struct Label {
        let name: String
    }

    /// Both labels: the app's by its plain name, TUIkit's by the umbrella's.
    @MainActor
    static func both() -> (Label, TUIkit.Label<TUIkit.Text, TUIkit.Text>) {
        (Label(name: "mine"), TUIkit.Label { TUIkit.Text(verbatim: "t14 title") } icon: { TUIkit.Text(verbatim: "*") })
    }

    /// An app's own `TerminalClient`, beside TUIkitTerminalHost's.
    struct TerminalClient {
        let name: String
    }

    /// Both clients: the app's by its plain name, and a program of TUIkit's
    /// by the umbrella's spelling, two re-exports down.
    static func bothClients() -> (TerminalClient, TUIkit.TerminalClient.Program) {
        (TerminalClient(name: "mine"), TUIkit.TerminalClient.Program.ghostty)
    }
}

/// A style conforming through the umbrella's spelling of the protocol.
private struct BracketedLabelStyle: TUIkit.LabelStyle {
    func makeBody(configuration: Configuration) -> some TUIkit.View {
        TUIkit.HStack(spacing: 0) {
            TUIkit.Text(verbatim: "[")
            configuration.title
            TUIkit.Text(verbatim: "]")
        }
    }
}

extension TUIkit.Label where Title == TUIkit.Text, Icon == TUIkit.Text {
    /// A member an app adds to TUIkit's type through the umbrella's name.
    fileprivate var t14Marker: Int { 14 }
}

extension TUIkit.LocalizationService.Language {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIkitStrings, which reaches the umbrella through TUIkitFoundation.
    fileprivate var b2Marker: String { "b2-\(rawValue)" }
}

@MainActor
@Suite("TUIkit.X in an app's source")
struct UmbrellaQualifiedNameTests {
    @Test("A qualified name reaches the declaring module's type, beside an app's type of the same name")
    func qualifiedNamesResolveThroughTheUmbrella() {
        let (mine, theirs) = Client.both()
        #expect(mine.name == "mine")
        #expect(theirs.t14Marker == 14)
        // An initializer as a value, and a function a lower module declares.
        let make: (String) -> TUIkit.Text = TUIkit.Text.init(verbatim:)
        let buffer: TUIkit.FrameBuffer = TUIkit.renderToBuffer(
            TUIkit.VStack { theirs.labelStyle(BracketedLabelStyle()); make("made") },
            context: makeRenderContext(width: 40, height: 2))
        let lines = buffer.lines.map(\.stripped)
        #expect(lines.first?.contains("[t14 title]") == true, "\(lines)")
        #expect(lines.last?.contains("made") == true, "\(lines)")
    }

    @Test("A qualified name reaches a module that TUIkitFoundation re-exports in turn")
    func qualifiedNamesResolveThroughTwoReExports() {
        // TUIkitTerminalHost's types: beside an app's own `TerminalClient`,
        // and a static function as a value.
        let (mine, program) = Client.bothClients()
        #expect(mine.name == "mine")
        #expect(program == .ghostty)
        let advance: (Character, TUIkit.TerminalClient.Program) -> Int =
            TUIkit.TerminalClient.cursorAdvance(of:on:)
        #expect(advance("a", program) == 1)
        // TUIkitStrings' types: a nested type through a class, and a member an
        // app's extension adds to it.
        let language: TUIkit.LocalizationService.Language = .german
        #expect(language.b2Marker == "b2-de")
        #expect(TUIkit.LocalizationService.Language.allCases.contains(language))
    }

    @Test("A TUIkit type's reflected name is its declaring module's, not the umbrella's")
    func reflectedNamesNameTheDeclaringModule() {
        // So `String(reflecting:)`, `dump` and the debugger say
        // `TUIkitFoundation.Text`: the umbrella declares nothing. (`Text`
        // stays in TUIkitFoundation as the split goes on; a type that is
        // carved into another module takes that module's name.) Both
        // expectations read `TUIkit.` before step B1, when `Label` and `Text`
        // were the TUIkit module's.
        #expect(String(reflecting: TUIkit.Text.self) == "TUIkitFoundation.Text")
        // A generic type names each argument's module as well: TUIkitStyling's
        // `Color` was never the TUIkit module's, so only the other two moved.
        #expect(
            String(reflecting: TUIkit.Label<TUIkit.Text, TUIkit.Color>.self)
                == "TUIkitFoundation.Label<TUIkitFoundation.Text, TUIkitStyling.Color>")
    }
}
