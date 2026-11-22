//  🖥️ TUI — A Terminal UI framework for Swift
//  ReplayedNestedFadeTests.swift
//
//  A claim of its own inside a repeating `.opacity` fade breathes with the fade.
//  The fade replays as runs cut from its rows as rebuilt at each phase
//  (`FrameBuffer.cyclingRuns`), and the rebuild took a cell's layer from the
//  first claim covering it: the inner one, which held the render's static value
//  at every phase. So `Text("b").opacity(0.5)` inside a breathing `VStack` stood
//  still while `Text("a")` beside it breathed, and moved only when something else
//  rendered (hunt 11-20, H-14). `.opacity(1)` is a claim as well ("fully opaque
//  is NOT the identity"), and a layer `.offset` displaces is faded by the same
//  function, so both are walked: on the page, where a claim at 1 is dropped
//  over nothing and only the other two froze, and over a block of colour.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// Two rows breathing together, the second with a fade of its own, on the page
/// or over a block of colour.
private struct BreathingPair: View {
    let shape: ReplayedNestedFadeTests.Shape
    let ground: ReplayedNestedFadeTests.Ground
    @State private var dim = false

    var body: some View {
        switch ground {
        case .page: pair
        case .block: ZStack(alignment: .topLeading) { Color.rgb(30, 40, 120); pair }
        }
    }

    private var pair: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("a breathes")
            switch shape {
            case .halfFaded: Text("b at half").opacity(0.5)
            case .opaque: Text("b at full").opacity(1)
            case .anchored: Text("b offset").opacity(0.5).offset(x: 2)
            }
        }
        .opacity(dim ? 0.3 : 1)
        .onAppear {
            withAnimation(.linear(duration: 0.4).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}

private struct BreathingPairApp: App {
    let shape: ReplayedNestedFadeTests.Shape
    let ground: ReplayedNestedFadeTests.Ground
    init() { (shape, ground) = (.halfFaded, .page) }
    init(_ shape: ReplayedNestedFadeTests.Shape, on ground: ReplayedNestedFadeTests.Ground) {
        (self.shape, self.ground) = (shape, ground)
    }

    var body: some Scene {
        WindowGroup {
            BreathingPair(shape: shape, ground: ground).palette(SystemPalette(.green))
        }
    }
}

@MainActor
@Suite("A claim inside a repeating fade breathes with it")
struct ReplayedNestedFadeTests {

    enum Shape: String, CaseIterable, Sendable {
        /// `Text("b").opacity(0.5)` in flow.
        case halfFaded
        /// `Text("b").opacity(1)`, a claim at full strength.
        case opaque
        /// `Text("b").opacity(0.5).offset(x: 2)`: an anchored layer.
        case anchored
    }

    enum Ground: String, CaseIterable, Sendable {
        /// The page: a claim at full strength is dropped there, over nothing.
        case page
        /// A block of colour under the fade, where a claim at 1 is kept.
        case block
    }

    @Test("Every tick shows what a render at that instant draws", arguments: Shape.allCases, Ground.allCases)
    func everyTickMatchesARender(shape: Shape, ground: Ground) {
        let found = TerminalColors.withCurrent(.unknown) {
            ReplayOracle.compare(
                { BreathingPairApp(shape, on: ground) }, ticks: 24, size: (30, 4), reportOncePerRow: true)
        }
        for mismatch in found.mismatches { Issue.record("\(shape) on \(ground): \(mismatch)") }
        // The whole cycle: 0.4 s each way is 24 steps of 50 ms.
        #expect(found.compared >= 24, "\(shape) on \(ground): only \(found.compared) rows were replayed")
    }

    /// The fade's cycle reaches a claim inside it as the fade's own phases times
    /// the claim's alpha, and the phases are the fade's array, not a copy: a ramp
    /// inside a breath claims per cell, and a copy each would be an array per
    /// claim per render and an array walk per `OpacityRegion ==`.
    @Test("A claim inside a repeating fade shares its phases, times its own alpha")
    func aClaimInsideSharesThePhases() throws {
        let phases = [1.0, 0.6, 0.3]
        let inner = OpacityRegion(offsetX: 0, offsetY: 1, width: 2, height: 1, opacity: 0.5)
        let faded = OpacityFading.fading(
            [inner], by: 1, cycle: OpacityCycle(phases: phases, clock: .content),
            wholeOf: FrameBuffer(lines: ["ab", "cd"]), appendingRectangle: true)
        let claim = try #require(faded.first?.cycle)
        #expect((0..<3).map(claim.phase(atStep:)) == [0.5, 0.3, 0.15])
        #expect(faded.first?.opacity == 0.5)
        #expect(faded.last?.cycle?.phase(atStep: 1) == 0.6)
        let address = { (array: [Double]) in array.withUnsafeBufferPointer { Int(bitPattern: $0.baseAddress) } }
        #expect(address(claim.phases) == address(phases))
    }
}
