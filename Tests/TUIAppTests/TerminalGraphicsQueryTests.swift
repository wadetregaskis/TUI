//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalGraphicsQueryTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// The handshake. This is the one terminal capability in the project that is
/// asked rather than looked up, so what it asks and how it reads the answer
/// are the whole of the detection.
@MainActor
@Suite("Kitty graphics handshake")
struct TerminalGraphicsQueryTests {

    @Test("The transmit is silent and the placement is not")
    func onlyThePlacementSpeaks() {
        let request = TerminalGraphicsQuery.request
        // Three commands go out, and if all three spoke the reply would have
        // to be counted rather than read: every acknowledgement has the same
        // `ESC _ G i=…;` shape.
        #expect(request.contains("a=t,q=2"), "the transmit is quiet")
        #expect(request.contains("a=d,d=I,q=2"), "and so is the delete")
        #expect(request.contains("a=p,U=1,q=0"), "the placement is the question")
        #expect(request.hasSuffix("\u{1B}[5n"), "fenced, so silence is an answer")
    }

    /// The fence test used to look at the LAST byte only: a keystroke landing
    /// behind the reply held the read open for the whole timeout, and a bare
    /// `ESC R` typed before the reply ended it early with pictures off. One
    /// scan now, the status fence every startup exchange shares — and since
    /// that is `CSI 0 n`, a modified F3 (`CSI 1;2 R`, a cursor report's shape)
    /// no longer ends the read either.
    @Test("The fence is found wherever it lands, and neither ESC R nor a modified F3 is one")
    func fenceIsScanned() {
        #expect(TerminalQueryReplies.sawStatusFence(Array("\u{1B}[0n".utf8)))
        #expect(TerminalQueryReplies.sawStatusFence(Array("\u{1B}[0nx".utf8)), "a byte behind the reply")
        #expect(TerminalQueryReplies.sawStatusFence(Array("\u{1B}_Gi=1;OK\u{1B}\\\u{1B}[0n".utf8)))
        #expect(!TerminalQueryReplies.sawStatusFence(Array("\u{1B}R".utf8)), "not a CSI")
        #expect(!TerminalQueryReplies.sawStatusFence(Array("\u{1B}_Gi=1;OK\u{1B}\\".utf8)), "no fence yet")
        #expect(!TerminalQueryReplies.sawStatusFence(Array("\u{1B}_Gi=1;OK\u{1B}\\\u{1B}[1;2R".utf8)), "Shift-F3")
        let keyThenAnswer = "\u{1B}[1;2R\u{1B}_Gi=\(TerminalGraphicsQuery.probeID);OK\u{1B}\\\u{1B}[0n"
        #expect(TerminalQueryReplies.sawStatusFence(Array(keyThenAnswer.utf8)))
        #expect(TerminalGraphicsQuery.parse(Array(keyThenAnswer.utf8)).placement)
    }

    /// Apple Terminal prints an APC payload instead of consuming it, and it is
    /// not necessarily the only terminal that does. The request cleans up
    /// after itself so an unmeasured host with the same parser gap does not
    /// start the app with base64 on screen.
    @Test("The request erases whatever a non-parsing terminal printed")
    func requestTidiesUpAfterItself() {
        let request = TerminalGraphicsQuery.request
        #expect(request.hasPrefix("\u{1B}7"), "the cursor is saved first, by DECSC")
        #expect(request.contains("\u{1B}8\u{1B}[J"), "…restored by DECRC, and the screen wiped from there")
        // Small enough that what a printing host shows fits in a row or two:
        // one pixel, not one image.
        #expect(request.count < 600, "three pixels and twenty-six deflated bytes, and nothing that grows")
    }

