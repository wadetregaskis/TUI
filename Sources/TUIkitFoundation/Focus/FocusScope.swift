//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusScope.swift
//
//  `.focusScope(_:)`, `.prefersDefaultFocus(_:in:)` and `ResetFocusAction`:
//  which control in a part of the screen should take the focus by default,
//  and putting it back there on request.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Modifiers

extension View {
    /// Creates a focus scope that limits default focus preferences.
    ///
    /// Mirrors SwiftUI's `focusScope(_:)`. Pass the namespace to
    /// ``View/prefersDefaultFocus(_:in:)`` on the control inside that should
    /// take the focus by default, and to ``ResetFocusAction`` to put the focus
    /// back there:
    ///
    /// ```swift
    /// struct Settings: View {
    ///     @Namespace private var settings
    ///     @Environment(\.resetFocus) private var resetFocus
    ///
    ///     var body: some View {
    ///         VStack {
    ///             Toggle("Wrap lines", isOn: $wraps)
    ///             TextField("Name", text: $name)
    ///                 .prefersDefaultFocus(in: settings)
    ///             Button("Start over") { resetFocus(in: settings) }
    ///         }
    ///         .focusScope(settings)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter namespace: The namespace that scopes default focus
    ///   preferences.
    /// - Returns: A view that sets the namespace of descendants for default
    ///   focus.
    public func focusScope(_ namespace: Namespace.ID) -> some View {
        _FocusScopeModifier(content: self, namespace: namespace)
    }

    /// Indicates that the view should receive focus by default for a given
    /// namespace.
    ///
    /// Mirrors SwiftUI's `prefersDefaultFocus(_:in:)`. The first focusable
    /// control in this view is the preferred one, within the namespace's
    /// ``View/focusScope(_:)`` — or the whole screen, where no view applies
    /// that scope.
    ///
    /// - **Initially:** on the frame the preference first appears, if nothing
    ///   holds the focus by then — at launch, when a sheet holding it is
    ///   presented, or later — the preferred control takes it, rather than the
    ///   first control on the screen or in the sheet. The focus manager's own
    ///   first-control choice does not count as holding it until something
    ///   happens to it: the user moves the focus, clicks, or presses a key
    ///   while it holds the focus, or the app or a
    ///   `.defaultFocus(_:_:priority:)` puts the focus somewhere. A focus put
    ///   somewhere that way is left alone. Once applied, the preference is
    ///   spent until its scope leaves the screen and comes back.
    /// - **On request:** ``ResetFocusAction`` moves the focus back to it.
    ///
    /// If several controls in one scope prefer it, the first in the tree wins.
    ///
    /// - Parameters:
    ///   - prefersDefaultFocus: Whether this view prefers to receive focus by
    ///     default. Default `true`.
    ///   - namespace: The namespace of the focus scope within which this view
    ///     prefers default focus.
    /// - Returns: A modified view that sets whether it prefers to be focused by
    ///   default.
    public func prefersDefaultFocus(
        _ prefersDefaultFocus: Bool = true, in namespace: Namespace.ID
    ) -> some View {
        _PrefersDefaultFocusModifier(content: self, prefers: prefersDefaultFocus, namespace: namespace)
    }
}

// MARK: - ResetFocusAction

/// An action that asks the focus system to reevaluate default focus. Mirrors
/// SwiftUI's `ResetFocusAction`.
///
/// Read it with `@Environment(\.resetFocus)` and call it with the namespace
/// of a ``View/focusScope(_:)``:
///
/// ```swift
/// @Environment(\.resetFocus) private var resetFocus
///
/// Button("Start over") { resetFocus(in: settings) }
/// ```
public struct ResetFocusAction {
    /// The focus system it acts on, from the environment it was read in.
    private weak let focusManager: FocusManager?

    init(focusManager: FocusManager?) {
        self.focusManager = focusManager
    }

    /// Asks the focus system to reevaluate the default focus item.
    ///
    /// The focus system reevaluates default focus when the currently focused
    /// item is within the provided namespace's scope, or when nothing holds
    /// the focus: it moves to the control that prefers default focus there
    /// (``View/prefersDefaultFocus(_:in:)``), or to the scope's first control
    /// when none does. A focus elsewhere is left where it is. With no
    /// ``View/focusScope(_:)`` for the namespace, the scope is the whole
    /// screen.
    ///
    /// - Parameter namespace: The namespace of the ``View/focusScope(_:)``
    ///   within which to reevaluate default focus.
    @MainActor
    public func callAsFunction(in namespace: Namespace.ID) {
        focusManager?.resetFocus(in: namespace)
    }
}

