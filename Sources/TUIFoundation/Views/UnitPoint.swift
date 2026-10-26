//  🖥️ TUI — A Terminal UI framework for Swift
//  UnitPoint.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - UnitPoint

/// A normalized point in a view's coordinate space, matching SwiftUI's
/// `UnitPoint`: `(0, 0)` is the top-leading corner, `(1, 1)` the
/// bottom-trailing one.
///
/// Used by ``TUI/View/defaultScrollAnchor(_:)`` to express where a scroll
/// view initially positions — and keeps — its content: `.bottom` is the
/// log-viewer follow mode.
///
/// `Codable` as in SwiftUI, over its two stored coordinates. As with ``Angle``,
/// the encoded shape is what this type stores, not an interchange format.
public struct UnitPoint: Hashable, Sendable, Codable {
    /// The normalized horizontal position (0 = leading, 1 = trailing).
    public var x: Double

    /// The normalized vertical position (0 = top, 1 = bottom).
    public var y: Double

    /// Creates a unit point at the top-leading corner, ``zero``.
    public init() {
        self.init(x: 0, y: 0)
    }

    /// Creates a unit point.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Self(x: 0, y: 0)
    public static let center = Self(x: 0.5, y: 0.5)
    public static let leading = Self(x: 0, y: 0.5)
    public static let trailing = Self(x: 1, y: 0.5)
    public static let top = Self(x: 0.5, y: 0)
    public static let bottom = Self(x: 0.5, y: 1)
    public static let topLeading = Self(x: 0, y: 0)
    public static let topTrailing = Self(x: 1, y: 0)
    public static let bottomLeading = Self(x: 0, y: 1)
    public static let bottomTrailing = Self(x: 1, y: 1)
}

// MARK: - Default Scroll Anchor

/// Which of a scroll view's anchoring questions an anchor answers — SwiftUI's
/// `ScrollAnchorRole`, taken by ``TUI/View/defaultScrollAnchor(_:for:)``.
///
/// "Anchor" names three things, and the unlabelled
/// ``TUI/View/defaultScrollAnchor(_:)`` answers all of them at once:
/// **where the view opens**, **what it holds onto as its content changes**,
/// and **where content shorter than the view sits**. The role picks one.
///
/// A role's anchor wins over the unlabelled one wherever either is written,
/// as SwiftUI's does (measured): the role-specific call states an exception
/// to the unlabelled rule, so it holds whether it is written nearer the view
/// or further out.
public struct ScrollAnchorRole: Hashable, Sendable {
    private let rawValue: String

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Where the view is scrolled to on the frame it first renders.
    ///
    /// `.bottom` here is "open at the tail, then leave me alone" — a log you
    /// want to join at the end but then read backwards through without it
    /// snatching the view away on every append.
    public static let initialOffset = Self("initialOffset")

    /// What the view holds onto when its CONTENT changes size under it.
    ///
    /// `.bottom` here is follow-the-log: while the view sits at the tail,
    /// arriving rows keep it there.
    public static let sizeChanges = Self("sizeChanges")

    /// Where content SHORTER than the scroll view sits in it.
    ///
    /// `.bottom` here is a chat: the first lines appear at the bottom of the
    /// view, and each new one pushes the ones before it up. Content that fills
    /// the view is unaffected — there is no room to place it in.
    ///
    /// Read by ``ScrollView`` on its vertical axis, at the anchor's `y` as a
    /// fraction of the room left over (a `y` of 0.5 centres the content),
    /// rounded down to a whole line, and on its horizontal axis at the
    /// anchor's `x`, to a whole column: `.trailing` puts narrow content
    /// against the trailing edge, and the unlabelled `.top` or `.bottom`
    /// (whose `x` is 0.5) centres it, as SwiftUI's do (measured). A view that
    /// scrolls both ways places each axis by its own coordinate. Content that
    /// fills whatever width it is offered has none of its own to place, where
    /// SwiftUI places its ideal width. Like SwiftUI's on macOS, ``List`` and
    /// ``Table`` ignore it: their rows always start at the top.
    public static let alignment = Self("alignment")
}