    /// Every byte, so a change to any of it is a decision someone made here.
    ///
    /// The save and restore are DECSC and DECRC (`ESC 7`, `ESC 8`), never
    /// SCOSC and SCORC (`CSI s`, `CSI u`): Ghostty's reference reads `CSI s`
    /// as DECSLRM, set the left and right margins, whenever mode 69 is on,
    /// and whether SCORC restores the SGR state is the terminal's choice.
    @Test("The request, byte for byte")
    func requestBytesArePinned() {
        let placement = TerminalGraphicsQuery.probeID
        let compression = TerminalGraphicsQuery.compressionProbeID
        let classic = TerminalGraphicsQuery.classicProbeID
        let playback = TerminalGraphicsQuery.playbackProbeID
        let expected =
            "\u{1B}7"
            + "\u{1B}[B"
            + "\u{1B}[6n"
            + "\u{1B}_Ga=t,q=2,f=32,t=d,s=1,v=1,i=\(placement);AAAAAA==\u{1B}\\"
            + "\u{1B}_Ga=t,q=2,f=32,t=d,s=1,v=1,i=\(classic);AAAAAA==\u{1B}\\"
            + "\u{1B}[6n"
            + "\u{1B}_Ga=p,U=1,q=0,i=\(placement),c=1,r=1\u{1B}\\"
            + "\u{1B}[6n"
            + "\u{1B}_Ga=p,q=0,i=\(classic),p=1,c=1,r=1,z=1\u{1B}\\"
            + "\u{1B}[6n"
            + "\u{1B}_Ga=d,d=I,q=2,i=\(placement)\u{1B}\\"
            + "\u{1B}_Ga=d,d=I,q=2,i=\(classic)\u{1B}\\"
            + "\u{1B}_Ga=t,q=0,f=32,t=d,o=z,s=32,v=32,i=\(compression);"
            + "eJztwQENAAAAwqD3T20PBxQAAADwbhAAAAE=\u{1B}\\"
            + "\u{1B}_Ga=d,d=I,q=2,i=\(compression)\u{1B}\\"
            + "\u{1B}_Ga=t,q=2,f=32,t=d,s=1,v=1,i=\(playback);AAAAAA==\u{1B}\\"
            + "\u{1B}_Ga=f,q=0,f=32,t=d,s=1,v=1,z=40,i=\(playback);AAAAAA==\u{1B}\\"
            + "\u{1B}_Ga=d,d=I,q=2,i=\(playback)\u{1B}\\"
            + "\u{1B}8\u{1B}[J"
            + "\u{1B}[5n"
        #expect(TerminalGraphicsQuery.request == expected)
        #expect(!TerminalGraphicsQuery.request.contains("\u{1B}[s"))
        #expect(!TerminalGraphicsQuery.request.contains("\u{1B}[u"))
    }

    /// Each reply is what `animation_probe.py` read, 2026-11-02, but kitty's, which
    /// is read from its source.
    @Test("Playing frames takes an OK that names the frame it made")
    func playbackNamesTheFrame() {
        let id = TerminalGraphicsQuery.playbackProbeID
        func answered(_ body: String) -> Bool {
            TerminalGraphicsQuery.parse(Array("\u{1B}_G\(body)\u{1B}\\".utf8)).framePlayback
        }
        #expect(answered("i=\(id),r=2;OK"), "Ghostty 1.4.0, and kitty")
        #expect(!answered("i=\(id);OK"), "acknowledging is not adding a frame")
        #expect(!answered("i=\(id);InvalidKittyAction(UnsupportedAction)"), "Warp")
        #expect(!answered("i=\(TerminalGraphicsQuery.probeID),r=2;OK"), "another question's id")
        #expect(!TerminalGraphicsQuery.parse([]).framePlayback, "iTerm2 3.7.6 says nothing")
    }

    @Test("The handshake does not turn playing frames on until someone has seen it draw")
    func playbackOffByDefault() {
        #expect(!TerminalClient.playbackTrustsHandshake)
    }

    @Test("Playing frames: pictures, then the override, the environment, the handshake")
    func playbackLadder() {
        func ladder(pictures: Bool = true, override: Bool? = nil, env: String? = nil, detected: Bool? = nil) -> Bool {
            TerminalClient.graphicsPlaybackSupported(
                pictures: pictures, override: override,
                environment: env.map { ["TUI_GRAPHICS_PLAYBACK": $0] } ?? [:], detected: detected)
        }
        #expect(!ladder(), "nobody asked")
        #expect(ladder(detected: true))
        #expect(!ladder(detected: false))
        #expect(!ladder(env: "0", detected: true), "for a terminal that says so and draws nothing")
        #expect(ladder(env: "1", detected: false))
        #expect(!ladder(override: false, env: "1", detected: true))
        #expect(ladder(override: true, env: "0"))
        #expect(!ladder(pictures: false, override: true, env: "1", detected: true), "no pictures, nothing to play")
    }

