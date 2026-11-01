//  🖥️ TUI — A Terminal UI framework for Swift
//  TintModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUICore
import TUIStyling
import TUIView

// MARK: - Tinted palette

/// A ``Palette`` that delegates to a base palette but overrides ``accent`` with
/// a tint colour. Applying `.tint(_:)` installs one for the subtree, so every
/// `palette.accent` read — button caps and focus pulse, a toggle's ON mark, a
/// slider/stepper's arrows, a radio's selected dot, focus highlights, accent-
/// coloured text — follows the tint, with no per-control wiring.
///
/// `accent` is the only role this CHANGES — but every other role still has to
/// be written out, and that is the whole hazard of the type. A `Palette` role
/// left without a witness here does not fall through to `base`; it falls to
/// `Palette`'s protocol extension, whose defaults are *collapsing* — they
/// recompute the role from this palette's OTHER roles. So an omission silently
/// discards whatever the base stated for it and substitutes a derived colour.
/// That is not hypothetical: `fieldBackground` was missing, and every tinted
/// subtree drew its text fields on a surface stepped off `background` instead
/// of on the one the base palette named.
///
/// Adding a role to ``Palette`` therefore means adding a line here.
/// `StyleCascadeCoverageTests` asserts all of them, driven by a table it
/// cross-checks against a palette that states every role, so the omission
/// fails a test instead of quietly changing a colour.
struct TintedPalette: DerivedPalette {
    let base: any Palette
    let tint: Color

    /// The tint is the only field this adds; the bases are compared by the caller.
    func hasSameDerivation(as other: Self) -> Bool { tint == other.tint }

    var id: String { base.id }
    var name: String { base.name }

    var background: Color { base.background }
    var statusBarBackground: Color { base.statusBarBackground }
    var appHeaderBackground: Color { base.appHeaderBackground }
    var overlayBackground: Color { base.overlayBackground }

    var foreground: Color { base.foreground }
    var foregroundSecondary: Color { base.foregroundSecondary }
    var foregroundTertiary: Color { base.foregroundTertiary }
    var foregroundQuaternary: Color { base.foregroundQuaternary }

    // Resolve the tint against the base palette so the accent is always a
    // concrete colour. A *semantic* tint (e.g. `.tint(.palette.success)`) would
    // otherwise reach the ANSI renderer unresolved and trap — `.resolve(with:)`
    // returns a concrete colour unchanged, and maps `.semantic(role)` to the
    // base palette's colour for that role.
    var accent: Color { tint.resolve(with: base) }

    var success: Color { base.success }
    var warning: Color { base.warning }
    var error: Color { base.error }
    var info: Color { base.info }

    var border: Color { base.border }
    var focusBackground: Color { base.focusBackground }
    var cursorColor: Color { base.cursorColor }
    var fieldBackground: Color { base.fieldBackground }

    // Not a colour, and forwarded for exactly the reason the colours are: left
    // unstated it would be recomputed from this palette's page, so a `.tint` inside
    // an `.environment(\.colorScheme, …)` would throw the pin away.
    var colorScheme: ColorScheme { base.colorScheme }
}

// MARK: - tint environment

/// Environment key for the cascading tint colour (SwiftUI's `\.tint`).
private struct TintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

/// Environment key for the tint as it was stated, resolved: a ramp where it
/// was one.
private struct TintPaintKey: EnvironmentKey {
    static let defaultValue: Paint? = nil
}

extension EnvironmentValues {
    /// The tint colour applied to this subtree, if any (set via
    /// ``View/tint(_:)-(S?)``). The accent affordance of controls follows it:
    /// a gradient's representative (``Gradient/representative``).
    public var tint: Color? {
        get { self[TintKey.self] }
        set { self[TintKey.self] = newValue }
    }

    /// The tint applied to this subtree, as stated — a gradient as a ramp, not
    /// its representative — or `nil` where none was. What a control that PAINTS
    /// its tint along itself reads: a gauge's track, a progress bar's fill
    /// (`Gradients where a colour is accepted.md` §5). SwiftUI's own is an
    /// `AnyShapeStyle?` and package-only; a resolved paint, as
    /// ``foregroundStyle`` is one, because a resolved paint compares.
    package var tintPaint: Paint? {
        get { self[TintPaintKey.self] }
        set { self[TintPaintKey.self] = newValue }
    }
}

// MARK: - Tint modifier

