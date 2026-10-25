//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalCapabilitiesTests.swift
//
//  `TerminalCapabilities` (decisions TERMCAPS-API): a feature's three states
//  and how each source of answers settles them — the table of terminals, the
//  keyboard negotiation, a switch, a key the person pressed — the group
//  constants, `supports` and `supportsAny`, and the colour depth passed
//  through.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTerminalHost

private typealias Feature = TerminalCapabilities.Feature

@Suite("What the terminal can do, feature by feature")
struct TerminalCapabilitiesTests {
    /// Every member, one by one, as the type declares them.
    private static let members: [Feature] = [
        .doubleUnderline, .curlyUnderline, .dottedUnderline, .dashedUnderline, .underlineColor, .strikethrough,
        .strikethroughColor, .pictures, .hyperlinks, .clipboardWrites, .notifications, .progressReports,
        .pointerShapes, .disambiguatedKeys, .shiftedKeys, .keyRepeats, .keyReleases, .modifierKeys, .capsLock,
        .numericPad, .optionAsMeta,
    ]

    // MARK: The three states

    @Test("With nothing asked, every feature is undetermined, and nothing is supported")
    func nothingKnownIsUndetermined() {
        let known = TerminalCapabilities.nothingKnown
        #expect(known.undetermined == Feature.all)
        for member in Self.members {
            #expect(known.status(of: member) == .undetermined)
        }
        #expect(!known.supports(.hyperlinks))
        #expect(!known.supportsAny(of: .keyboard))
    }

    @Test("A feature settles from undetermined, and can settle again")
    func settlingMovesAFeature() {
        let start = TerminalCapabilities.nothingKnown
        let supported = start.settling(.keyReleases, as: .supported)
        #expect(supported.status(of: .keyReleases) == .supported)
        #expect(supported.status(of: .keyRepeats) == .undetermined, "the rest kept")
        let unsupported = supported.settling(.keyReleases, as: .unsupported)
        #expect(unsupported.status(of: .keyReleases) == .unsupported)
        #expect(!unsupported.supported.contains(.keyReleases))
        let unsettled = unsupported.settling(.keyReleases, as: .undetermined)
        #expect(unsettled == start)
    }

    @Test("One source's answers are taken for its own features alone")
    func settlingFromAnother() {
        let mine = TerminalCapabilities.nothingKnown.settling(.hyperlinks, as: .supported)
        let theirs = TerminalCapabilities.nothingKnown
            .settling([.keyReleases, .hyperlinks], as: .unsupported)
        let merged = mine.settling(.keyReleases, from: theirs)
        #expect(merged.status(of: .keyReleases) == .unsupported)
        #expect(merged.status(of: .hyperlinks) == .supported)
    }

    @Test("A feature named both supported and unsupported is supported")
    func supportedWinsAnOverlap() {
        let known = TerminalCapabilities(supported: .pictures, unsupported: [.pictures, .hyperlinks])
        #expect(known.status(of: .pictures) == .supported)
        #expect(known.unsupported == .hyperlinks)
    }

    // MARK: Groups

    @Test("Every member is one feature of its own, and the groups divide them")
    func membersAndGroups() {
        for member in Self.members {
            #expect(member.rawValue.nonzeroBitCount == 1, "\(member.rawValue)")
        }
        #expect(Set(Self.members.map(\.rawValue)).count == Self.members.count)
        #expect(Feature(Self.members) == Feature.all)
        #expect(Feature.patternedUnderline == [.curlyUnderline, .dottedUnderline, .dashedUnderline])
        #expect(Feature.textDecorations.isSuperset(of: .patternedUnderline))
        let groups: [Feature] = [.textDecorations, .pictures, .hostIntegration, .keyboard]
        #expect(groups.map(\.rawValue.nonzeroBitCount).reduce(0, +) == Self.members.count, "no member in two")
        #expect(Feature(groups) == Feature.all)
        #expect(Feature.keyboard.contains(.optionAsMeta))
        #expect(TerminalCapabilities.negotiatedKeyboard == Feature.keyboard.subtracting(.optionAsMeta))
    }

    @Test("A group's status is its members' when they agree, and undetermined when they do not")
    func groupStatus() {
        let all = TerminalCapabilities.nothingKnown.settling(.patternedUnderline, as: .supported)
        #expect(all.status(of: .patternedUnderline) == .supported)
        let none = TerminalCapabilities.nothingKnown.settling(.patternedUnderline, as: .unsupported)
        #expect(none.status(of: .patternedUnderline) == .unsupported)
        let mixed = all.settling(.dashedUnderline, as: .unsupported)
        #expect(mixed.status(of: .patternedUnderline) == .undetermined)
        let partial = TerminalCapabilities.nothingKnown.settling(.curlyUnderline, as: .supported)
        #expect(partial.status(of: .patternedUnderline) == .undetermined)
    }

