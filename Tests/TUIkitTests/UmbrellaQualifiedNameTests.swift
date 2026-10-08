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
//  Step B3 carved TUIkitApp out the other way: built on TUIkitFoundation,
//  not under it, so TUIkitFoundation cannot re-export it, and the umbrella
//  does, beside TUIkitFoundation. The third test spells its types through the
//  umbrella, so a carve that left TUIkitApp out of the umbrella's re-exports
//  would stop this file compiling as well.
//
//  Step B4 carved TUIkitColorPicker out the same way, so the umbrella
//  re-exports a second module beside TUIkitFoundation. The fourth test spells
//  its types through the umbrella: an app's own `ColorPicker` beside it is the
//  case an app meets (a colour picker of its own, written before it adopted
//  TUIkit), and a carve that left the module out of the umbrella's re-exports
//  stops this file compiling.
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

    /// An app's own `Scene`, beside TUIkitApp's protocol.
    struct Scene {
        let name: String
    }

    /// Both scenes: the app's by its plain name, and a window group by the
    /// umbrella's spelling of TUIkitApp's protocol and type.
    @MainActor
    static func bothScenes() -> (Scene, some TUIkit.Scene) {
        (Scene(name: "mine"), TUIkit.WindowGroup { TUIkit.Text(verbatim: "b3") })
    }

    /// An app's own `ColorPicker`, beside TUIkitColorPicker's view.
    struct ColorPicker {
        let name: String
    }

    /// Both pickers: the app's by its plain name, TUIkit's by the umbrella's.
    @MainActor
    static func bothPickers(selection: TUIkit.Binding<TUIkit.Color>) -> (ColorPicker, TUIkit.ColorPicker) {
        (ColorPicker(name: "mine"), TUIkit.ColorPicker("b4", selection: selection))
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

extension TUIkit.WindowGroup {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIkitApp, which the umbrella re-exports itself.
    fileprivate var b3Marker: Int { 3 }
}

extension TUIkit.ColorPicker {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIkitColorPicker, which the umbrella re-exports itself.
    fileprivate var b4Marker: Int { 4 }
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

    @Test("A qualified name reaches TUIkitApp, which the umbrella re-exports beside TUIkitFoundation")
    func qualifiedNamesReachTheModuleBuiltOnFoundation() {
        // TUIkitApp's types: a scene beside an app's own `Scene`, as an
        // opaque `some TUIkit.Scene`, and a member an app's extension adds.
        let (mine, group) = Client.bothScenes()
        #expect(mine.name == "mine")
        #expect(String(reflecting: type(of: group)) == "TUIkitApp.WindowGroup<TUIkitFoundation.Text>")
        #expect(TUIkit.WindowGroup { TUIkit.Text(verbatim: "b3") }.b3Marker == 3)
        // A conformance spelled through the umbrella, and a free function of
        // TUIkitApp's as a value (never called: it writes to the terminal).
        let style: any TUIkit.WindowToolbarStyle = TUIkit.DefaultWindowToolbarStyle()
        #expect(style is TUIkit.DefaultWindowToolbarStyle)
        let draw: (() -> TUIkit.Text) -> Void = TUIkit.renderOnce(content:)
        _ = draw
    }

    @Test("A qualified name reaches TUIkitColorPicker, which the umbrella re-exports beside TUIkitApp")
    func qualifiedNamesReachTheColorPicker() {
        // TUIkitColorPicker's view beside an app's own `ColorPicker`, a member
        // an app's extension adds to it, and the view drawn: its label and
        // the swatch's selection come out of the render.
        let (mine, picker) = Client.bothPickers(selection: .constant(TUIkit.Color.red))
        #expect(mine.name == "mine")
        #expect(picker.b4Marker == 4)
        let lines = TUIkit.renderToBuffer(picker, context: makeRenderContext(width: 60, height: 3)).lines
            .map(\.stripped)
        #expect(lines.first?.contains("b4") == true, "\(lines)")
        // A curve editor, whose initializer takes a TUIkitImage type, spelled
        // through the umbrella too.
        let panel = TUIkit.ToneCurveEditorPanel(
            stops: .constant([TUIkit.ASCIIToneCurve.Stop]()), isPresented: .constant(true))
        #expect(String(reflecting: type(of: panel)) == "TUIkitColorPicker.ToneCurveEditorPanel")
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
        // Step B2 carved these out of TUIkitFoundation, and each read
        // `TUIkitFoundation.` between B1 and B2: a carve renames what an app
        // sees of every type it moves (decisions SPB2, "What an app can see").
        #expect(String(reflecting: TUIkit.TerminalClient.self) == "TUIkitTerminalHost.TerminalClient")
        #expect(
            String(reflecting: TUIkit.LocalizationService.Language.self)
                == "TUIkitStrings.LocalizationService.Language")
        if #available(macOS 15, *) {
            #expect(
                String(reflecting: TUIkit.SystemFormatStyle.Timer.self) == "TUIkitStrings.SystemFormatStyle.Timer")
        }
        // Step B3 carved these out (decisions SPB3, "What an app can see");
        // each read `TUIkitFoundation.` between B1 and B3. A generic type of
        // TUIkitApp names TUIkitFoundation for its argument.
        #expect(
            String(reflecting: TUIkit.WindowGroup<TUIkit.Text>.self)
                == "TUIkitApp.WindowGroup<TUIkitFoundation.Text>")
        #expect(String(reflecting: TUIkit.DefaultWindowToolbarStyle.self) == "TUIkitApp.DefaultWindowToolbarStyle")
        // Step B4 carved these out (decisions SPB4, "What an app can see");
        // each read `TUIkitFoundation.` between B1 and B4.
        #expect(String(reflecting: TUIkit.ColorPicker.self) == "TUIkitColorPicker.ColorPicker")
        #expect(String(reflecting: TUIkit.ColorPickerPanel.self) == "TUIkitColorPicker.ColorPickerPanel")
    }
}
