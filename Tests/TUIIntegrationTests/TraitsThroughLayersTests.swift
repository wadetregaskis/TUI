//  🖥️ TUI — A Terminal UI framework for Swift
//  TraitsThroughLayersTests.swift
//
//  A z-index, a tag, a row badge, a layout priority and a spacing preference
//  written on a view survive `.overlay { }`, `.background { }`,
//  `.contextMenu { }`, `.clipped()`, `.clipShape(_:)` and `.mask { }` after it,
//  as SwiftUI's do (hunt H-63, FMOD-3; measured,
//  `Tools/SwiftUIProbes/Traits through layers and menus (H-63)/traits.out`).
//  Until 2026-11-23 none of the six was a `SingleContentWrapper`, so each read
//  stopped at it: `Text(x).tag(x).contextMenu { … }` on a static `List` row
//  lost its tag, and `ZStack { a.zIndex(1).overlay { … }; b }` drew `b` on top.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
@testable import TUILists
import TUIMenus
import TUIPickers
@testable import TUITestSupport

/// The six wrappers, each written after the trait, as the probe writes them.
enum TraitLayer: String, CaseIterable, CustomTestStringConvertible {
    case overlay, background, contextMenu, clipped, clipShape, mask

    var testDescription: String { rawValue }
}

/// `content` under `layer`, as its own type rather than an arm of a
/// `@ViewBuilder` `switch`: the readers asked of a type, not a laid-out child,
/// see a `_ConditionalContent` arm as a view of its own.
@MainActor
private func wrapped(_ content: some View, in layer: TraitLayer) -> any View {
    switch layer {
    case .overlay: content.overlay { EmptyView() }
    case .background: content.background { EmptyView() }
    case .contextMenu: content.contextMenu { Button("Menu item") {} }
    case .clipped: content.clipped()
    case .clipShape: content.clipShape(Rectangle())
    case .mask: content.mask { Rectangle() }
    }
}

extension View {
    /// `self` under `layer`, the way an app writes it, for a container to lay
    /// out (which resolves the `switch`'s arm to the view in it).
    @ViewBuilder fileprivate func under(_ layer: TraitLayer) -> some View {
        switch layer {
        case .overlay: overlay { EmptyView() }
        case .background: background { EmptyView() }
        case .contextMenu: contextMenu { Button("Menu item") {} }
        case .clipped: clipped()
        case .clipShape: clipShape(Rectangle())
        case .mask: mask { Rectangle() }
        }
    }
}

@MainActor
@Suite("Traits through layers, menus, clips and masks")
struct TraitsThroughLayersTests {
    private func context(width: Int = 30, height: Int = 6) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    private func lines(_ view: some View, width: Int = 30) -> [String] {
        renderToBuffer(view, context: context(width: width)).lines.map(\.stripped)
    }

    @Test("A z-index inside the wrapper still orders the ZStack", arguments: TraitLayer.allCases)
    func zIndex(_ layer: TraitLayer) {
        // SwiftUI: `ZStack { Color.red.zIndex(1).<layer>; Color.green }` is red.
        let top = lines(ZStack { Text("BBB").zIndex(1).under(layer); Text("AAA") }).first
        #expect(top == "BBB")
        // The control: without the z-index, tree order puts the second on top.
        #expect(lines(ZStack { Text("BBB").under(layer); Text("AAA") }).first == "AAA")
    }

    @Test("A tag inside the wrapper is the view's", arguments: TraitLayer.allCases)
    func tag(_ layer: TraitLayer) {
        func tag<V: View>(_ view: V) -> Int? { extractTagValue(from: view, as: Int.self) }
        let found = tag(wrapped(Text("a").tag(1), in: layer))
        #expect(found == 1)
    }

    @Test("A static List row's tag inside the wrapper keys the row", arguments: TraitLayer.allCases)
    func listRowTag(_ layer: TraitLayer) {
        // SwiftUI: `List(selection:)` shows and writes the rows' tags.
        let tui = TUIContext()
        var environment = EnvironmentValues()
        let focus = FocusManager()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        var selection: Int?
        let list = List(selection: Binding(get: { selection }, set: { selection = $0 })) {
            Text("One").tag(10).under(layer)
            Text("Two").tag(20).under(layer)
        }
        .frame(height: 8)
        tui.stateStorage.beginRenderPass()
        focus.beginRenderPass()
        let context = RenderContext(availableWidth: 30, availableHeight: 12, environment: environment, tuiContext: tui)
        _ = renderToBuffer(list, context: context)
        focus.endRenderPass()
        tui.stateStorage.endRenderPass()
        let handler = focus.sections.lazy.flatMap(\.focusables).compactMap { $0 as? ItemListHandler<Int> }.first
        #expect(handler?.id(at: 0) == 10, "the first row is keyed by its tag, not its ordinal")
        #expect(handler?.id(at: 1) == 20)
    }

    @Test("A menu Picker shows the option whose tag is inside the wrapper", arguments: TraitLayer.allCases)
    func pickerOptionTag(_ layer: TraitLayer) {
        // SwiftUI's pop-up shows "Two" for the selection 2.
        let picker = Picker("P", selection: .constant(2)) {
            Text("One").tag(1).under(layer)
            Text("Two").tag(2).under(layer)
        }
        .pickerStyle(.menu)
        #expect(lines(picker, width: 40).first?.contains("Two") == true)
    }

    @Test("A List row's badge inside the wrapper is drawn", arguments: TraitLayer.allCases)
    func listRowBadge(_ layer: TraitLayer) {
        func badge<V: View>(_ view: V) -> ListRowBadge? { extractListRowBadge(from: view) }
        let found = badge(wrapped(Text("Inbox").badge(7), in: layer))
        #expect(found != nil)
        let row = lines(List { Text("Inbox").badge(12).under(layer) }).first { $0.contains("Inbox") } ?? ""
        #expect(row.contains(" 12"), "\(row.debugDescription)")
    }

    @Test("A layout priority inside the wrapper still claims the row's space", arguments: TraitLayer.allCases)
    func layoutPriority(_ layer: TraitLayer) {
        // SwiftUI gives the first text 20 of the 30 characters, the second the rest.
        let a = String(repeating: "a", count: 20)
        let row = HStack(spacing: 0) {
            Text(a).lineLimit(1).layoutPriority(1).under(layer)
            Text(String(repeating: "b", count: 20)).lineLimit(1)
        }
        #expect(lines(row).first?.hasPrefix(a) == true)
    }

    @Test("A spacer's spacing preference inside the wrapper is the view's", arguments: TraitLayer.allCases)
    func spacingPreference(_ layer: TraitLayer) {
        // SwiftUI: `HStack { box; Spacer(minLength: 0).<layer>; box }` leaves no
        // gap, the spacer's preference. The witness that lets the row ask.
        func states<V: View>(_: V) -> Bool { V._statesSpacingPreference }
        let spacer = states(wrapped(Spacer(minLength: 0), in: layer))
        let text = states(wrapped(Text("x"), in: layer))
        #expect(spacer)
        #expect(!text)
    }

    @Test("A view drawn at its own size is still drawn so under the wrapper", arguments: TraitLayer.allCases)
    func ownSize(_ layer: TraitLayer) {
        func drawsAtOwnSize<V: View>(_: V) -> Bool { drawsAtItsOwnSize(V.self) }
        let fixed = drawsAtOwnSize(wrapped(Text("x").fixedSize(), in: layer))
        let plain = drawsAtOwnSize(wrapped(Text("x"), in: layer))
        #expect(fixed)
        #expect(!plain)
    }
}
