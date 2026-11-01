//  🖥️ TUI — A Terminal UI framework for Swift
//  PresentedWindowContent.swift
//
//  A window group that presents data: `WindowGroup(for:)`, whose windows each
//  present a value, opened by `openWindow(value:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - The Presented Content

/// The content of a window group that presents data — mirrors SwiftUI's
/// `PresentedWindowContent`, which a `WindowGroup(for:)` is a group of.
///
/// Each window of the group presents its own value, read and written through
/// the binding its content is built with: the value `openWindow(value:)`
/// opened it with, or `nil` — or the group's default value — for a window
/// opened by identifier or at launch. A write through the binding changes what
/// the window presents, so `openWindow(value:)` with the new value brings it to
/// the front.
///
/// You don't create one directly: the window group's initializers do.
nonisolated public struct PresentedWindowContent<Data, Content>: View
where Data: Decodable & Encodable & Hashable, Content: View {
    /// The window's content for its value.
    let present: (Binding<Data?>) -> Content

    /// The value a window opened with none presents, for a group that has a
    /// default; `nil` for one whose windows present `nil` then.
    let defaultValue: (() -> Data)?

    @MainActor public var body: some View {
        _PresentedWindowCore(present: present, defaultValue: defaultValue)
    }
}

/// What a window group's scene needs of its content: the type of value its
/// windows present, if they present one.
@MainActor
protocol PresentingWindowContent {
    /// The type of value the windows present.
    static var presentedValueType: Any.Type { get }
}

@MainActor extension PresentedWindowContent: PresentingWindowContent {
    static var presentedValueType: Any.Type { Data.self }
}

/// Builds the window's content from the value it presents, held in its state.
///
/// The value lives in a `StateBox` at this view's identity — the window's —
/// so a write through the binding redraws what read it, as a `@State` write
/// does, and each window of the group keeps its own. It starts as the value
/// the window was opened with (``EnvironmentValues/presentedWindow``), and the
/// window's presenter is told what it is each frame, so `openWindow(value:)`
/// and `dismissWindow(value:)` find the window by what it presents now.
private struct _PresentedWindowCore<Data: Hashable, Content: View>: View, Renderable, Layoutable {
    let present: (Binding<Data?>) -> Content
    let defaultValue: (() -> Data)?

    var body: Never { fatalError("_PresentedWindowCore renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let binding = valueBinding(context: context)
        if !context.isMeasuring, let presented = context.environment.presentedWindow {
            if let value = binding.wrappedValue { presented.report(AnyHashable(value)) } else { presented.report(nil) }
        }
        return TUIView.renderToBuffer(present(binding), context: contentContext(context))
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(present(valueBinding(context: context)), proposal: proposal, context: contentContext(context))
    }

    /// The context the content draws in: a child identity of this view's.
    private func contentContext(_ context: RenderContext) -> RenderContext {
        context.withChildIdentity(type: Content.self, index: 0)
    }

    /// The binding to the value the window presents, kept at this identity,
    /// starting as the value it was opened with, or as the group's default.
    private func valueBinding(context: RenderContext) -> Binding<Data?> {
        let opened = context.environment.presentedWindow?.openedValue?.base as? Data ?? defaultValue?()
        guard let storage = context.stateStorage else { return .constant(opened) }
        let box: StateBox<Data?> = storage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: PresentedWindowStateIndex.value),
            default: opened)
        storage.markActive(context.identity)
        return Binding(get: { box.value }, set: { box.value = $0 })
    }
}

/// `_PresentedWindowCore`'s StateStorage property indices: outside it, as a
/// generic type has no static stored properties. The content draws at a child
/// identity of the core's, so its own `@State` never shares this slot.
private enum PresentedWindowStateIndex {
    static let value = 0
}

// MARK: - The Window's Value

/// What a window of a group that presents data was opened with, and where it
/// reports what it presents now: the window's presenter's, one per window, put
/// in the environment of the window's content.
///
/// A class, compared by identity: one window's from frame to frame, so the
/// memos below it stay on.
@MainActor
final class PresentedWindowSlot: Equatable {
    /// The value the window was opened with, or `nil`.
    let openedValue: AnyHashable?

    /// What the window presents, as its content last drew.
    private(set) var value: AnyHashable?

    init(openedValue: AnyHashable?) {
        self.openedValue = openedValue
        self.value = openedValue
    }

    /// Notes what the window presents now.
    func report(_ value: AnyHashable?) {
        self.value = value
    }

    nonisolated static func == (lhs: PresentedWindowSlot, rhs: PresentedWindowSlot) -> Bool {
        lhs === rhs
    }
}

private struct PresentedWindowKey: EnvironmentKey {
    static let defaultValue: PresentedWindowSlot? = nil
}

extension EnvironmentValues {
    /// The window being drawn's value, for a window group that presents data;
    /// `nil` elsewhere.
    var presentedWindow: PresentedWindowSlot? {
        get { self[PresentedWindowKey.self] }
        set { self[PresentedWindowKey.self] = newValue }
    }
}