/// The anchors ``TUI/View/defaultScrollAnchor(_:for:)`` stated, one per
/// role — `nil` where none was, which defers to the unlabelled anchor
/// (``EnvironmentValues/defaultScrollAnchor``).
///
/// `nil` is "unstated", not "no anchor", because that is what SwiftUI's is
/// (measured): `.defaultScrollAnchor(nil, for: .initialOffset)` beside an
/// unlabelled `.bottom` still opens at the tail. A role is opted out of the
/// unlabelled anchor by stating another — `.top` — not by stating none.
struct ScrollAnchorRoleAnchors: Equatable, Sendable {
    var initialOffset: UnitPoint?
    var sizeChanges: UnitPoint?
    var alignment: UnitPoint?

    subscript(role: ScrollAnchorRole) -> UnitPoint? {
        get {
            switch role {
            case .initialOffset: initialOffset
            case .sizeChanges: sizeChanges
            default: alignment
            }
        }
        set {
            switch role {
            case .initialOffset: initialOffset = newValue
            case .sizeChanges: sizeChanges = newValue
            default: alignment = newValue
            }
        }
    }
}

private struct DefaultScrollAnchorKey: EnvironmentKey {
    static let defaultValue: UnitPoint? = nil
}

private struct ScrollAnchorRolesKey: EnvironmentKey {
    static let defaultValue = ScrollAnchorRoleAnchors()
}

extension EnvironmentValues {
    /// The anchor the unlabelled ``TUI/View/defaultScrollAnchor(_:)``
    /// states: every role's, except where
    /// ``TUI/View/defaultScrollAnchor(_:for:)`` states one of its own.
    ///
    /// Writing it directly is writing the unlabelled modifier.
    public var defaultScrollAnchor: UnitPoint? {
        get { self[DefaultScrollAnchorKey.self] }
        set { self[DefaultScrollAnchorKey.self] = newValue }
    }

    /// The anchors stated for one role each — see ``ScrollAnchorRoleAnchors``.
    ///
    /// Internal: SwiftUI exposes no `EnvironmentValues` member for a role, and
    /// ``defaultScrollAnchor`` is public only because it predates the roles.
    var scrollAnchorRoles: ScrollAnchorRoleAnchors {
        get { self[ScrollAnchorRolesKey.self] }
        set { self[ScrollAnchorRolesKey.self] = newValue }
    }

    /// The anchor in force for `role`: the one stated for it, or else the
    /// unlabelled one.
    ///
    /// `@usableFromInline`: the `@inlinable` ``declaredAnchorModes`` calls it
    /// (module split step A3).
    @usableFromInline
    func scrollAnchor(for role: ScrollAnchorRole) -> UnitPoint? {
        scrollAnchorRoles[role] ?? defaultScrollAnchor
    }

    /// Both declared anchor MODES, resolved — what a scrollable captures each
    /// render: the one it holds as its content changes (``ScrollAnchorRole/sizeChanges``)
    /// and the one it opens at (``ScrollAnchorRole/initialOffset``).
    ///
    /// `opening` is always stated here. It is optional because the handlers
    /// that capture it keep the third state "nobody said", which defers to the
    /// standing mode, for a caller that sets only the standing one.
    ///
    /// `@inlinable` (module split step A3): `ItemListHandler` captures both
    /// with its frame inputs, in the Lists group, which leaves the substrate
    /// at B6.
    @inlinable
    package var declaredAnchorModes: (standing: ScrollAnchorMode, opening: ScrollAnchorMode?) {
        (
            ScrollAnchorMode.resolved(defaultScrollAnchor: scrollAnchor(for: .sizeChanges)),
            ScrollAnchorMode.resolved(defaultScrollAnchor: scrollAnchor(for: .initialOffset))
        )
    }
}

