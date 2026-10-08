//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScopedTransactionModifier.swift
//
//  A transaction (or an animation) for the modifiers written inside a closure,
//  and the view they wrap left under the transaction it had:
//  `View.transaction(_:body:)`, `View.animation(_:body:)`, and their
//  `ViewModifier` counterparts.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension View {
    /// Applies the given transaction mutation function to all animations used
    /// within the `body` closure.
    ///
    /// Any modifiers applied to the content of `body` will be applied to this
    /// view, and the changes to the transaction performed in the `transform`
    /// will only affect the modifiers defined in the `body`.
    ///
    /// The following code animates the opacity changing with a faster
    /// animation, while the contents of `MyView` are animated with the implicit
    /// transaction:
    ///
    /// ```swift
    /// MyView(isActive: isActive)
    ///     .transaction { transaction in
    ///         transaction.animation = transaction.animation?.speed(2)
    ///     } body: { content in
    ///         content.opacity(isActive ? 1.0 : 0.0)
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - transform: The transformation to apply to the transaction the
    ///     modifiers in `body` render under. It runs on both the measure and the
    ///     render walk, so it must be a pure function of the value it is handed.
    ///   - body: Builds the modifiers around `content`, a stand-in for this
    ///     view, which keeps the transaction it had.
    public func transaction<V: View>(
        _ transform: @escaping (inout Transaction) -> Void,
        @ViewBuilder body: (PlaceholderContentView<Self>) -> V
    ) -> some View {
        let scope = TransactionScope()
        let built = body(PlaceholderContentView(source: scope.source(drawing: self)))
        return _ScopedTransactionView(content: built, scope: scope, transform: transform)
    }

    /// Applies the given animation to all animatable values within the `body`
    /// closure.
    ///
    /// Any modifiers applied to the content of `body` will be applied to this
    /// view, and the `animation` will only be used on the modifiers defined in
    /// the `body`.
    ///
    /// The following code animates the opacity changing with an easeInOut
    /// animation, while the contents of `MyView` are animated with the implicit
    /// transaction's animation:
    ///
    /// ```swift
    /// MyView(isActive: isActive)
    ///     .animation(.easeInOut) { content in
    ///         content.opacity(isActive ? 1.0 : 0.0)
    ///     }
    /// ```
    ///
    /// The modifiers in `body` animate every change of theirs, not only those
    /// made inside `withAnimation`; a subtree that has opted out with
    /// `Transaction.disablesAnimations` stays out.
    public func animation<V: View>(
        _ animation: Animation?, @ViewBuilder body: (PlaceholderContentView<Self>) -> V
    ) -> some View {
        transaction({ $0.applying(animation) }, body: body)
    }
}

extension View where Self: Equatable {
    /// Applies the given animation to this view when this view changes.
    ///
    /// ```swift
    /// Gauge(level: level).animation(.easeInOut)
    /// ```
    ///
    /// The view's own value is what is watched: the animation applies on the
    /// frames it differs from the last one, as ``View/animation(_:value:)``
    /// with the view as its value.
    ///
    /// - Parameter animation: The animation to apply. If `animation` is `nil`,
    ///   the view doesn't animate.
    /// - Returns: A view that applies `animation` to this view whenever it
    ///   changes.
    public func animation(_ animation: Animation?) -> some View {
        self.animation(animation, value: self)
    }
}

extension ViewModifier {
    /// Returns a new version of the modifier that will apply the transaction
    /// mutation function `transform` to all transactions within the modifier.
    ///
    /// The view the modifier is applied to keeps the transaction it had, as in
    /// ``View/transaction(_:body:)``.
    public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some ViewModifier {
        _PushPopTransactionModifier(base: self, transform: transform)
    }

    /// Returns a new version of the modifier that will apply `animation` to all
    /// animatable values within the modifier.
    public func animation(_ animation: Animation?) -> some ViewModifier {
        transaction { $0.applying(animation) }
    }
}

extension Transaction {
    /// `animation` in force, unless the subtree has opted out of animating —
    /// what SwiftUI's own `animation` forms do to the transaction.
    fileprivate mutating func applying(_ animation: Animation?) {
        guard !disablesAnimations else { return }
        self.animation = animation
    }
}

// MARK: - The scope

/// The transaction a ``View/transaction(_:body:)`` found where it was drawn,
/// and the place, kept for the view it wraps.
///
/// The body is built where the modifier is written — SwiftUI's closure does not
/// escape — before either is known, so the placeholder handed to it reads them
/// from here when it draws.
@MainActor
final class TransactionScope {
    /// The transaction in force around the scoped modifiers.
    var outer = Transaction()

    /// Where the scoped view is drawn: the wrapped view is drawn here too,
    /// as it would be with its modifiers written directly on it.
    var identity: ViewIdentity?

    /// What the placeholder draws: `content`, at the scope's place, under the
    /// transaction it had.
    func source<Content: View>(drawing content: Content) -> PlaceholderSource {
        PlaceholderSource(
            render: { [self] context in
                TUIkitView.renderToBuffer(content, context: restored(context))
            },
            measure: { [self] proposal, context in
                measureChild(content, proposal: proposal, context: restored(context))
            })
    }

    private func restored(_ context: RenderContext) -> RenderContext {
        var restored = context
        restored.environment.transaction = outer
        if let identity { restored.identity = identity }
        return restored
    }
}

/// The modifiers a ``View/transaction(_:body:)`` built, drawn under the
/// transformed transaction.
struct _ScopedTransactionView<Content: View>: View {
    let content: Content
    let scope: TransactionScope
    let transform: (inout Transaction) -> Void

    var body: Never {
        fatalError("_ScopedTransactionView renders via Renderable")
    }

    /// `context` under the transformed transaction, having noted what it was.
    private func scoped(_ context: RenderContext) -> RenderContext {
        scope.outer = context.environment.transaction
        scope.identity = context.identity
        var scoped = context
        transform(&scoped.environment.transaction)
        return scoped
    }
}

extension _ScopedTransactionView: Renderable, Layoutable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: scoped(context))
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: scoped(context))
    }
}

/// A modifier with a transaction transform of its own — what
/// ``ViewModifier/transaction(_:)`` returns.
struct _PushPopTransactionModifier<Base: ViewModifier>: ViewModifier {
    let base: Base
    let transform: (inout Transaction) -> Void

    func body(content: Content) -> some View {
        content.transaction(transform) { $0.modifier(base) }
    }
}