/// Applies a tint to its content's subtree by overriding the environment
/// palette's accent (see `TintedPalette`). A read-modify-write at render, so
/// it composes with the surrounding palette like the other style modifiers.
///
/// The tint may be any style. Where a colour is derived from it — the accent,
/// and every colour the controls derive from that — a gradient stands as its
/// representative; where one is painted along a control, as a gauge's track
/// is, the ramp itself (`EnvironmentValues.tintPaint`).
nonisolated package struct TintModifier<Content: View, S: ShapeStyle>: View {
    public let content: Content
    public let tint: S?

    public init(content: Content, tint: S?) {
        self.content = content
        self.tint = tint
    }

    /// Not used during rendering — ``Renderable`` conformance takes priority.
    @MainActor public var body: some View { content }

    @MainActor private func modifiedContext(_ context: RenderContext) -> RenderContext {
        guard let tint else { return context }

        // The same bookkeeping `EnvironmentModifier` and `_StyleEnvironmentView`
        // do, and it is not optional here either: this is NOT a plain
        // `setting()` write that only the subtree reads. The render memo keys on
        // identity + view value + size and deliberately carries no environment,
        // so a memoized view below an `.tint(…)` that changed serves the buffer
        // painted in the OLD accent — wrong pixels, not merely stale work. The
        // `@State`-driven case is covered by accident (the declaring view is an
        // ancestor, so its own invalidation reaches the row); a tint bound to
        // anything else — `@AppStorage`, a cousin's state, a plain box — is not.
        //
        // The TINT is what is noted, not the `TintedPalette` the two of them
        // resolve to. The palette is a pure function of (base, tint), so the
        // tint is the whole of what this modifier adds and whoever swapped the
        // base noted that themselves.
        //
        // What that reason is NOT, whatever this said until `5819aed2` went
        // over these sites: noting the derived palette would not "refuse every
        // memo store in the subtree". That is `EnvironmentModifier`'s arm and
        // this site has no counterpart to it — it matches `.changed` alone, so
        // an `.incomparable` answer would fall through ignored and DEADEN the
        // slot for good (`noteAppliedEnvironment` pins `isComparable = false`,
        // RenderCache.swift ~1079), which is how `.theme(…)` went on serving a
        // palette it could not compare.
        //
        // `TintedPalette` still has no `Equatable` conformance of its own, so
        // the raw value would indeed answer `.incomparable`; `ComparablePalette`
        // would compare one through its derivation, as `ThemeModifier` now
        // compares the base. Noting it here would just be a second answer to
        // the question the line above already answers.
        //
        // Nor is the existential the reason, which is what this said until
        // `ThemeModifier` needed the same answer and measured it: an `Any`
        // holding `any Palette` reports the CONCRETE type's conformance, so a
        // `SystemPalette` in that slot answers `is any Equatable` perfectly
        // well. It is `TintedPalette` specifically that cannot.
        //
        // The PAINT is noted, as `_StyleEnvironmentView` notes its: a style need
        // not be `Equatable`, and a resolved paint is.
        let paint = tint.paint(in: context.environment)
        if let cache = context.renderCache,
            case .changed = cache.noteAppliedEnvironment(
                paint, identity: context.identity, keyPath: \EnvironmentValues.tintPaint,
                depth: context.environmentApplicationDepth)
        {
            // A tint is ink; the sizes below it stay (see `_StyleEnvironmentView`).
            cache.clearAffected(by: context.identity, keepingSizes: true)
        }

        var environment = context.environment
        let accent = paint.representative
        environment.tint = accent
        environment.tintPaint = paint
        environment.palette = TintedPalette(base: environment.palette, tint: accent)
        var modified = context.withEnvironment(environment)
        modified.environmentApplicationDepth += 1
        return modified
    }
}

@MainActor extension TintModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(content, context: modifiedContext(context))
    }
}

@MainActor extension TintModifier: Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: modifiedContext(context))
    }
}

extension View {
    /// Sets the tint colour for this view's subtree — the accent affordance of
    /// every control inside (and accent-coloured content) follows it.
    ///
    /// ```swift
    /// Sidebar().tint(.green)        // green buttons, toggles, sliders, …
    /// DangerZone().tint(.red)
    /// ```
    ///
    /// `nil` leaves the inherited tint / palette accent unchanged.
    ///
    /// A gradient tints what paints along itself with the ramp — a gauge's
    /// arc or bar, a progress bar's fill — and every colour derived from the
    /// tint (a button's face, a toggle's mark) with its representative
    /// (`Gradients where a colour is accepted.md` §5).
    nonisolated public func tint<S: ShapeStyle>(_ tint: S?) -> some View {
        TintModifier(content: self, tint: tint)
    }

    /// The colour spelling, so `.tint(.red)` and `.tint(nil)` infer a type: a
    /// disfavoured `Color?` twin, as SwiftUI ships one (and as
    /// ``View/foregroundStyle(_:)-(Color)`` is).
    @_disfavoredOverload
    nonisolated public func tint(_ tint: Color?) -> some View {
        TintModifier(content: self, tint: tint)
    }
}

// MARK: - Seeing Through the Wrapper

/// - Note: An environment value reaches a subtree whether it was set one level
///   up or two, so publishing it around each member is the same thing as
///   publishing it once around the pair. What changes is only that the members
///   stay the enclosing container's own children.
@MainActor extension TintModifier: ContentRewrapping {
    public var wrappedContent: Content { content }

    /// Its content's context: the tint it publishes (``SingleContentWrapper/wrappedContentContext(_:)``).
    public func wrappedContentContext(_ context: RenderContext) -> RenderContext? { modifiedContext(context) }

    public func rewrapping<V: View>(_ view: V) -> any View {
        TintModifier<V, S>(content: view, tint: tint)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
@MainActor extension TintModifier: ChildViewProvider where Content: ChildViewProvider {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
@MainActor extension TintModifier: GridRowProviding where Content: GridRowProviding {}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
@MainActor extension TintModifier: DrawsContentUnchanged {}
