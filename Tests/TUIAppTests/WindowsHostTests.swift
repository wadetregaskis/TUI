//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowsHostTests.swift
//
//  Windows Terminal and the classic Windows console (conhost) as hosts TUI has
//  measured: what names each, and what each advances every row of its record
//  by (`windows-terminal-1.24.12741.0-*.json`, `conhost-10.0.26300-*.json`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUITerminalHost

@Suite("Windows Terminal and conhost as hosts")
struct WindowsHostTests {

    // MARK: - Naming them

    @Test("Their names go round")
    func named() {
        #expect(TerminalClient.Program(termProgramName: "WindowsTerminal") == .windowsTerminal)
        #expect(TerminalClient.Program.windowsTerminal.termProgramName == "WindowsTerminal")
        #expect(TerminalClient.Program(termProgramName: "conhost") == .windowsConsole)
        #expect(TerminalClient.Program.windowsConsole.termProgramName == "conhost")
    }

    @Test("WT_SESSION names Windows Terminal, and TERM_PROGRAM still outranks it")
    func sessionNamesWindowsTerminal() {
        #expect(TerminalHost.detectProgram(environment: ["WT_SESSION": "b6139141"]) == .windowsTerminal)
        #expect(TerminalHost.detectProgram(environment: ["WT_SESSION": ""]) == .unidentified)
        // VS Code's terminal, started from a Windows Terminal tab, inherits the
        // session and names itself.
        #expect(
            TerminalHost.detectProgram(environment: ["WT_SESSION": "b6139141", "TERM_PROGRAM": "vscode"])
                == .unidentified)
    }

    /// The replies as measured (`identity_probe.py`, 2026-11-16).
    private static let windowsTerminalDA1 = "\u{1B}[?61;4;6;7;14;21;22;23;24;28;32;42;52c"
    private static let conhostDA1 = "\u{1B}[?61;1;6;7;21;22;23;24;28;32;42;52c"
    private static let sharedDA2 = "\u{1B}[>0;10;1c"

    private func name(_ primary: String, _ secondary: String = sharedDA2, version: String = "") -> String? {
        TerminalHost.nameFromDeviceAttributes(
            TerminalIdentityQuery.parse(Array((version + primary + secondary + "\u{1B}[0n").utf8)))
    }

    @Test("Their Device Attributes name each, by Sixel and by 132 columns")
    func deviceAttributes() {
        #expect(name(Self.windowsTerminalDA1) == "WindowsTerminal")
        #expect(name(Self.conhostDA1) == "conhost")
        // Both attributes, or neither, names neither.
        #expect(name("\u{1B}[?61;1;4;6;22c") == nil)
        #expect(name("\u{1B}[?61;6;22c") == nil)
        // Another DA2, an older conformance level, or an XTVERSION answer rules them out.
        #expect(name(Self.windowsTerminalDA1, "\u{1B}[>0;276;0c") == nil)
        #expect(name("\u{1B}[?62;4;22c") == nil)
        #expect(name(Self.conhostDA1, version: "\u{1B}P>|Terminal(1)\u{1B}\\") == nil)
    }

    // MARK: - Windows Terminal's advance

    @Test("Windows Terminal's model is its record, but for what no CUF repairs")
    func windowsTerminalModelIsItsRecord() throws {
        // The invisible format characters advance 1 against 0 there; an
        // over-advance reads as the claim (`windowsTerminalCursorAdvance`).
        let overAdvancing: Set<String> = [
            "bidi_lrm", "bidi_rlm", "word_joiner", "function_application", "invisible_times",
            "invisible_separator", "invisible_plus", "mongolian_vowel_separator",
        ]
        try TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: .windowsTerminal)) {
            for (file, record) in try AdvanceRecord.load([
                "windows-terminal-1.24.12741.0-advance.json", "windows-terminal-1.24.12741.0-alternate.json",
            ]) {
                for (id, measured) in record.advances {
                    let cluster = Self.cluster(measured.cluster)
                    guard cluster.count == 1, let character = cluster.first else { continue }
                    let expected = overAdvancing.contains(id) ? character.terminalWidth : measured.advance
                    #expect(
                        character.windowsTerminalCursorAdvance == expected,
                        "\(id) (\(measured.cluster)) in \(file): measured \(measured.advance)")
                }
                for id in overAdvancing {
                    #expect(record.advances[id]?.advance == 1, "\(id) in \(file)")
                }
            }
        }
    }

    // MARK: - conhost's advance

    @Test("conhost's cell count is its record, row for row")
    func conhostCellsAreItsRecord() throws {
        try TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: .windowsConsole)) {
            for (file, record) in try AdvanceRecord.load([
                "conhost-10.0.26300-advance.json", "conhost-10.0.26300-alternate.json",
            ]) {
                for (id, measured) in record.advances {
                    let cells = Self.cluster(measured.cluster).reduce(0) { $0 + $1.windowsConsoleCells }
                    #expect(cells == measured.advance, "\(id) (\(measured.cluster)) in \(file)")
                }
            }
        }
    }

    @Test(
        "conhost's model is short only where a CUF repairs it",
        arguments: [
            ("\u{1F5A5}", 1),  // a bare pictograph
            ("\u{1FAE9}", 1),  // Unicode 16
            ("\u{1F600}", 2),
            ("\u{0065}\u{0301}", 1),  // over-advances: read as the claim
        ])
    func conhostModel(text: String, advance: Int) {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: .windowsConsole)) {
            #expect(Character(text).windowsConsoleCursorAdvance == advance)
        }
    }

    @Test(
        "conhost is sent a spelling that fits where one does",
        arguments: [
            ("\u{2B1B}\u{FE0E}", "\u{2B1B}"),  // a selector after a wide base
            ("\u{3030}\u{FE0F}", "\u{3030}"),
            ("\u{0065}\u{0301}", "\u{00E9}"),  // composed
        ])
    func conhostRespelling(text: String, spelled: String) {
        // By scalar throughout: `==` on a `Character` or a `String` is
        // canonical equivalence, by which `é` is already `e` + U+0301.
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: .windowsConsole)) {
            let respelled = Character(text).windowsConsoleRespelling.map { Array($0.unicodeScalars) }
            #expect(respelled == Array(spelled.unicodeScalars))
            let emitted = TerminalClient.compensating(text + "|", for: .windowsConsole)
            #expect(Array(emitted.unicodeScalars) == Array((spelled + "|").unicodeScalars))
        }
    }

    @Test(
        "and the rest is sent as written",
        arguments: [
            "\u{2764}\u{FE0F}",  // a narrow base: the selector is what makes it two cells
            "\u{0031}\u{FE0F}\u{20E3}",  // a keycap: no spelling claims what it does
            "\u{0938}\u{094D}\u{0924}",  // a conjunct: nothing composes
            "A",
        ])
    func conhostNoRespelling(text: String) {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: .windowsConsole)) {
            #expect(Character(text).windowsConsoleRespelling == nil)
        }
    }

    @Test("conhost is sent a flag as its letters, and a short pictograph its CUF")
    func conhostCompensation() {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: .windowsConsole)) {
            #expect(TerminalClient.compensating("\u{1F1FA}\u{1F1F8}|", for: .windowsConsole) == "US|")
            #expect(
                TerminalClient.compensating("\u{1F5A5}|", for: .windowsConsole)
                    == "\u{1B}[2X\u{1F5A5}\u{1B}[1C|")
        }
    }

    @Test("Windows Terminal gets a CUF after a short glyph, and nothing else changes")
    func windowsTerminalCompensation() {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: .windowsTerminal)) {
            #expect(
                TerminalClient.compensating("\u{1F5A5}|", for: .windowsTerminal)
                    == "\u{1B}[2X\u{1F5A5}\u{1B}[1C|")
            for row in ["plain \u{1F600}", "\u{1F1FA}\u{1F1F8}", "\u{2B1B}\u{FE0E}", "e\u{0301}"] {
                #expect(TerminalClient.compensating(row, for: .windowsTerminal) == row)
            }
        }
    }

    // MARK: - Reading a record's clusters

    /// `U+0938 U+094D …` as the text it names.
    private static func cluster(_ codePoints: String) -> String {
        var text = ""
        for token in codePoints.split(separator: " ") {
            guard let value = UInt32(token.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(value) else {
                continue
            }
            text.unicodeScalars.append(scalar)
        }
        return text
    }
}
