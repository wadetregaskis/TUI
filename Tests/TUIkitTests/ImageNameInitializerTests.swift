//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageNameInitializerTests.swift
//
//  `Label(_:image:)` and `ContentUnavailableView(_:image:description:)` with
//  an image resource's name.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Icons from an image resource's name")
struct ImageNameInitializerTests {

    @Test("A label's image icon takes the two cells a symbol takes, before its title")
    func labelIconIsGlyphSized() {
        let harness = InputChainHarness(width: 20, height: 1)
        let line = harness.frame(Label("Gear", image: "tuikit-test-missing-image")).lines.first?.stripped ?? ""
        // Two cells of icon, the label's gap, then the title.
        #expect(line.hasSuffix("Gear") || line.contains(" Gear"), "\(line.debugDescription)")
        let titleColumn = line.distance(from: line.startIndex, to: line.range(of: "Gear")!.lowerBound)
        #expect(titleColumn == 3, "\(line.debugDescription)")
    }

    @Test("The icon names the image the bundle initialiser would")
    func iconImageIsTheNamedResource() {
        let label = Label("Gear", image: "gear")
        #expect(label.icon.image == Image("gear"))
    }
}