extension EnvironmentValues {
    /// An action that requests the focus system to reevaluate default focus.
    /// Mirrors SwiftUI's `\.resetFocus`.
    ///
    /// See ``ResetFocusAction``.
    public var resetFocus: ResetFocusAction {
        ResetFocusAction(focusManager: focusManager)
    }
}

// MARK: - The registry

/// The focus scopes and default-focus preferences a pass declared, and which
/// of them have had their one initial say.
///
/// `@usableFromInline`: the `@inlinable` `FocusRegistration.register(context:handler:focusID:)`
/// reaches it (module split step A3).
@usableFromInline
final class FocusScopeRegistry {
    /// Where each scope rendered, this walk.
    private var scopes: [Namespace.ID: ViewIdentity] = [:]

    /// The preferred control of each namespace, this walk: the first claimed.
    private var preferences: [Namespace.ID: String] = [:]

    /// The namespaces of ``preferences``, in the order they were claimed —
    /// tree order, so the first of two preferences due at once wins.
    private var preferenceOrder: [Namespace.ID] = []

    /// Namespaces a `.prefersDefaultFocus` was rendered for this walk, before
    /// any control claimed it.
    private var offered: Set<Namespace.ID> = []

    /// The last pass's scopes and preferences: what a ``ResetFocusAction``
    /// called between frames reads.
    private(set) var settledScopes: [Namespace.ID: ViewIdentity] = [:]
    private(set) var settledPreferences: [Namespace.ID: String] = [:]

    /// Namespaces seen on screen, whose initial preference has been applied
    /// or passed up. A namespace that leaves the screen is dropped, so it
    /// applies again when it comes back.
    private var applied: Set<Namespace.ID> = []

    /// The control the focus manager focused by itself — the first of a
    /// section, the first left when the focus was dropped, or the neighbour an
    /// untouched choice recovers to when it leaves, at a pass's end or
    /// unregistered by the app (`FocusManager.focusRecovered(_:)`) — while nothing
    /// has happened to that focus since: not a focus anyone asked for, so a
    /// preference that comes due later may take its place (B35).
    ///
    /// Kept across frames, and ended by the first real focus event: any move
    /// of the focus (`FocusManager.focusedID`'s `didSet`, which a Tab, a click
    /// on another control, an app's write and `.defaultFocus` all go through),
    /// an explicit focus of this very control (`FocusManager.focus(_:)`, a
    /// click on it), or any key offered to it
    /// (`FocusManager.noteInputToFocusedControl()`), so the focus never moves
    /// from under someone typing.
    var autoFocusedID: String?

    /// Starts a walk: this walk's declarations replace the last walk's.
    func beginWalk() {
        scopes.removeAll(keepingCapacity: true)
        preferences.removeAll(keepingCapacity: true)
        preferenceOrder.removeAll(keepingCapacity: true)
        offered.removeAll(keepingCapacity: true)
    }

    func declareScope(_ namespace: Namespace.ID, at identity: ViewIdentity) {
        scopes[namespace] = identity
    }

    func noteOffer(_ namespace: Namespace.ID) {
        offered.insert(namespace)
    }

    /// `@usableFromInline`: the `@inlinable` `FocusRegistration.register(context:handler:focusID:)`
    /// reaches it (module split step A3).
    @usableFromInline
    func declarePreference(_ namespace: Namespace.ID, focusID: String) {
        guard preferences[namespace] == nil else { return }
        preferences[namespace] = focusID
        preferenceOrder.append(namespace)
    }

    /// Whether the automatic first-control focus should wait for the end of
    /// the pass, because a scope or a preference that has not had its say yet
    /// is on screen: the preferred control then takes the focus directly,
    /// rather than the first control taking it and losing it in one frame.
    var holdsAutoFocus: Bool {
        scopes.keys.contains { !applied.contains($0) } || offered.contains { !applied.contains($0) }
    }