    @Test("Only an acknowledged placement counts as support")
    func onlyOKCounts() {
        func answered(_ reply: String) -> Bool {
            TerminalGraphicsQuery.parse(Array(reply.utf8)).placement
        }
        #expect(answered("\u{1B}_Gi=16777215;OK\u{1B}\\"))
        // Ghostty's answer for an image it does not have — the terminal got as
        // far as the lookup, but this exchange transmits first, so reaching
        // ENOENT means something else went wrong. Not support.
        #expect(!answered("\u{1B}_Gi=16777215;ENOENT: image not found\u{1B}\\"))
        // Warp's, verbatim: the protocol is there and the feature is not.
        #expect(
            !answered(
                "\u{1B}_Gi=16777215;InvalidKittyAction(InvalidControlData"
                    + "(UnicodePlaceholderUnsupported))\u{1B}\\"))
        #expect(!answered(""), "silence is a terminal with no protocol at all")
        #expect(!answered("\u{1B}[0n"), "the fence alone is silence")
    }

    /// A reply that merely CONTAINS `OK` is not an acknowledgement — the body
    /// after the semicolon has to be exactly that. Warp's refusal does not
    /// contain the letters, but a future error text could, and a substring
    /// search would read it as success.
    @Test("An error that happens to spell OK is still an error")
    func okMustBeTheWholeBody() {
        #expect(TerminalGraphicsQuery.parse(Array("\u{1B}_Gi=16777215;ENOTOKEN\u{1B}\\".utf8)) == .init())
        #expect(
            TerminalGraphicsQuery.parse(Array("\u{1B}_Gi=16777215;OK is not what I said\u{1B}\\".utf8))
                == .init())
    }

    /// A reply can arrive with the DSR fence, a stray keystroke, or both
    /// around it, so the scan has to find the APC rather than assume the
    /// buffer is one.
    @Test("The answer is found among whatever else arrived")
    func answerIsFoundInASharedBuffer() {
        let buffer = "q\u{1B}_Gi=16777215;OK\u{1B}\\\u{1B}[0n"
        #expect(TerminalGraphicsQuery.parse(Array(buffer.utf8)).placement)
        #expect(TerminalQueryReplies.sawStatusFence(Array(buffer.utf8)))
        #expect(!TerminalQueryReplies.sawStatusFence(Array("\u{1B}_Gi=1;OK\u{1B}\\".utf8)))
    }

    // MARK: - The second question

    @Test("The request also offers a deflated transmission, out loud, under its own id")
    func compressionIsOfferedAndSpoken() {
        let request = TerminalGraphicsQuery.request
        let probe = "a=t,q=0,f=32,t=d,o=z,s=32,v=32,i=\(TerminalGraphicsQuery.compressionProbeID);"
        #expect(request.contains(probe), "the transmission is the question, so it speaks")
        #expect(request.contains("a=d,d=I,q=2,i=\(TerminalGraphicsQuery.compressionProbeID)"), "…and is freed")
        #expect(TerminalGraphicsQuery.compressionProbeID == TerminalGraphicsQuery.probeID - 1)
        #expect(request.count < 600, "twenty-six deflated bytes, base64")
    }

    @Test("Each OK is credited to the id that asked, and an unknown id to nobody")
    func answersAreCreditedById() {
        let placement = "\u{1B}_Gi=\(TerminalGraphicsQuery.probeID);OK\u{1B}\\"
        let compression = "\u{1B}_Gi=\(TerminalGraphicsQuery.compressionProbeID);OK\u{1B}\\"
        let stray = "\u{1B}_Gi=7;OK\u{1B}\\"
        #expect(TerminalGraphicsQuery.parse(Array(placement.utf8)) == .init(placement: true, compression: false))
        #expect(TerminalGraphicsQuery.parse(Array(compression.utf8)) == .init(placement: false, compression: true))
        #expect(TerminalGraphicsQuery.parse(Array((placement + compression).utf8)) == .init(placement: true, compression: true))
        #expect(TerminalGraphicsQuery.parse(Array((compression + placement).utf8)) == .init(placement: true, compression: true))
        #expect(TerminalGraphicsQuery.parse(Array(stray.utf8)) == .init(), "an OK naming neither question answers neither")
        // A host that draws placements and refuses `o=z`, which is the case
        // the split exists for.
        let refused = placement + "\u{1B}_Gi=\(TerminalGraphicsQuery.compressionProbeID);EINVAL:unsupported\u{1B}\\"
        #expect(TerminalGraphicsQuery.parse(Array(refused.utf8)) == .init(placement: true, compression: false))
    }

    // MARK: - The third question, and the cursor

    private let virtualOK = "\u{1B}_Gi=\(TerminalGraphicsQuery.probeID);OK\u{1B}\\"
    private let classicOK = "\u{1B}_Gi=\(TerminalGraphicsQuery.classicProbeID),p=1;OK\u{1B}\\"

    /// `reply`, between the four cursor reports the request asks for, at these
    /// columns of row 3.
    private func answers(columns: [Int], virtual: String = "", classic: String = "") -> TerminalGraphicsQuery.Answers {
        let report = columns.map { "\u{1B}[3;\($0)R" }
        return TerminalGraphicsQuery.parse(
            Array((report[0] + report[1] + virtual + report[2] + classic + report[3] + "\u{1B}[0n").utf8))
    }

    @Test("The classic probe's id is below every strip's")
    func classicProbeIDIsFree() {
        let lowestStrip = HairlineLayer.firstStripID - KittyGraphics.ImageID(HairlineLayer.maximumStrips - 1)
        #expect(TerminalGraphicsQuery.classicProbeID == lowestStrip - 1)
    }

    /// What `classic_placement_probe.py` read, 2026-11-01.
    @Test("Ghostty and iTerm2: a virtual placement stays put, a classic one moves on")
    func aHostWithPlaceholders() {
        let said = answers(columns: [3, 3, 3, 4], virtual: virtualOK, classic: classicOK)
        #expect(said.placement)
        #expect(said.classicPlacement)
    }

    /// Warp's replies verbatim, cursor as measured.
    @Test("Warp refuses the virtual placement by name and takes the classic one")
    func warp() {
        let refused =
            "\u{1B}_Gi=\(TerminalGraphicsQuery.probeID);"
            + "InvalidKittyAction(InvalidControlData(UnicodePlaceholderUnsupported))\u{1B}\\"
        let said = answers(columns: [3, 3, 3, 4], virtual: refused, classic: classicOK)
        #expect(!said.placement)
        #expect(said.classicPlacement)
    }

    /// Konsole reads no `U`, and acknowledges every placement (source read).
    @Test("An OK to a virtual placement that moved the cursor is not a virtual placement")
    func aHostThatDoesNotKnowU() {
        let said = answers(columns: [3, 3, 4, 5], virtual: virtualOK, classic: classicOK)
        #expect(!said.placement)
        #expect(said.classicPlacement)
    }

    /// WezTerm's `a=p` sends no reply at all (source read).
    @Test("A placement that moved the cursor is a placement, answer or none")
    func aHostThatDoesNotAnswer() {
        let said = answers(columns: [3, 3, 4, 5])
        #expect(!said.placement)
        #expect(said.classicPlacement)
    }

    @Test("A cursor moved by a quiet transmission is a host that prints APC, whatever it said")
    func aHostThatPrints() {
        #expect(answers(columns: [3, 60, 90, 120], virtual: virtualOK, classic: classicOK) == .init())
    }

    @Test("A cursor that never moves adds nothing, as under tmux")
    func aHostThatStaysPut() {
        #expect(answers(columns: [3, 3, 3, 3]) == .init())
    }

    /// `CSI 1;m R` is a modified F3, which is why the request leaves row 1 before
    /// it asks (`CursorReportRequestScanTests`).
    @Test("The request leaves row 1 before its first cursor report, so none can be a key")
    func noReportCanBeAKey() throws {
        let request = TerminalGraphicsQuery.request
        let move = try #require(request.range(of: "\u{1B}[B"))
        let report = try #require(request.range(of: "\u{1B}[6n"))
        #expect(move.upperBound <= report.lowerBound)
        #expect(TerminalGraphicsQuery.cursorReports(in: Array("\u{1B}[1;2R".utf8)).isEmpty)
        #expect(TerminalGraphicsQuery.cursorReports(in: Array("\u{1B}[2;2R".utf8)) == [[2, 2]])
        // And so one that arrives after the fence's timeout is not typed.
        #expect(KeyEvent.parse(Array("\u{1B}[1;2R".utf8))?.key == .f3)
        #expect(KeyEvent.parse(Array("\u{1B}[2;2R".utf8))?.key != .f3)
    }

    @Test("A modified F3 among the reports is not one of them")
    func aKeystrokeAmongTheReports() {
        let buffer = "\u{1B}[1;2R\u{1B}[3;3R\u{1B}[3;3R" + virtualOK + "\u{1B}[3;3R" + classicOK + "\u{1B}[3;4R\u{1B}[0n"
        let said = TerminalGraphicsQuery.parse(Array(buffer.utf8))
        #expect(said.placement)
        #expect(said.classicPlacement)
    }

    /// A host that does not answer `CSI 6 n`, or a report cut off by the timeout.
    @Test("A wrong number of reports leaves the acknowledgements to stand")
    func tooFewReports() {
        let buffer = "\u{1B}[3;3R" + virtualOK + "\u{1B}[3;9R\u{1B}[0n"
        #expect(TerminalGraphicsQuery.parse(Array(buffer.utf8)).placement)
    }

    private func keptForTheParser(_ reply: String) -> [UInt8] {
        TerminalQueryReplies.unconsumed(
            Array(reply.utf8), isReply: TerminalGraphicsQuery.isReply, isFence: TerminalQueryReplies.isStatusFence)
    }

    @Test("Cursor reports are this exchange's and go no further, and a key goes to the parser")
    func repliesAndKeys() {
        let reports = "\u{1B}[3;3R\u{1B}[3;3R\u{1B}[3;3R\u{1B}[3;4R"
        #expect(keptForTheParser("q" + reports + "\u{1B}[0nx") == Array("qx".utf8))
        #expect(keptForTheParser("\u{1B}[1;2R" + reports + "\u{1B}[0n") == Array("\u{1B}[1;2R".utf8))
    }
}
