//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnchorTests.swift
//
//  `Anchor`, `anchorPreference`, `transformAnchorPreference` and
//  `GeometryProxy.subscript(_:)`, against probes L1 and L2 of the W05 brief
//  (SwiftUI, macOS 15): an anchor resolves relative to the READING proxy's own
//  origin. Design study A2 §10 step 4.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

private struct BoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CellRect>? { nil }
    static func reduce(value: inout Anchor<CellRect>?, nextValue: () -> Anchor<CellRect>?) {
        value = value ?? nextValue()
    }
}

private struct PointKey: PreferenceKey {
    static var defaultValue: Anchor<CellPoint>? { nil }
    static func reduce(value: inout Anchor<CellPoint>?, nextValue: () -> Anchor<CellPoint>?) {
        value = value ?? nextValue()
    }
}

private struct AllKey: PreferenceKey {
    static var defaultValue: [Anchor<CellRect>] { [] }
    static func reduce(value: inout [Anchor<CellRect>], nextValue: () -> [Anchor<CellRect>]) {
        value += nextValue()
    }
}

/// What a reader resolved, the last time it was built.
@MainActor
private final class Resolved<T> {
    var value: T?
}

@MainActor
@Suite("Anchors")
struct AnchorTests {

    @Test("L1: a bounds anchor read by a reader filling the overlay is where the view is, with no correction")
    func probeL1() {
        let harness = InputChainHarness()
        let seen = Resolved<CellRect>()
        let view = Text("hello")
            .padding(2)
            .anchorPreference(key: BoundsKey.self, value: .bounds) { $0 }
            .padding(1)
            .overlayPreferenceValue(BoundsKey.self) { anchor in
                GeometryReader { proxy in
                    if let anchor {
                        // swiftlint:disable:next redundant_discardable_let
                        let _ = (seen.value = proxy[anchor])
                    }
                    Text("")
                }
            }
        harness.frame(view)
        // The padded text is 9 × 5, one cell in from the base's corner.
        #expect(seen.value == CellRect(x: 1, y: 1, width: 9, height: 5))
        #expect(harness.geometryCorrections.layer == 0)
    }

    @Test("L2: relative to the reader's own origin; a reader off the layer's origin is corrected once")
    func probeL2() {
        let harness = InputChainHarness()
        let seen = Resolved<CellRect>()
        let view = Text("hello")
            .padding(2)
            .anchorPreference(key: BoundsKey.self, value: .bounds) { $0 }
            .padding(1)
            .overlayPreferenceValue(BoundsKey.self) { anchor in
                GeometryReader { proxy in
                    if let anchor {
                        // swiftlint:disable:next redundant_discardable_let
                        let _ = (seen.value = proxy[anchor])
                    }
                    Text("")
                }
                .padding(1)
            }
        harness.frame(view)
        // SwiftUI's (2, 2, 49, 36) for a reader padded 5 over a view at 7.
        #expect(seen.value == CellRect(x: 0, y: 0, width: 9, height: 5))
        #expect(harness.geometryCorrections.layer == 1)
        harness.frame(view)
        #expect(seen.value == CellRect(x: 0, y: 0, width: 9, height: 5))
        #expect(harness.geometryCorrections.layer == 1)
        #expect(harness.geometryCorrections.residual == 0)
    }

    @Test("A layer drawn again for its reader counts what it publishes once")
    func correctedLayerPublishesOnce() {
        struct CountKey: PreferenceKey {
            static var defaultValue: Int { 0 }
            static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
        }
        let harness = InputChainHarness()
        let count = Resolved<Int>()
        let view = VStack {
            Text("hello")
                .anchorPreference(key: BoundsKey.self, value: .bounds) { $0 }
                .overlayPreferenceValue(BoundsKey.self) { anchor in
                    GeometryReader { proxy in
                        if let anchor {
                            Text("\(proxy[anchor].x)")
                        }
                    }
                    .padding(.leading, 1)
                    .preference(key: CountKey.self, value: 1)
                }
        }
        .onPreferenceChange(CountKey.self) { count.value = $0 }
        harness.frame(view)
        #expect(harness.geometryCorrections.layer == 1)
        #expect(count.value == 1)
    }