    /// Ends the pass. Returns the preferred controls whose initial say is due,
    /// in tree order, and marks everything seen as having had it.
    func endPass() -> [String] {
        let due = preferenceOrder.filter { !applied.contains($0) }.compactMap { preferences[$0] }
        applied = Set(scopes.keys).union(offered).union(preferences.keys)
        settledScopes = scopes
        settledPreferences = preferences
        return due
    }
}

// MARK: - FocusManager

extension FocusManager {
    /// Gives the initial focus to a preferred control whose scope appeared
    /// this pass, if nothing holds the focus but what the manager chose for
    /// itself — on this pass or an earlier one, untouched since (see
    /// ``FocusScopeRegistry/autoFocusedID``). Called by ``endRenderPass()``
    /// after `.defaultFocus` has had its say and before the first-focusable
    /// fallback.
    func resolveScopeDefaults() {
        let due = focusScopes.endPass()
        guard pendingFocusID == nil else { return }
        for focusID in due {
            guard currentFocusedID == nil || currentFocusedID == focusScopes.autoFocusedID else { return }
            guard canReceiveDefault(focusID) else { continue }
            focus(id: focusID)
        }
    }

    /// Input reached the focused control: a key offered to it, or taken by an
    /// `onKeyPress` on its way there. From now on its focus counts as held,
    /// even where the manager chose it, so a preference that comes due later
    /// leaves it alone (B35).
    package func noteInputToFocusedControl() {
        focusScopes.autoFocusedID = nil
    }

    /// Reevaluates default focus in `namespace`'s scope — see
    /// ``ResetFocusAction/callAsFunction(in:)``.
    func resetFocus(in namespace: Namespace.ID) {
        let scope = focusScopes.settledScopes[namespace]
        if let focused = focusedIdentity, let scope, focused != scope, !scope.isAncestor(of: focused) {
            return
        }
        if let preferred = focusScopes.settledPreferences[namespace], canReceiveDefault(preferred) {
            focus(id: preferred)
        } else if let scope, let first = firstFocusableID(inside: scope) {
            focus(id: first)
        }
    }

    /// Whether `focusID` is in this pass's ring, can take the focus, and is
    /// reachable from where the focus is: while a modal holds the keyboard,
    /// only its own controls are.
    private func canReceiveDefault(_ focusID: String) -> Bool {
        let candidates = activeSectionIsModal ? (activeSection.map { [$0] } ?? []) : sections
        return candidates.contains { section in
            section.focusables.contains { $0.focusID == focusID && $0.canBeFocused }
        }
    }

    /// The first control in the ring that rendered inside `scope`, preferring
    /// the active section's.
    package func firstFocusableID(inside scope: ViewIdentity) -> String? {
        let ordered = (activeSection.map { [$0] } ?? []) + sections.filter { $0.id != activeSection?.id }
        let reachable = activeSectionIsModal ? Array(ordered.prefix(1)) : ordered
        for section in reachable {
            for element in section.focusables where element.canBeFocused {
                guard let identity = renderedIdentity(ofFocusID: element.focusID) else { continue }
                if identity == scope || scope.isAncestor(of: identity) { return element.focusID }
            }
        }
        return nil
    }
}

// MARK: - The offer a preferring view makes

/// The preference `.prefersDefaultFocus(_:in:)` offers the first focusable
/// control below it, which claims it through `FocusRegistration` — the same
/// shape as `FocusHandoffOffer`, for the same reason: the preferred control's
/// focus id is its own, and only it knows it.
///
/// `@usableFromInline`: the `@inlinable` `FocusRegistration.register(context:handler:focusID:)`
/// reaches it (module split step A3).
@usableFromInline
final class PreferredFocusOffer: @unchecked Sendable {
    let namespace: Namespace.ID

    /// Whose it is. `nil` until the first focusable registers below the modifier.
    private var claimant: ViewIdentity?

    init(namespace: Namespace.ID) {
        self.namespace = namespace
    }

    /// The namespace if `identity` may claim the preference — because nothing
    /// has yet, or because this identity already did. Render pass only.
    ///
    /// `@usableFromInline`: the `@inlinable` `FocusRegistration.register(context:handler:focusID:)`
    /// reaches it (module split step A3).
    @usableFromInline
    func claim(_ identity: ViewIdentity) -> Namespace.ID? {
        if let claimant, claimant != identity { return nil }
        claimant = identity
        return namespace
    }
}