    @Test("supports(_:) wants every member supported; supportsAny(of:) one")
    func supportsAndSupportsAny() {
        let known = TerminalCapabilities.nothingKnown
            .settling([.curlyUnderline, .dottedUnderline], as: .supported)
            .settling(.dashedUnderline, as: .unsupported)
        #expect(known.supports(.curlyUnderline))
        #expect(known.supports([.curlyUnderline, .dottedUnderline]))
        #expect(!known.supports(.patternedUnderline), "one member unsupported")
        #expect(known.supportsAny(of: .patternedUnderline))
        #expect(!known.supportsAny(of: [.dashedUnderline, .doubleUnderline]), "unsupported and undetermined")
        #expect(known.supports([]), "nothing asked is nothing missing")
        #expect(!known.supportsAny(of: []))
    }

    // MARK: Colour depth

    @Test("The colour depth is ColorDepth.current, read as it is asked for", arguments: [
        ColorDepth.basic16, .palette256, .truecolor,
    ])
    func colorDepthPassesThrough(depth: ColorDepth) {
        ColorDepth.withCurrent(depth) {
            #expect(TerminalCapabilities.nothingKnown.colorDepth == depth)
            #expect(TerminalCapabilities.nothingKnown.colorDepth == ColorDepth.current)
        }
    }

    // MARK: The table of terminals

    @Test("The text decorations follow the measured line styles, and only on the terminals read")
    func textDecorationsFollowTheTable() {
        for program in TerminalClient.Program.allCases {
            let known = TerminalCapabilities.textDecorations(of: program)
            #expect(known.undetermined.isSuperset(of: Feature.all.subtracting(.textDecorations)))
            switch program {
            case .appleTerminal, .iTerm2, .ghostty, .warp:
                // As the renderer reduces a style by, so the two cannot disagree.
                let styles = TerminalHost.lineStyles(for: program)
                #expect(known.supports(.doubleUnderline) == styles.doubleUnderline)
                #expect(known.supports(.patternedUnderline) == styles.patternedUnderlines)
                #expect(known.supports(.underlineColor) == styles.underlineColour)
                #expect(known.supports(.strikethroughColor) == styles.strikethroughColour)
                #expect(known.undetermined.isDisjoint(with: .textDecorations), "\(program)")
            case .gnomeTerminal, .tmux, .unidentified:
                #expect(known == .nothingKnown, "\(program)")
            }
        }
        #expect(TerminalCapabilities.textDecorations(of: .appleTerminal).status(of: .strikethrough) == .unsupported)
        #expect(TerminalCapabilities.textDecorations(of: .warp).status(of: .strikethrough) == .supported)
        #expect(TerminalCapabilities.textDecorations(of: .warp).status(of: .patternedUnderline) == .unsupported)
        #expect(TerminalCapabilities.textDecorations(of: .ghostty).status(of: .strikethroughColor) == .unsupported)
        #expect(TerminalCapabilities.textDecorations(of: .iTerm2).supports(.textDecorations))
    }

    @Test(
        "A switch settles a feature anywhere; a table only where it reaches",
        arguments: [
            // uses, forced, evidence, status
            (true, true, .unidentified, .supported),
            (false, true, .unidentified, .unsupported),
            (false, true, .unknown, .unsupported),
            (true, false, .known, .supported),
            (false, false, .known, .unsupported),
            (true, false, .unknown, .undetermined),
            (false, false, .unknown, .undetermined),
            (true, false, .unidentified, .supported),
            (false, false, .unidentified, .undetermined),
        ] as [(Bool, Bool, TerminalCapabilities.HostEvidence, TerminalCapabilities.Status)])
    func ladderStatus(
        uses: Bool, forced: Bool, evidence: TerminalCapabilities.HostEvidence, status: TerminalCapabilities.Status
    ) {
        #expect(TerminalCapabilities.status(uses: uses, forced: forced, evidence: evidence) == status)
    }

    @Test("An app's override or a TUIKIT_ switch of 1 or 0 forces a feature; anything else does not")
    func forcing() {
        #expect(TerminalCapabilities.isForced(override: false, variable: "TUIKIT_X", in: [:]))
        #expect(TerminalCapabilities.isForced(override: nil, variable: "TUIKIT_X", in: ["TUIKIT_X": "1"]))
        #expect(TerminalCapabilities.isForced(override: nil, variable: "TUIKIT_X", in: ["TUIKIT_X": "0"]))
        #expect(!TerminalCapabilities.isForced(override: nil, variable: "TUIKIT_X", in: ["TUIKIT_X": "yes"]))
        #expect(!TerminalCapabilities.isForced(override: nil, variable: "TUIKIT_X", in: ["TUIKIT_Y": "1"]))
    }

    // MARK: The keyboard negotiation

