//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SpringLoading.swift
//
//  SwiftUI's spring loading: a control that a drag pauses over is activated,
//  so the drag can reveal its own destination — a folder list, another tab —
//  without being let go of.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - SpringLoadingBehavior

/// The options for controlling the spring loading behavior of views.
///
/// Use values of this type with the ``View/springLoadingBehavior(_:)``
/// modifier, and with ``TabContent/springLoadingBehavior(_:)`` on a tab.
public struct SpringLoadingBehavior: Hashable, Sendable {
    private enum Kind: Hashable, Sendable { case automatic, enabled, disabled }
    private let kind: Kind

    /// The automatic spring loading behavior.
    ///
    /// This defers to default component behavior for spring loading: a tab
    /// spring-loads, and a button does not — measured on macOS 15.8, where an
    /// `.automatic` button, link, navigation link and disclosure group are not
    /// spring-loaded and the same views under `.enabled` are.
    public static let automatic = Self(kind: .automatic)

    /// Spring loaded interactions will be enabled for applicable views.
    public static let enabled = Self(kind: .enabled)

    /// Spring loaded interactions will be disabled for applicable views.
    public static let disabled = Self(kind: .disabled)

    /// Whether a view that spring-loads by default when `byDefault` says so
    /// spring-loads under this behavior.
    func allows(byDefault: Bool) -> Bool {
        switch kind {
        case .automatic: byDefault
        case .enabled: true
        case .disabled: false
        }
    }
}

private struct SpringLoadingBehaviorKey: EnvironmentKey {
    static let defaultValue = SpringLoadingBehavior.automatic
}

extension EnvironmentValues {
    /// The behavior of spring loaded interactions for the views associated
    /// with this environment — set with ``View/springLoadingBehavior(_:)``.
    ///
    /// A value of `enabled` means that a view should support spring loaded
    /// interactions if it is able, and `disabled` means it should not. A value
    /// of `automatic` means that a view should follow its default behavior: a
    /// ``TabView``'s tabs spring-load, and a ``Button`` does not.
    public internal(set) var springLoadingBehavior: SpringLoadingBehavior {
        get { self[SpringLoadingBehaviorKey.self] }
        set { self[SpringLoadingBehaviorKey.self] = newValue }
    }
}

// MARK: - The modifier

extension View {
    /// Sets the spring loading behavior for this view.
    ///
    /// Spring loading refers to a view being activated during a drag and drop
    /// interaction: while a drag is in flight, holding the pointer still over a
    /// spring-loaded view for half a second activates it, as a click would,
    /// and the drag carries on. This is commonly used with views that have a
    /// navigation or presentation effect, allowing the destination to be
    /// revealed without letting go of the drag:
    ///
    /// ```swift
    /// Button {
    ///     showFolders = true
    /// } label: {
    ///     Label("Show Folders", systemImage: "folder")
    /// }
    /// .springLoadingBehavior(.enabled)
    /// ```
    ///
    /// The views that spring-load are the ones macOS's do (measured on macOS
    /// 15.8): a ``Button`` in any style, a ``NavigationLink``, a ``Link``, a
    /// `.button` ``Toggle``, a ``DisclosureGroup``'s header (which opens or
    /// closes it) and a segmented ``Picker``'s segments, all only under
    /// `.enabled`; and, as SwiftUI documents, a ``TabView``'s tabs, which
    /// spring-load unless told `.disabled`. A ``Menu``, a menu or radio-group
    /// ``Picker`` and a checkbox ``Toggle`` never do. The pause is
    /// macOS's default spring-loading delay, half a second; moving to another
    /// cell starts it again, and a view activates once each time the pointer
    /// arrives on it — a disclosure group opened by a pause does not shut on
    /// the next one.
    ///
    /// The keyboard needs no pause: while a drag is in flight, Tab still moves
    /// the focus and Return or Space still activates the focused control, so a
    /// keyboard reaches whatever a pause would.
    ///
    /// Unlike `disabled(_:)`, this modifier overrides the value set by an
    /// ancestor view rather than being unioned with it. For example, the below
    /// button would allow spring loading:
    ///
    /// ```swift
    /// HStack {
    ///     Button {
    ///         showFolders = true
    ///     } label: {
    ///         Label("Show Folders", systemImage: "folder")
    ///     }
    ///     .springLoadingBehavior(.enabled)
    ///
    ///     ...
    /// }
    /// .springLoadingBehavior(.disabled)
    /// ```
    ///
    /// - Parameter behavior: Whether spring loading is enabled or not. If
    ///   unspecified, the default behavior is `.automatic`.
    /// - Returns: A view whose spring-loading views follow `behavior`.
    public func springLoadingBehavior(_ behavior: SpringLoadingBehavior) -> some View {
        environment(\.springLoadingBehavior, behavior)
    }
}

// MARK: - A region that spring-loads

/// Makes its content's rectangle spring-load: a drag held still over it for the
/// spring-loading delay runs `activate`.
///
/// For a view that is not itself a control with a region of its own to name —
/// a `.sidebarAdaptable` tab view's rows, which are a list's. A control that
/// already registers a mouse handler (a `Button`, a tab strip's chip) registers
/// its spring-load target under that handler's id instead, and needs no second
/// region.
struct _SpringLoadedRegion<Content: View>: View {
    let content: Content

    /// Whether the region spring-loads at all; off, it registers nothing and
    /// draws its content as it is.
    let isEnabled: Bool

    /// What a pause over the region does.
    let activate: () -> Void

    var body: Never {
        fatalError("_SpringLoadedRegion renders via Renderable")
    }
}

extension _SpringLoadedRegion: Renderable, Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkit.renderToBuffer(content, context: context)
        guard isEnabled, !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher,
            let session = context.environment.dragAndDropSession
        else { return buffer }
        // An inert region, at the BACK of the dispatch order as a drop zone's
        // is: it takes no event, so a click on the content still reaches the
        // content, and spring-load targeting matches ids rather than taking
        // the innermost region, so it finds this one at any depth.
        let handlerID = dispatcher.register(in: context) { _ in false }
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.height,
                handlerID: handlerID),
            at: 0)
        session.registerSpringLoadTarget(
            DragAndDropSession.SpringLoadTarget(
                handlerID: handlerID, identity: context.identity, activate: activate),
            in: context)
        return buffer
    }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``.
extension _SpringLoadedRegion: SingleContentWrapper {
    var wrappedContent: Content { content }
}
