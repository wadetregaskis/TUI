//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusableFocusTintTests.swift
//
//  A focused `.focusable()` view draws the standard focus tint behind its
//  cells — the owner's ruling A-FOCUSABLE-1 (b), 2026-11-20, TUI's rendering
//  of the focus ring SwiftUI draws round one on macOS. Until then the view
//  took Tab and the keys and looked exactly as it did unfocused.
//
//  Every case compares the subject focused with the same subject unfocused —
//  the focus parked on a sibling button by a real focus manager — so a case
//  that passes is about the focus, not about the arrangement.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITerminalHost
@testable import TUITestSupport

@MainActor
@Suite("A focused .focusable() view draws the focus tint behind its cells")
struct FocusableFocusTintTests {

    /// The word every subject draws, so a cell's state can be read back where it starts.
    private static let word = "hello"

    /// What a frame shows on the subject's row: the line, and the runs on it that animate.
    private struct Row {
        let line: String
        let runs: [AnimatedCellRun]
    }

    /// `subject` above a sibling button, rendered three frames with the services a
    /// breath needs, and the row that shows `word`. The subject is the first stop, so a
    /// fresh manager focuses it; `onSibling` moves the focus to the last stop
    /// registered, the sibling, after the first frame, which is the genuinely unfocused
    /// baseline. `pick` instead names the stop to focus among those registered, in ring
    /// order.
    private func render(
        _ subject: some View, onSibling: Bool = false, pick: (([String]) -> String?)? = nil,
        differentiatesWithoutColor: Bool = false, word: String = word,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> Row {
        let context = makeRenderContext(width: 30, height: 8) { environment, _ in
            environment.animationScheduler = AnimationScheduler()
            environment.volatileReadTracker = VolatileReadTracker()
            environment._accessibilityDifferentiateWithoutColor = differentiatesWithoutColor
        }
        let view = VStack(alignment: .leading, spacing: 0) {
            subject
            Button("sibling") {}
        }
        var buffer = FrameBuffer()
        for frame in 0..<3 {
            if frame == 1, let manager = context.environment.focusManager {
                let ids = manager.registeredFocusIDsInActiveSection()
                if let id = onSibling ? ids.last : pick?(ids) { manager.focus(id: id) }
            }
            let scheduler = context.environment.animationScheduler
            scheduler?.beginFrame()
            context.stateStorage?.beginRenderPass()
            context.environment.focusManager?.beginRenderPass()
            buffer = renderToBuffer(view, context: context)
            context.environment.focusManager?.endRenderPass()
            context.stateStorage?.endRenderPass()
            scheduler?.endFrame()
        }
        let row = try #require(
            buffer.lines.firstIndex { $0.stripped.contains(word) }, "no \(word) in \(buffer.lines)",
            sourceLocation: sourceLocation)
        return Row(line: buffer.lines[row], runs: buffer.animatedCells.filter { $0.offsetY == row && $0.isAnimating })
    }

    /// The SGR state in force on the first cell of `word`, in `line`.
    private func state(of word: String = word, in line: String) throws -> SGRState {
        try #require(sgrState(of: word, in: [line]), "no \(word) in \(line.debugDescription)")
    }

    private var palette: any Palette { EnvironmentValues().palette }

    @Test("Focused, it breathes the focus wash behind its cells; unfocused, it draws nothing")
    func focusedBreathesAndUnfocusedDoesNot() throws {
        try withColorDepth(.truecolor) {
            let subject = Text(Self.word).focusable()
            let focused = try render(subject)
            let unfocused = try render(subject, onSibling: true)
            let bare = try render(Text(Self.word), onSibling: true)

            // Unfocused: exactly the view without the modifier, and nothing breathing.
            #expect(unfocused.line == bare.line)
            #expect(unfocused.runs.isEmpty)

            // Focused: the same cells, on a field of their own, breathing.
            #expect(focused.line.stripped == unfocused.line.stripped)
            #expect(focused.line != unfocused.line, "no tint behind the focused view")
            let run = try #require(focused.runs.first, "the focused view does not breathe")
            #expect(run.offsetX == 0 && run.width == Self.word.count, "the tint covers \(run.width) cells")
            let grounds = try run.frames.map { try state(in: $0).renderedBackground }
            #expect(Set(grounds).count > 1, "every point of the pulse is one colour: \(Set(grounds))")
            // In the focus wash a list's cursor row breathes: one focus identity.
            let wash = palette.focusWashPulse()
            #expect(grounds.contains(renderedBackground(of: wash.dim)), "\(Set(grounds))")
            #expect(grounds.contains(renderedBackground(of: wash.bright)), "\(Set(grounds))")
        }
    }

