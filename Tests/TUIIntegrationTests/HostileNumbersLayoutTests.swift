//  🖥️ TUI — A Terminal UI framework for Swift
//  HostileNumbersLayoutTests.swift
//
//  Frames, padding, offsets, stacks, spacers and every other modifier that
//  takes a length in cells, handed negative and enormous lengths: each must
//  draw without trapping or hanging. See HostileNumbersSupport.swift.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Hostile numbers: layout")
struct HostileNumbersLayoutTests {

    @Test("A fixed frame of any length draws", arguments: Hostile.ints)
    func fixedFrame(length: Int) {
        drawHostile(Text("frame").frame(width: length, height: 3))
        drawHostile(Text("frame").frame(width: 7, height: length))
        drawHostile(Text("frame").frame(width: length))
        drawHostile(Text("frame").frame(height: length))
    }

    @Test("A flexible frame of any bounds draws", arguments: Hostile.ints)
    func flexibleFrame(length: Int) {
        drawHostile(Text("frame").frame(minWidth: length))
        drawHostile(Text("frame").frame(minHeight: length))
        drawHostile(Text("frame").frame(idealWidth: length, idealHeight: 2).fixedSize())
        drawHostile(Text("frame").frame(idealWidth: 2, idealHeight: length).fixedSize())
        drawHostile(Text("frame").frame(maxWidth: .fixed(length), maxHeight: .fixed(length)))
        drawHostile(Text("frame").frame(minWidth: length, idealWidth: length, maxWidth: .infinity))
        drawHostile(Text("frame").frame(minHeight: length, idealHeight: length, maxHeight: .infinity))
        drawHostile(Text("frame").frame(minWidth: 5, maxWidth: .fixed(length)))
    }

    @Test("Padding of any length draws", arguments: Hostile.ints)
    func padding(length: Int) {
        drawHostile(Text("pad").padding(.horizontal, length))
        drawHostile(Text("pad").padding(.vertical, length))
        drawHostile(Text("pad").padding(EdgeInsets(top: 1, leading: length, bottom: 1, trailing: length)))
        drawHostile(Text("pad").padding(EdgeInsets(top: length, leading: 1, bottom: length, trailing: 1)))
        drawHostile(Text("pad").safeAreaPadding(.horizontal, length))
        drawHostile(Text("pad").safeAreaPadding(.top, length))
    }

    @Test("An offset or a position of any distance draws", arguments: Hostile.ints)
    func offsetAndPosition(distance: Int) {
        drawHostile(Text("offset").offset(x: distance, y: distance))
        drawHostile(Text("position").position(x: distance, y: distance))
        drawHostile(VStack { Text("a"); Text("b").offset(x: distance) })
    }

    @Test("Stacks and spacers of any spacing draw", arguments: Hostile.ints)
    func stacks(spacing: Int) {
        drawHostile(VStack(spacing: spacing) { Text("a"); Text("b") })
        drawHostile(HStack(spacing: spacing) { Text("a"); Text("b") })
        drawHostile(HStack { Text("a"); Spacer(minLength: spacing); Text("b") })
        drawHostile(VStack { Text("a"); Spacer(minLength: spacing); Text("b") })
        drawHostile(ZStack { Text("a"); Text("b") }.padding(.vertical, spacing))
    }

    @Test("Line limits and line spacing of any count draw", arguments: Hostile.ints)
    func lines(count: Int) {
        let text = Text("one two three four five six seven eight nine ten")
        drawHostile(text.lineLimit(count))
        drawHostile(text.lineLimit(count, reservesSpace: true))
        drawHostile(text.lineSpacing(count))
        if count >= 0 {
            drawHostile(text.lineLimit(count...))
            drawHostile(text.lineLimit(...count))
        }
    }

    @Test("Layout priority, z-index and aspect ratio of any value draw", arguments: Hostile.doubles)
    func priorities(value: Double) {
        drawHostile(HStack { Text("a").layoutPriority(value); Text("b") })
        drawHostile(ZStack { Text("a").zIndex(value); Text("b") })
        drawHostile(Color.red.aspectRatio(value, contentMode: .fit))
        drawHostile(Color.red.aspectRatio(value, contentMode: .fill))
    }

    @Test("A container-relative frame of any division draws", arguments: Hostile.ints)
    func containerRelative(value: Int) {
        drawHostile(Text("c").containerRelativeFrame(.horizontal, count: value, span: 1, spacing: 0))
        drawHostile(Text("c").containerRelativeFrame(.horizontal, count: 3, span: value, spacing: 0))
        drawHostile(Text("c").containerRelativeFrame([.horizontal, .vertical], count: 3, span: 1, spacing: value))
        drawHostile(Text("c").containerRelativeFrame(.horizontal) { _, _ in value })
    }

    @Test("A shadow of any radius or offset draws", arguments: Hostile.ints)
    func shadow(value: Int) {
        drawHostile(Text("shadow").shadow(radius: value))
        drawHostile(Text("shadow").shadow(radius: 1, x: value, y: value))
    }

    @Test("Label and scrollbar spacing of any width draw", arguments: Hostile.ints)
    func labelAndScrollbar(value: Int) {
        drawHostile(Label("Title", systemImage: "star").labelIconToTitleSpacing(value))
        drawHostile(Label("Title", systemImage: "star").labelReservedIconWidth(value))
        drawHostile(
            ScrollView { VStack { ForEach(0..<20, id: \.self) { Text("row \($0)") } } }
                .scrollbarWidth(value))
        drawHostile(
            ScrollView { VStack { ForEach(0..<20, id: \.self) { Text("row \($0)") } } }
                .scrollbarSpacing(value))
    }

    @Test("A badge of any count draws", arguments: Hostile.ints)
    func badge(count: Int) {
        drawHostile(List { Text("row").badge(count) })
    }
}
