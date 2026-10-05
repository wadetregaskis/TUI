//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextSelectability.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - TextSelectability

/// A type that describes whether people can select text — SwiftUI's
/// `TextSelectability`, given to ``View/textSelection(_:)``.
///
/// What selecting means in a terminal is TUIkit's own selection of what is
/// drawn — a drag selects the cells it crosses — described under
/// ``View/textSelection(_:)``.
public protocol TextSelectability {
    /// Whether the selectability allows selection.
    static var allowsSelection: Bool { get }
}

/// The selectability that lets people select text: ``TextSelectability/enabled``.
public struct EnabledTextSelectability: TextSelectability {
    /// `true`: people can select text.
    public static let allowsSelection = true
}

/// The selectability that keeps people from selecting text:
/// ``TextSelectability/disabled``.
public struct DisabledTextSelectability: TextSelectability {
    /// `false`: people cannot select text.
    public static let allowsSelection = false
}

extension TextSelectability where Self == EnabledTextSelectability {
    /// A selectability that lets people select text — and, in a `List` or a
    /// `Table`, the text in its rows.
    public static var enabled: EnabledTextSelectability { EnabledTextSelectability() }
}

extension TextSelectability where Self == DisabledTextSelectability {
    /// A selectability that keeps people from selecting text.
    public static var disabled: DisabledTextSelectability { DisabledTextSelectability() }
}

// MARK: - The modifier

extension View {
    /// Controls whether people can select text within this view.
    ///
    /// A terminal app's text is selected by TUIkit's own selection of what is
    /// drawn (see <doc:MouseAndGestures>, "Selecting Text"): a drag that no
    /// control uses selects the cells it crosses, a double-click a word, a
    /// triple-click the row, and the app's ⌘C — Ctrl-C by default — copies.
    /// With no modifier that selection is already on, wherever a drag does
    /// nothing else. This modifier says where it is and is not:
    ///
    /// - **`.enabled`** keeps a selection to this view's rectangle — on a
    ///   single `Text`, that `Text`, as SwiftUI's selection does — and widens
    ///   it to the rows of a ``List`` or a ``Table`` inside it, following macOS:
    ///   a press on a row's TEXT belongs to the text — a drag selects it, kept
    ///   to the row, a double-click selects a word, and a click selects nothing
    ///   — while a press on the row's blank cells selects, drags or activates
    ///   the row as before. A row is reached from the keyboard as ever.
    /// - **`.disabled`** turns TUIkit's selection off here: a drag selects
    ///   nothing, and a scroll view's background takes its press at once. The
    ///   terminal's own selection, with its modifier held, is the terminal's.
    ///
    /// The innermost modifier wins, so a view inside an `.enabled` container
    /// can opt out. A ``Button``'s label never selects, as SwiftUI documents:
    /// a press on a control is the control's. Neither value changes what a
    /// ``TextField`` or ``TextEditor`` does with its own text.
    ///
    /// Where SwiftUI selects within one `Text` at a time, this selects what is
    /// drawn, so inside an `.enabled` container that is not a list a drag may
    /// cross from one `Text` into the next.
    ///
    /// - Parameter selectability: ``TextSelectability/enabled`` or
    ///   ``TextSelectability/disabled``.
    /// - Returns: A view whose text is selectable as `selectability` says.
    public func textSelection<S: TextSelectability>(_ selectability: S) -> some View {
        _TextSelectionScope(content: self, allowsSelection: S.allowsSelection)
    }
}

/// The region a ``View/textSelection(_:)`` files over its content, and the
/// environment it gives the content.
///
/// The region is a hover observer whose handler declines everything: it is
/// geometry for the selection, not a control, and must take nothing from the
/// controls inside it. It is inserted behind its content's regions, so of two
/// nested scopes the inner one is met first — the one that wins.
///
/// The environment value tells a ``List`` or a ``Table`` inside an enabled
/// scope to file its rows for the selection, so nothing else pays for it.
struct _TextSelectionScope<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let allowsSelection: Bool

    var body: Never { fatalError("_TextSelectionScope renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkit.renderToBuffer(
            content.environment(\.textSelectionAllowed, allowsSelection), context: context)
        guard !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher
        else { return buffer }
        let id = dispatcher.registerSelectionScope(allowsSelection, in: context)
        buffer.hitTestRegions.insert(
            HitTestRegion(offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.height, handlerID: id),
            at: 0)
        return buffer
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(
            content.environment(\.textSelectionAllowed, allowsSelection), proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper

/// Seen through, as an environment modifier is: `textSelection(_:)` is
/// SwiftUI's environment-like modifier, so on multi-member content each member
/// gets its own scope, and a container still sees the members. Opaque, it
/// collapsed `List { ForEach(names) { Text($0) }.textSelection(.enabled) }`
/// into one row, took a stack's spacing from between a `ForEach`'s members,
/// and hid a `.zIndex`, a container value or a removal transition written
/// inside it. (A `List` row's `.tag(_:)` is read off the row's outermost view
/// only, under any modifier — see `TagCarrying`.)
///
/// - Note: Each member's scope files its own region, which is the member's
///   rectangle: what a selection begun on it keeps to, as SwiftUI keeps a
///   selection inside one `Text`. A scope is geometry, not an effect, so
///   filing it per member multiplies nothing a user sees.
extension _TextSelectionScope: ContentRewrapping {
    var wrappedContent: Content { content }

    func rewrapping<V: View>(_ view: V) -> any View {
        _TextSelectionScope<V>(content: view, allowsSelection: allowsSelection)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension _TextSelectionScope: ChildViewProvider where Content: ChildViewProvider {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension _TextSelectionScope: GridRowProviding where Content: GridRowProviding {}

/// Body deliberately empty: ``SectionPartsProviding`` has the whole
/// implementation for a ``SingleContentWrapper``.
extension _TextSelectionScope: SectionPartsProviding where Content: SectionPartsProviding {}

/// Draws its content unchanged, at its own identity — the region it files is
/// geometry, nothing drawn — so a removal transition written inside it plays;
/// see `DrawsContentUnchanged`.
extension _TextSelectionScope: DrawsContentUnchanged {}

// MARK: - Environment

private struct TextSelectionAllowedKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// The innermost ``View/textSelection(_:)`` around this view: `true`
    /// enabled, `false` disabled, `nil` none — TUIkit's default.
    var textSelectionAllowed: Bool? {
        get { self[TextSelectionAllowedKey.self] }
        set { self[TextSelectionAllowedKey.self] = newValue }
    }
}