    @Test("A layer over a base that made no anchor is drawn once, with no layer space")
    func layerWithoutAnchors() {
        let harness = InputChainHarness()
        let seen = Resolved<CellRect>()
        let view = Text("hello")
            .padding(.leading, 2)
            .anchorPreference(key: BoundsKey.self, value: .bounds) { $0 }
            .overlayPreferenceValue(PointKey.self) { _ in
                GeometryReader { proxy in
                    // swiftlint:disable:next redundant_discardable_let
                    let _ = (seen.value = proxy.frame(in: .local))
                    Text("")
                }
                .padding(.leading, 1)
            }
        harness.frame(view)
        #expect(seen.value == CellRect(x: 0, y: 0, width: 6, height: 1))
        #expect(harness.geometryCorrections.layer == 0)
    }

    @Test("Point sources: unit points floor once from the whole product; a point is in the view's cells")
    func pointSources() {
        let harness = InputChainHarness()
        let center = Resolved<CellPoint>()
        let corner = Resolved<CellPoint>()
        func probe(_ source: Anchor<CellPoint>.Source, into seen: Resolved<CellPoint>) -> some View {
            Text("abcde")
                .padding(.leading, 3)
                .anchorPreference(key: PointKey.self, value: source) { $0 }
                .overlayPreferenceValue(PointKey.self) { anchor in
                    GeometryReader { proxy in
                        if let anchor {
                            // swiftlint:disable:next redundant_discardable_let
                            let _ = (seen.value = proxy[anchor])
                        }
                        Text("")
                    }
                }
        }
        harness.frame(probe(.center, into: center))
        harness.frame(probe(.point(CellPoint(x: 7, y: 0)), into: corner))
        // Eight cells wide: the centre is column 4.
        #expect(center.value == CellPoint(x: 4, y: 0))
        #expect(corner.value == CellPoint(x: 7, y: 0))
        #expect(Anchor<CellPoint>.Source.bottomTrailing.geometry == .unitPoint(.bottomTrailing))
    }