extension View {
    /// Associates an anchor with scroll views within this view, controlling
    /// where their content is initially positioned, what they hold onto as
    /// the content changes, **and** where content shorter than the view sits.
    /// Matches SwiftUI's modifier of the same name, which likewise sets every
    /// role at once — see ``defaultScrollAnchor(_:for:)`` to set one.
    ///
    /// `.bottom` (a `y` of 0.75 or more) is the terminal's log-viewer idiom:
    /// the view opens at the tail, and while it is *at* the bottom, growing
    /// content keeps it glued there; scrolling up releases the glue (appends no
    /// longer move the view); scrolling back to the bottom — End, or any scroll
    /// that lands there — re-engages it. Engagement is **positional** — being
    /// at the tail *is* the follow — so there is no stored flag to fall out of
    /// step, and the opening placement is that rule's own first frame rather
    /// than a second mechanism.
    ///
    /// In a ``ScrollView``, `.bottom` also places content shorter than the view
    /// at its BOTTOM (the ``ScrollAnchorRole/alignment`` role), as SwiftUI's
    /// does: the first lines of a chat appear at the bottom and push upwards.
    /// For a log that starts at the top and only follows its tail once it
    /// fills the view, state the other two roles and leave alignment alone:
    ///
    /// ```swift
    /// // Starts at the bottom, grows upwards, then follows the tail.
    /// ScrollView { messages }.defaultScrollAnchor(.bottom)
    ///
    /// // Starts at the top, grows downwards, then follows the tail.
    /// ScrollView { logLines }
    ///     .defaultScrollAnchor(.bottom, for: .initialOffset)
    ///     .defaultScrollAnchor(.bottom, for: .sizeChanges)
    /// ```
    ///
    /// ``List`` and ``Table`` ignore the alignment role, as macOS's do, so
    /// there the two spellings behave alike.
    ///
    /// Two deviations from SwiftUI, both a consequence of scrolling in whole
    /// rows rather than points:
    /// - For where the view opens and what it holds, the anchor **quantises to
    ///   three edges**: `y ≥ 0.75` is the bottom, `y ≤ 0.25` the top, and
    ///   anything mid-content anchors *nothing* (what is on screen stays put
    ///   as with no anchor at all: ``ScrollWindowHold``). SwiftUI's `.center` keeps the
    ///   centre fixed, but holds the top row through rows inserted above it, as
    ///   every anchor does (`Tools/SwiftUIProbes/Scroll anchoring/hold.out`
    ///   cases 22–23); here it means "no anchor". The alignment role is not
    ///   quantised: it places short content at its `y` to the line.
    /// - `x` is ignored for where the view opens and what it holds: the
    ///   anchor modes are defined over rows. The alignment role reads it on a
    ///   view that scrolls across.
    ///
    /// - Parameter anchor: The unit point to anchor content to, or `nil`
    ///   for the default (no anchor — the top).
    public func defaultScrollAnchor(_ anchor: UnitPoint?) -> some View {
        environment(\.defaultScrollAnchor, anchor)
    }

    /// Associates an anchor with scroll views within this view for **one** of
    /// the questions an anchor answers. Matches SwiftUI's modifier of the same
    /// name.
    ///
    /// The unlabelled ``defaultScrollAnchor(_:)`` sets every role together,
    /// which is what a chat wants: open at the tail, follow it, and sit at the
    /// bottom while it is short. The roles come apart when you want one
    /// without the others:
    ///
    /// ```swift
    /// // Join the log at the end, then read backwards undisturbed.
    /// List(entries) { … }.defaultScrollAnchor(.bottom, for: .initialOffset)
    ///
    /// // Start at the beginning, but follow the tail once you reach it.
    /// List(entries) { … }.defaultScrollAnchor(.bottom, for: .sizeChanges)
    ///
    /// // The chat's anchoring, with short content at the top.
    /// ScrollView { … }
    ///     .defaultScrollAnchor(.bottom)
    ///     .defaultScrollAnchor(.top, for: .alignment)
    /// ```
    ///
    /// A role's anchor wins over the unlabelled one wherever the two are
    /// written, as in SwiftUI. A `nil` anchor states nothing: the role goes
    /// back to the unlabelled anchor, or to none if there is none. Writing all
    /// three roles separately is the same as writing the unlabelled form.
    ///
    /// The same deviations apply as for ``defaultScrollAnchor(_:)`` — the
    /// three-edge quantisation of the opening and standing anchors, and `x`
    /// being ignored.
    ///
    /// - Parameters:
    ///   - anchor: The unit point to anchor content to, or `nil` to defer to
    ///     the unlabelled anchor.
    ///   - role: Which question this anchor answers.
    public func defaultScrollAnchor(
        _ anchor: UnitPoint?, for role: ScrollAnchorRole
    ) -> some View {
        transformEnvironment(\.scrollAnchorRoles) { $0[role] = anchor }
    }
}