    @Test("focusEffectDisabled() outside the modifier takes the tint away")
    func focusEffectDisabledRemovesIt() throws {
        try withColorDepth(.truecolor) {
            let subject = Text(Self.word).focusable().focusEffectDisabled()
            let disabled = try render(subject)
            let unfocused = try render(subject, onSibling: true)
            #expect(disabled.line == unfocused.line)
            #expect(disabled.runs.isEmpty)
        }
    }

    @Test("A cell that paints its own background keeps it at every point of the breath")
    func ownBackgroundShowsThrough() throws {
        try withColorDepth(.truecolor) {
            let subject = HStack(spacing: 0) {
                Text("A").background(Color.red)
                Text(Self.word)
            }.focusable()
            let run = try #require(try render(subject).runs.first, "the focused view does not breathe")
            let red = renderedBackground(of: .red)
            for frame in run.frames {
                let own = try state(of: "A", in: frame).renderedBackground
                let tinted = try state(in: frame).renderedBackground
                #expect(own == red)
                #expect(tinted != red)
            }
        }
    }

    /// A `.focusable()` around a control is two stops. The focus is drawn once
    /// whichever holds it: the wrapper's tint with the button unfocused, or the
    /// button's own focus with no tint.
    @Test("Around a Button, the focus is drawn once, by whichever stop holds it")
    func aButtonInsideIsNotDoubled() throws {
        try withColorDepth(.truecolor) {
            let wrapped = HStack { Button(Self.word) {} }.focusable()
            // The button's own stop, the second in the ring, holds the focus: the
            // picture is the button focused without the wrapper.
            let onButton = try render(wrapped, pick: { $0.dropFirst().first })
            let bare = try render(HStack { Button(Self.word) {} })
            #expect(onButton.line == bare.line)
            let wrappedFrames = onButton.runs.map(\.frames)
            let bareFrames = bare.runs.map(\.frames)
            #expect(wrappedFrames == bareFrames, "the wrapper drew a focus the button draws")

            // The wrapper's stop holds it: the tint, behind a button drawn unfocused.
            let onWrapper = try render(wrapped)
            let unfocusedButton = try render(HStack { Button(Self.word) {} }, onSibling: true)
            #expect(onWrapper.line.stripped == unfocusedButton.line.stripped)
            #expect(!onWrapper.runs.isEmpty, "the focused wrapper does not breathe")
        }
    }

    @Test("Without colour the tint is reverse video, breathing by weight where the host draws bold")
    func noColourReverses() throws {
        try withColorDepth(.noColor) {
            let subject = Text(Self.word).focusable()
            try TerminalClient.$drawsBoldPin.withValue(true) {
                let focused = try render(subject)
                let run = try #require(focused.runs.first, "the focused view does not breathe")
                let states = try run.frames.map { try state(in: $0) }
                // Read out before the expectations: a key path handed to a
                // rethrowing call inside `#expect` does not compile.
                let reversed = states.map(\.reversesVideo)
                let bold = Set(states.map(\.isBold))
                #expect(!reversed.contains(false))
                #expect(bold == [true, false])
                let unfocused = try state(in: render(subject, onSibling: true).line)
                #expect(!unfocused.reversesVideo)
            }
            try TerminalClient.$drawsBoldPin.withValue(false) {
                let focused = try render(subject)
                let drawn = try state(in: focused.line)
                #expect(focused.runs.isEmpty)
                #expect(drawn.reversesVideo)
            }
        }
    }

