//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalGraphicsQueryTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

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
        #expect(request.count < 300, "one pixel and twenty-six deflated bytes, and nothing that grows")
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
        let expected =
            "\u{1B}7"
            + "\u{1B}_Ga=t,q=2,f=32,t=d,s=1,v=1,i=\(placement);AAAAAA==\u{1B}\\"
            + "\u{1B}_Ga=p,U=1,q=0,i=\(placement),c=1,r=1\u{1B}\\"
            + "\u{1B}_Ga=d,d=I,q=2,i=\(placement)\u{1B}\\"
            + "\u{1B}_Ga=t,q=0,f=32,t=d,o=z,s=32,v=32,i=\(compression);"
            + "eJztwQENAAAAwqD3T20PBxQAAADwbhAAAAE=\u{1B}\\"
            + "\u{1B}_Ga=d,d=I,q=2,i=\(compression)\u{1B}\\"
            + "\u{1B}8\u{1B}[J"
            + "\u{1B}[5n"
        #expect(TerminalGraphicsQuery.request == expected)
        #expect(!TerminalGraphicsQuery.request.contains("\u{1B}[s"))
        #expect(!TerminalGraphicsQuery.request.contains("\u{1B}[u"))
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
        #expect(request.count < 300, "twenty-six deflated bytes, base64")
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
}