    @Test("A rect source, an array of sources and an optional source")
    func compositeSources() {
        let harness = InputChainHarness()
        let seen = Resolved<[CellRect]>()
        let optional = Resolved<CellRect?>()
        struct ArrayKey: PreferenceKey {
            static var defaultValue: Anchor<[CellRect]>? { nil }
            static func reduce(value: inout Anchor<[CellRect]>?, nextValue: () -> Anchor<[CellRect]>?) {
                value = value ?? nextValue()
            }
        }
        struct OptionalKey: PreferenceKey {
            static var defaultValue: Anchor<CellRect?>? { nil }
            static func reduce(value: inout Anchor<CellRect?>?, nextValue: () -> Anchor<CellRect?>?) {
                value = value ?? nextValue()
            }
        }
        let view = VStack(spacing: 0) {
            Text("x")
            Text("wide")
                .anchorPreference(
                    key: ArrayKey.self,
                    value: Anchor.Source([.bounds, .rect(CellRect(x: 1, y: 0, width: 2, height: 1))])
                ) { $0 }
                .anchorPreference(key: OptionalKey.self, value: Anchor.Source(nil as Anchor<CellRect>.Source?)) { $0 }
        }
        .overlayPreferenceValue(ArrayKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    // swiftlint:disable:next redundant_discardable_let
                    let _ = (seen.value = proxy[anchor])
                }
                Text("")
            }
        }
        .overlayPreferenceValue(OptionalKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    // swiftlint:disable:next redundant_discardable_let
                    let _ = (optional.value = proxy[anchor])
                }
                Text("")
            }
        }
        harness.frame(view)
        #expect(seen.value == [CellRect(x: 0, y: 1, width: 4, height: 1), CellRect(x: 1, y: 1, width: 2, height: 1)])
        #expect(optional.value == .some(nil))
    }

    @Test("transformAnchorPreference collects the anchors of every row, and each resolves to its row")
    func transformCollects() {
        let harness = InputChainHarness()
        let seen = Resolved<[CellRect]>()
        let view = VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                Text(String(repeating: "#", count: index + 1))
                    .transformAnchorPreference(key: AllKey.self, value: .bounds) { all, anchor in
                        all.append(anchor)
                    }
            }
        }
        .backgroundPreferenceValue(AllKey.self) { anchors in
            GeometryReader { proxy in
                // swiftlint:disable:next redundant_discardable_let
                let _ = (seen.value = anchors.map { proxy[$0] })
                Text("")
            }
        }
        harness.frame(view)
        #expect(
            seen.value == [
                CellRect(x: 0, y: 0, width: 1, height: 1), CellRect(x: 0, y: 1, width: 2, height: 1),
                CellRect(x: 0, y: 2, width: 3, height: 1),
            ])
    }

    @Test("An anchor kept in state and read by a reader elsewhere resolves through the global space")
    func anchorKeptInState() {
        let harness = InputChainHarness()
        let kept = Resolved<Anchor<CellRect>>()
        let seen = Resolved<CellRect>()
        let view = {
            VStack(alignment: .leading, spacing: 0) {
                Text("abc")
                    .padding(.leading, 4)
                    .anchorPreference(key: BoundsKey.self, value: .bounds) { $0 }
                    .onPreferenceChange(BoundsKey.self) { kept.value = $0 }
                Text("-")
                GeometryReader { proxy in
                    if let anchor = kept.value {
                        // swiftlint:disable:next redundant_discardable_let
                        let _ = (seen.value = proxy[anchor])
                    }
                    Text("")
                }
                .frame(height: 2)
            }
        }
        harness.frame(view())
        harness.frame(view())
        harness.frame(view())
        // The reader is two rows down; the anchored text one row above that,
        // in its first row.
        #expect(seen.value == CellRect(x: 0, y: -2, width: 7, height: 1))
    }

    @Test("An anchor inside a scrolled view and one moved by .offset resolve where they are drawn")
    func scrolledAndOffset() {
        let harness = InputChainHarness()
        let scrolled = Resolved<CellRect>()
        let moved = Resolved<CellRect>()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<6, id: \.self) { Text("row \($0)") }
                        Text("anchored").anchorPreference(key: BoundsKey.self, value: .bounds) { $0 }
                        ForEach(7..<20, id: \.self) { Text("row \($0)") }
                    }
                }
                .scrollPosition(binding)
                .frame(height: 4)
                Text("moved")
                    .anchorPreference(key: PointKey.self, value: .topLeading) { $0 }
                    .offset(x: 3, y: 1)
            }
            .overlayPreferenceValue(BoundsKey.self) { anchor in
                GeometryReader { proxy in
                    if let anchor {
                        // swiftlint:disable:next redundant_discardable_let
                        let _ = (scrolled.value = proxy[anchor])
                    }
                    Text("")
                }
            }
            .overlayPreferenceValue(PointKey.self) { anchor in
                GeometryReader { proxy in
                    if let anchor {
                        let point = proxy[anchor]
                        // swiftlint:disable:next redundant_discardable_let
                        let _ = (moved.value = CellRect(x: point.x, y: point.y, width: 0, height: 0))
                    }
                    Text("")
                }
            }
        }
        harness.frame(view())
        position.scrollTo(y: 5)
        harness.frame(view())
        // Content row 6, scrolled five: the viewport's second row.
        #expect(scrolled.value?.y == 1)
        // Laid out on row 4 at column 0, drawn three right and one down.
        #expect(moved.value == CellRect(x: 3, y: 5, width: 0, height: 0))
    }
}