    @Test("Under Differentiate Without Color the tint is reverse video over the colours, still")
    func differentiateWithoutColorReverses() throws {
        try withColorDepth(.truecolor) {
            let subject = Text(Self.word).focusable()
            let focused = try render(subject, differentiatesWithoutColor: true)
            let drawn = try state(in: focused.line)
            let unfocused = try state(in: render(subject, onSibling: true, differentiatesWithoutColor: true).line)
            #expect(drawn.reversesVideo)
            #expect(focused.runs.isEmpty)
            #expect(!unfocused.reversesVideo)
        }
    }

    @Test("In a view that does not appear active the tint stays, still, in the plain wash")
    func inactiveHoldsStill() throws {
        try withColorDepth(.truecolor) {
            let subject = Text(Self.word).focusable().environment(\.appearsActive, false)
            let held = try render(subject)
            let drawn = try state(in: held.line)
            #expect(held.runs.isEmpty, "the tint breathes in an inactive window")
            let fill = palette.focusWashEmphasis(appearsActive: false)
            guard case .fill(let wash) = fill else {
                Issue.record("the default palette's held wash is \(fill), not a fill")
                return
            }
            #expect(drawn.renderedBackground == renderedBackground(of: wash))
        }
    }

    // MARK: - The documented ways to draw a look of your own (FocusSystem.md)

    /// "Your own focus look", the recommended way: `@FocusState` in the view
    /// that owns the state, the tint turned off.
    private struct Tile: View {
        let title: String
        @FocusState private var isFocused: Bool

        var body: some View {
            Text(title)
                .padding(.horizontal, 1)
                .border(isFocused ? .palette.accent : .palette.border)
                .focusable()
                .focused($isFocused)
                .focusEffectDisabled()
        }
    }

    /// The right way to read `\.isFocused`: from the focusable's content.
    private struct TileFace: View {
        let title: String
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            Text(title).bold(isFocused)
        }
    }

    private struct Launcher: View {
        var body: some View {
            TileFace(title: FocusableFocusTintTests.word)
                .focusable()
                .focusEffectDisabled()
        }
    }

    /// The wrong way: `\.isFocused` read above the view's own `.focusable()`.
    private struct BrokenTile: View {
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            Text(FocusableFocusTintTests.word)
                .bold(isFocused)
                .focusable()
        }
    }

    /// Breathing in step with the built-ins, through `\.selectionEmphasis`.
    private struct BreathingTileFace: View {
        @Environment(\.isFocused) private var isFocused
        @Environment(\.selectionEmphasis) private var emphasis
        @Environment(\.palette) private var palette

        var body: some View {
            Text(FocusableFocusTintTests.word)
                .border(emphasis.animatedColor(isFocused, dim: palette.border, bright: palette.accent))
        }
    }

    @Test("The documented custom looks draw as the article says")
    func documentedCustomLooks() throws {
        try withColorDepth(.truecolor) {
            // @FocusState: the border changes, and no tint is drawn behind the title.
            let tile = try render(Tile(title: Self.word))
            let tileOff = try render(Tile(title: Self.word), onSibling: true)
            let tileGround = try state(in: tile.line).renderedBackground
            let tileOffGround = try state(in: tileOff.line).renderedBackground
            #expect(tile.line != tileOff.line, "the tile's own look does not show its focus")
            #expect(tileGround == tileOffGround)

            // \.isFocused read below the modifier: bold while focused.
            let face = try state(in: render(Launcher()).line)
            let faceOff = try state(in: render(Launcher(), onSibling: true).line)
            #expect(face.isBold)
            #expect(!faceOff.isBold)

            // \.isFocused read above it: never bold.
            let broken = try state(in: render(BrokenTile()).line)
            #expect(!broken.isBold)

            // selectionEmphasis: the border breathes while focused, and is still while not.
            let breathing = BreathingTileFace().focusable().focusEffectDisabled()
            let breathes = try render(breathing).runs
            let rests = try render(breathing, onSibling: true).runs
            #expect(!breathes.isEmpty, "the border does not breathe")
            #expect(rests.isEmpty)
        }
    }
}