    @Test("The keyboard negotiation settles its seven features, and leaves Option as Meta to the keys")
    func keyboardNegotiation() {
        let legacy = TerminalCapabilities.keyboard(.legacy)
        #expect(legacy.unsupported == TerminalCapabilities.negotiatedKeyboard)
        #expect(legacy.status(of: .optionAsMeta) == .undetermined)

        let everything = TerminalCapabilities.keyboard(
            KeyboardReporting(flags: [
                .disambiguateEscapeCodes, .reportEventTypes, .reportAlternateKeys, .reportAllKeysAsEscapeCodes,
                .reportAssociatedText,
            ]))
        #expect(everything.supported == TerminalCapabilities.negotiatedKeyboard)

        // Flags 1 and 2 only: releases and repeats, no modifier keys alone.
        let some = TerminalCapabilities.keyboard(
            KeyboardReporting(flags: [.disambiguateEscapeCodes, .reportEventTypes]))
        #expect(some.supports([.disambiguatedKeys, .keyRepeats, .keyReleases]))
        #expect(some.status(of: .modifierKeys) == .unsupported)
        #expect(some.status(of: .capsLock) == .unsupported)
    }

    @Test(
        "Read back from the capabilities, the keyboard is the one the negotiation reported",
        arguments: [
            KittyKeyboardFlags(), .requested, [.disambiguateEscapeCodes], [.disambiguateEscapeCodes, .reportEventTypes],
            [.disambiguateEscapeCodes, .reportAlternateKeys], [.reportAllKeysAsEscapeCodes],
        ])
    func keyboardReadBack(flags: KittyKeyboardFlags) {
        let reporting = KeyboardReporting(flags: flags)
        #expect(KeyboardReporting(TerminalCapabilities.keyboard(reporting)) == reporting)
    }

    @Test("Nothing known reads as the legacy keyboard")
    func nothingKnownIsLegacy() {
        #expect(KeyboardReporting(TerminalCapabilities.nothingKnown) == .legacy)
    }

    @Test("An undo hint follows the keyboard the capabilities report")
    func undoHintFollowsCapabilities() {
        let shortcuts = UndoShortcuts.default
        let legacy = TerminalCapabilities.keyboard(.legacy)
        let kitty = TerminalCapabilities.keyboard(KeyboardReporting(flags: .requested))
        // Ctrl-Shift-Z arrives as Ctrl-Z in a legacy encoding, so redo is
        // named by Ctrl-Y, which every terminal sends (FB9-REDO).
        #expect(shortcuts.hint(for: .undo, on: legacy) == "⌃Z")
        #expect(shortcuts.hint(for: .redo, on: legacy) == "⌃Y")
        #expect(shortcuts.hint(for: .redo, on: kitty) == "⌃⇧Z")
        #expect(shortcuts.hint(for: .redo, on: .nothingKnown) == "⌃Y")
    }

    // MARK: What a key shows

    @Test(
        "An Option chord on a printable key shows Option is sent as Meta",
        arguments: [
            KeyEvent(key: .character("x"), alt: true),
            KeyEvent(key: .character("X"), alt: true, shift: true),
            KeyEvent(key: .character("B"), alt: true, shift: true),
            KeyEvent(key: .character("a"), ctrl: true, alt: true),
            KeyEvent(key: .character("."), alt: true),
            KeyEvent(key: .character("1"), alt: true, phase: .repeat),
        ])
    func optionChordSettlesOptionAsMeta(event: KeyEvent) throws {
        let learnt = try #require(TerminalCapabilities.nothingKnown.observing(event))
        #expect(learnt.status(of: .optionAsMeta) == .supported)
        #expect(learnt.supported == .optionAsMeta, "nothing else learnt")
        #expect(learnt.observing(event) == nil, "settled once")
    }

    @Test(
        "Nothing else shows it: a plain key, a composed one, ⌥←'s Emacs keys, a ⌘ chord, a release",
        arguments: [
            KeyEvent(key: .character("x")),
            KeyEvent(key: .character("≈")),
            KeyEvent(key: .character("å"), alt: true),
            KeyEvent(key: .character("b"), alt: true),
            KeyEvent(key: .character("d"), alt: true),
            KeyEvent(key: .character("f"), alt: true),
            KeyEvent(key: .character(" "), alt: true),
            KeyEvent(key: .left, alt: true),
            KeyEvent(key: .character("k"), alt: true, command: true),
            KeyEvent(key: .character("x"), alt: true, phase: .release),
        ])
    func otherKeysShowNothing(event: KeyEvent) {
        #expect(TerminalCapabilities.nothingKnown.observing(event) == nil)
    }

    // MARK: The environment

    @Test("Outside a running app the environment knows nothing")
    func environmentDefault() {
        #expect(EnvironmentValues().terminalCapabilities == .nothingKnown)
    }
}
