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

    @Test("A TUIkit type's reflected name is its declaring module's, not the umbrella's")
    func reflectedNamesNameTheDeclaringModule() {
        // So `String(reflecting:)`, `dump` and the debugger say
        // `TUIkitFoundation.Text`: the umbrella declares nothing. (`Text`
        // stays in TUIkitFoundation as the split goes on; a type that is
        // carved into another module takes that module's name.)
        #expect(String(reflecting: TUIkit.Text.self) == "TUIkitFoundation.Text")
        #expect(!String(reflecting: TUIkit.Color.self).hasPrefix("TUIkit."))
    }
}