private struct PreferredFocusOfferKey: EnvironmentKey {
    static let defaultValue: PreferredFocusOffer? = nil
}

extension EnvironmentValues {
    /// The default-focus preference offered to the first focusable in the
    /// subtree, set by `.prefersDefaultFocus(_:in:)`.
    ///
    /// `@usableFromInline`: the `@inlinable` `FocusRegistration.register(context:handler:focusID:)`
    /// reaches it (module split step A3).
    @usableFromInline
    var preferredFocusOffer: PreferredFocusOffer? {
        get { self[PreferredFocusOfferKey.self] }
        set { self[PreferredFocusOfferKey.self] = newValue }
    }
}

// MARK: - The modifier views

/// Declares its scope each render, and draws its content unchanged at its own
/// identity — the identity the focus is tested against.
struct _FocusScopeModifier<Content: View>: View {
    let content: Content
    let namespace: Namespace.ID

    var body: Never {
        fatalError("_FocusScopeModifier renders via Renderable")
    }
}

extension _FocusScopeModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring { declare(context: context) }
        return TUIkitView.renderToBuffer(content, context: context)
    }

    /// Declares the scope, and journals the declaration so a served subtree
    /// makes it again: a scope is per-frame presence, like a focus section.
    private func declare(context: RenderContext) {
        let identity = context.identity
        let namespace = namespace
        FocusScopeRegistrar.declare(namespace, at: identity, context: context)
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        journal.append(
            EffectJournal.Entry(
                kind: FocusScopeRegistrar.kind, channelToken: context.environment.keyChannelToken
            ) { replay in
                FocusScopeRegistrar.declare(namespace, at: identity, context: replay)
            })
    }
}

extension _FocusScopeModifier: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// The one declaration `.focusScope(_:)` makes, shared by the live render and
/// by a value memo replaying it — see `EffectJournal`.
enum FocusScopeRegistrar {
    static let kind = EffectJournal.Kind("focusScope")

    /// Refuses the throwaway managers, as every focus declaration does: a
    /// backdrop's scope is a picture of one.
    @MainActor
    static func declare(_ namespace: Namespace.ID, at identity: ViewIdentity, context: RenderContext) {
        guard let manager = context.environment.focusManager,
            !manager.isBackdrop, !manager.suppressesAutoFocus
        else { return }
        manager.focusScopes.declareScope(namespace, at: identity)
    }
}

/// Puts a fresh ``PreferredFocusOffer`` in the environment on every render.
struct _PrefersDefaultFocusModifier<Content: View>: View {
    let content: Content
    let prefers: Bool
    let namespace: Namespace.ID

    var body: Never {
        fatalError("_PrefersDefaultFocusModifier renders via Renderable")
    }
}

extension _PrefersDefaultFocusModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard prefers, !context.isMeasuring else {
            return TUIkitView.renderToBuffer(content, context: context)
        }
        if let manager = context.environment.focusManager, !manager.isBackdrop, !manager.suppressesAutoFocus {
            manager.focusScopes.noteOffer(namespace)
        }
        // A fresh offer per render: the claim is this render's. The control
        // that claims it declines the memos (an offered declaration), so no
        // subtree holding the claim is ever served — which is also why this
        // needs no journal entry.
        let offer = PreferredFocusOffer(namespace: namespace)
        let env = context.environment.setting(\.preferredFocusOffer, to: offer)
        return TUIkitView.renderToBuffer(content, context: context.withEnvironment(env))
    }
}

extension _PrefersDefaultFocusModifier: Layoutable {
    /// Measures as its content, with no offer: a measure pass registers
    /// nothing, so nothing would claim it.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrappers (the READ direction)

/// Each names its content so a container asking for a z-index or an alignment
/// guide can look through it instead of stopping at it. Read-only: neither
/// conforms to ``ContentRewrapping``, so nothing about it is distributed to the
/// members of multi-view content.
extension _FocusScopeModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

extension _PrefersDefaultFocusModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Each draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _FocusScopeModifier: DrawsContentUnchanged {}
extension _PrefersDefaultFocusModifier: DrawsContentUnchanged {}
