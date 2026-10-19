//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowChromeState.swift
//
//  The rows the window's bars hold from one frame to the next: last frame's
//  answer, adopted a frame after the walk that changed it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Window Chrome State

/// What the window's chrome holds, frame to frame: how many rows of content
/// each bar keeps, so the chrome host can reserve them BEFORE the content draws.
///
/// The content is what declares the bars, as it draws, so the rows a frame is
/// laid out against cannot be this walk's answer — finding it would take
/// another walk, thrown away, and a walk thrown away runs effects for a tree
/// nobody sees (the effect leak `RenderPassScopeTests` pinned for as long as
/// the run loop re-rendered on a header-height change). So a bar's rows are
/// LAST frame's answer (the A28 design study's policy P2):
///
/// - Each frame is laid out against the reservation and drawn honestly at it.
///   A bar that grew this walk is cut to its reserved rows; one that shrank or
///   went is padded with its own background.
/// - After the walk the chrome host compares what the content declared with
///   what it reserved (``settle(_:wanting:)``). A difference is adopted for the
///   NEXT frame, and that frame is asked for, so a still screen still gets it.
/// - Frame 1 has no last frame: the run loop's first-frame measuring walk
///   ``seed(_:rows:)``s it, so an app that declares its chrome once at the root
///   never sees a frame without it.
///
/// A frame is therefore one walk, always, after the first. The price is that
/// a bar appears or goes a frame (≥ 16.7 ms) late.
///
/// ## Oscillation
///
/// A page whose layout at the smaller height stops declaring a bar — a
/// `ViewThatFits` that picks a variant without one — would flip every frame:
/// reserve, lose the declaration, release, regain it. Two rules hold it still:
///
/// - A bar is never released in the frame after it was reserved. The release
///   waits a frame (which is asked for), so a one-frame bounce costs nothing.
/// - A bar that changes back and forth three times within
///   ``oscillationWindow`` frames is PINNED at the larger of the two, and the
///   flip is reported on the diagnostic channel. It stays pinned while the
///   content keeps declaring either of the two, for ``pinNanos``; then the
///   declaration is adopted again, in case the flipping was a person changing
///   pages faster than the guard can tell from a layout that cannot settle. A
///   declaration of anything else is a real change, and unpins it at once.
package final class WindowChromeState: @unchecked Sendable {
    /// Which of the window's bars.
    package enum Edge: CaseIterable {
        /// The top toolbar, above the page.
        case top
        /// The bottom toolbar, below the page.
        case bottom
    }

    /// A toolbar item a walk declared, as the bar draws it.
    package struct ToolbarEntry {
        /// Where the item goes.
        package let placement: ToolbarItemPlacement
        /// What the item draws.
        package let view: AnyView
        /// The environment of the view that declared it.
        package let environment: EnvironmentValues
        /// The identity it was declared at.
        package let identity: ViewIdentity
        /// Whether it is a flexible ``ToolbarSpacer``: laid out as a `Spacer`.
        package var isFlexibleSpace = false
        /// The default item a ``DefaultToolbarItem`` places, or `nil`: how the
        /// window tells a sidebar button the page placed itself.
        package var defaultKind: ToolbarDefaultItemKind.Kind?
        /// Whether it is a `ToolbarTitleMenu`: the top bar draws it as its
        /// title, a pull-down, rather than beside the title.
        package var isTitleMenu = false
        /// For a ``ToolbarItemPlacement/keyboard`` item, the identity of the
        /// view that declared it: the item is shown while a text input inside
        /// that view has the focus. `nil` for every other item.
        package var keyboardScope: ViewIdentity?

        /// The memberwise initializer, spelled out because the synthesized one is internal and the
        /// toolbars (TUIkitChrome) declare these.
        package init(
            placement: ToolbarItemPlacement, view: AnyView, environment: EnvironmentValues, identity: ViewIdentity,
            isFlexibleSpace: Bool = false, defaultKind: ToolbarDefaultItemKind.Kind? = nil, isTitleMenu: Bool = false,
            keyboardScope: ViewIdentity? = nil
        ) {
            self.placement = placement
            self.view = view
            self.environment = environment
            self.identity = identity
            self.isFlexibleSpace = isFlexibleSpace
            self.defaultKind = defaultKind
            self.isTitleMenu = isTitleMenu
            self.keyboardScope = keyboardScope
        }

        /// Whether the item is shown while `focusManager` holds the focus as it
        /// does: every item but a ``ToolbarItemPlacement/keyboard`` one, which
        /// is shown while a text input inside the view that declared it has
        /// the focus.
        @MainActor
        package func isShown(focus focusManager: FocusManager?) -> Bool {
            guard let keyboardScope else { return true }
            guard let focusManager, focusManager.hasTextInputFocus,
                let focused = focusManager.focusedIdentity
            else { return false }
            return focused == keyboardScope || keyboardScope.isAncestor(of: focused)
        }
    }

    /// One bar's reservation and the history its oscillation guard reads.
    package struct Bar: Equatable {
        /// Rows of content the bar holds this frame, before its style frames
        /// them. 0 is no bar.
        var rows = 0
        /// The frame number the last adoption was recorded in, or `nil`.
        var lastChange: Int?
        /// Recent adoptions — the frame, and the rows before and after — kept
        /// for ``oscillationWindow`` frames.
        var recent: [Adoption] = []
        /// The two values the bar is flipping between, while it is pinned.
        var pinned: Set<Int>?
        /// When the pin was set, on the frame clock.
        var pinnedAtNanos: Int64 = 0
    }

    /// What settling a bar asks of the run loop.
    package enum Settlement: Equatable {
        /// Nothing: the bar is what the content declared, or is held there.
        case settled
        /// The next frame: it draws the adopted reservation, or lets a held
        /// release through.
        case nextFrame
        /// A frame at this instant on the frame clock: when a pin lapses.
        case frame(atNanos: Int64)
    }

    /// A change of reservation, as the oscillation guard remembers it.
    struct Adoption: Equatable {
        let frame: Int
        let from: Int
        let to: Int
    }

    /// How many frames back a flip counts towards pinning.
    static let oscillationWindow = 12

    /// How long a pin holds before the content's declaration is tried again:
    /// one second, sixty frames.
    static let pinNanos: Int64 = 1_000_000_000

    /// A window with no toolbar reserved yet. Spelled out because the implicit
    /// initializer is internal, and the run loop (TUIkitApp) makes one.
    package init() {}

    /// The top toolbar's reservation.
    private(set) var top = Bar()

    /// The bottom toolbar's reservation.
    private(set) var bottom = Bar()

    /// Both bars' reservations, with the history their guard reads — what
    /// ``settle(_:wanting:nowNanos:)`` changes.
    ///
    /// For a frame that walks the scene a second time (the scene root's
    /// geometry correction, `RenderLoop.renderContent`): read before the first
    /// walk and put back before the second, so the second is laid out against
    /// the rows the first was and settles from where the first did — a frame
    /// adopts a change once, for the next frame, however many walks it takes.
    package var reservation: (top: Bar, bottom: Bar) {
        get { (top, bottom) }
        set { (top, bottom) = newValue }
    }

    /// How every bar frames itself: the scene's `.windowToolbarStyle(_:)`,
    /// adopted each frame before anything is laid out. A box by default.
    package var style: ChromeStyle { get { _style } set { _style = newValue } }

    /// ``style``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _style: ChromeStyle = .bordered

    /// Whether the top bar's title slot shows ``title``: the scene's
    /// `.windowToolbarStyle(_:)` again, its `showsTitle:`.
    package var showsTitle: Bool { get { _showsTitle } set { _showsTitle = newValue } }

    /// ``showsTitle``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _showsTitle = true

    /// The style the bar at `edge` frames itself in: the window's one style.
    package func style(_ edge: Edge) -> ChromeStyle {
        style
    }

    /// What draws the window's menu bar this frame — the view the scene's
    /// commands make (`Scene.commands(content:)`, TUIkitCommands) — or `nil`
    /// for no menu bar.
    ///
    /// Set by the run loop before the walk, from the scene's configuration.
    /// A scene states its commands, so whether the bar has its row is known
    /// before anything is laid out: unlike a toolbar's rows, the menu bar's
    /// are this frame's answer, never last frame's.
    package var menuBar: AnyView? { get { _menuBar } set { _menuBar = newValue } }

    /// ``menuBar``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _menuBar: AnyView?

    /// The toolbar items this walk has declared, in the order it declared them.
    private(set) var toolbarEntries: [ToolbarEntry] = []

    /// The visibility each bar was last declared with this walk
    /// (`.toolbarVisibility(_:for:)`); absent is ``Visibility/automatic``.
    private var declaredVisibility: [BarKey: Visibility] = [:]

    /// The fill each bar was last declared with this walk
    /// (`.toolbarBackground(_:for:)`); absent is the palette's.
    private var declaredBackground: [BarKey: AnyShapeStyle] = [:]

    /// Whether the last `.toolbarRole(_:)` this walk drew keeps the title
    /// beside the top bar's principal items (`.editor`); `nil` with none.
    private var declaredTitleBesidePrincipal: Bool?

    /// Whether each bar was last declared to show its fill this walk
    /// (`.toolbarBackgroundVisibility(_:for:)`); absent is
    /// ``Visibility/automatic``.
    private var declaredBackgroundVisibility: [BarKey: Visibility] = [:]

    /// The identities of ``toolbarEntries``, so an item a walk renders twice —
    /// the first frame's measuring walk measures some views by rendering them —
    /// is declared once.
    private var declaredIdentities: Set<ViewIdentity> = []

    /// The click regions the app's line of key hints (``StatusBar``'s
    /// `init()`) registered this walk: the ones an inert bar keeps.
    ///
    /// A bar item drawn inert — every item while a modal holds the input, and
    /// one declared by a backdrop — has its click regions dropped, as its keys
    /// and focus are. The line of key hints is the exception: it shows what
    /// the app's keys do NOW (the modal's, while one is up), and a click on an
    /// item there does what the key would.
    package var appLineHandlerIDs: Set<HitTestRegion.HandlerID> { _appLineHandlerIDs }

    /// ``appLineHandlerIDs``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _appLineHandlerIDs: Set<HitTestRegion.HandlerID> = []

    /// Records the regions of the app's line of key hints, drawn this walk.
    package func noteAppLine(_ buffer: FrameBuffer) {
        for region in buffer.hitTestRegions { _appLineHandlerIDs.insert(region.handlerID) }
    }

    /// The rows of the frame the bottom bar took from the page for the
    /// tooltip it shows, as the walk drawn laid them out: from the bar's top
    /// edge down, as many as the tooltip added to the bar — its lines, and the
    /// bar's own framing when the tooltip is all the bar holds. Empty while
    /// the bar shows no tooltip.
    ///
    /// The bar grows upwards, so on a page that fills the window these were
    /// the page's last rows before the tooltip came: a pointer resting on one
    /// rests over the tooltip's own bar now, where its view was
    /// (`TooltipState.held`, decisions-HELP A-HELP-1).
    package var tooltipRows: Range<Int> { get { _tooltipRows } set { _tooltipRows = newValue } }

    /// ``tooltipRows``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _tooltipRows: Range<Int> = 0..<0

    /// The surfaces the walk drawn presented over the page — a sheet, docked
    /// or not, a cover, an alert, a popover, a menu, a drop-down — counting
    /// those presented from inside another; empty while the page is in
    /// front.
    ///
    /// What a help held on the rows the bar took for it asks: it stays while
    /// what is presented is what was when the hold began
    /// (`TooltipState.held`, decisions-HELP A-HELP-1). Taken from the
    /// layers the chrome host composites onto the content area, which every
    /// presentation is drawn as, rather than from what holds the focus: a
    /// sheet docked live beside the page never takes the input, and it still
    /// takes the rows the bar covers (found by the BUGS13 lane's second
    /// review). Each surface, not their count, which was compared until
    /// 2026-10-18: a frame that took one surface down as it put another up
    /// left the count, and the help, as they were.
    package var presentationsOverPage: [PresentedSurface] {
        get { _presentationsOverPage }
        set { _presentationsOverPage = newValue }
    }

    /// ``presentationsOverPage``'s storage: private, under the `package`
    /// accessor (CONTRIBUTING.md, "Crossing a module boundary").
    private var _presentationsOverPage: [PresentedSurface] = []

    /// The window's title: the OUTERMOST `.navigationTitle` the window's
    /// content declared this walk (see ``offer(_:as:at:)``) — kept until the
    /// next walk begins.
    ///
    /// Scene-level data: the top bar shows it in its title slot, and it is
    /// what a terminal window title (OSC 2) would be set from.
    package var title: String { titles.title }

    /// The window's subtitle: the title's own `.navigationSubtitle`, else the
    /// one that stands as a title does (see ``offer(_:as:at:)``).
    package var subtitle: String { titles.subtitle }

    /// The lines of the top bar's title slot, which the window's chrome takes
    /// from the views that declare them (`PreferenceModifier`).
    enum TitleLine {
        /// The `.navigationTitle`.
        case title
        /// The `.navigationSubtitle`, under it.
        case subtitle
    }

    /// A `.navigationTitle` or `.navigationSubtitle` a walk declared, and the
    /// identity of the view it was declared on.
    private struct TitleOffer {
        let text: String
        let identity: ViewIdentity
    }

    /// The titles this walk declared, in the order it declared them.
    private var titleOffers: [TitleOffer] = []

    /// The subtitles this walk declared, in the order it declared them.
    private var subtitleOffers: [TitleOffer] = []

    /// ``title`` and ``subtitle``, chosen from the offers the first time they
    /// are asked for after one.
    private var chosenTitles: (title: String, subtitle: String)?

    /// Offers a `.navigationTitle` or `.navigationSubtitle` declared on the
    /// view at `identity`.
    ///
    /// The window's title is the page's own, not whatever was declared last.
    /// The navigation-title preference is last-wins — the deepest view's title
    /// is the one a navigation stack wants for the screen it shows — and the
    /// window read it: a page titled "Navigation" that holds a navigation stack
    /// showed its stack's root ("Planets") over its own subtitle. Declared by
    /// the views that are drawn — a stack's covered root and presented content
    /// offer nothing (`PreferenceModifier`) — so a pushed screen's title is the
    /// window's when nothing outside the stack has one, and a sheet's never is.
    ///
    /// - The title is the outermost: one declared inside another's view never
    ///   displaces it, and of titles neither of which is inside the other, the
    ///   last declared stands, as the preference's own reduction has it. By
    ///   ANCESTRY, not by depth: compared by how deep they were declared, which
    ///   of two side by side won depended on the wrappers around each — a
    ///   `VStack` round one sibling handed the window to the other. Two
    ///   stacked on one view — `.navigationTitle("Inner")
    ///   .navigationTitle("Outer")`, with or without a `.padding()` between —
    ///   are declared at the SAME identity (a modifier renders its content at
    ///   its own), so there the first declared is the outer one, and stands,
    ///   as SwiftUI's outer preference writer overrides its content.
    /// - The subtitle is the title's own where it has one: declared on the
    ///   title's view or inside it, the outermost of those. Chosen apart from
    ///   the title, the outermost subtitle could belong to another view
    ///   entirely — a page's "Demo" under the "Planets" of a stack inside it,
    ///   where the stack's root said "9 planets".
    /// - Where the title has none, the subtitle of a view round it: the
    ///   outermost of those, as for titles.
    /// - Where nothing round it has one either, a subtitle BESIDE it, as
    ///   SwiftUI combines a sibling's preference upward — the one that stands
    ///   by the titles' own reduction (the outermost, and of several side by
    ///   side the last) among those no other title would take: not one
    ///   declared on another titled view, inside one, or round one.
    ///   `VStack { Text("H").navigationTitle("Notes"); List(…).navigationSubtitle("3 notes") }`
    ///   shows both; `HStack { Detail().navigationTitle("Inbox").navigationSubtitle("42 unread"); Inspector().navigationTitle("Info") }`
    ///   shows "Info" alone, the unread count being the inbox's. With no
    ///   title, the subtitle that stands among them all.
    ///
    /// An empty title is no title.
    func offer(_ text: String, as line: TitleLine, at identity: ViewIdentity) {
        guard !text.isEmpty else { return }
        switch line {
        case .title: titleOffers.append(TitleOffer(text: text, identity: identity))
        case .subtitle: subtitleOffers.append(TitleOffer(text: text, identity: identity))
        }
        chosenTitles = nil
    }

    /// Whether this walk drew a `.toolbar(removing: .title)`: the top bar's
    /// title slot is empty while one is drawn. ``title`` and ``subtitle`` are
    /// still the window's — what a terminal window's title would be set from.
    package var titleRemoved: Bool { _titleRemoved }

    /// ``titleRemoved``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _titleRemoved = false

    /// Records a `.toolbar(removing: .title)` the walk drew.
    package func removeTitle() {
        _titleRemoved = true
    }

    /// Whether the top bar shows ``title`` in its title slot, as this walk
    /// declared it: the walk placed items in the bar and did not hide it, the
    /// window's toolbar style shows titles, nothing removed the title, and no
    /// principal item takes its place. A bar too short for a row, or one a
    /// frame from being adopted, counts as showing it.
    ///
    /// Where it does not, a ``title`` titles the terminal's window instead
    /// (TUIkitApp's `RenderLoop.terminalWindowTitle`).
    package var topBarShowsTitle: Bool {
        guard showsTitle, !titleRemoved, !title.isEmpty else { return false }
        let entries = toolbarEntries(for: .top)
        return !entries.isEmpty && !entries.contains { $0.placement.region == .principal }
    }

    // MARK: The search field's place

    /// Whether a `DefaultToolbarItem(kind: .search)` claimed the window's
    /// search field for a bar, this frame or the last.
    ///
    /// Last frame's claim counts because a toolbar declared inside the
    /// searchable's content declares it after the searchable has drawn: the
    /// field moves a frame late, as a bar appears a frame late (see the type's
    /// own documentation). The first frame's seeding walk declares the toolbar,
    /// so the first frame drawn has it. Kept by FRAME, not by walk: a frame can
    /// begin a walk that never reaches the page, and a claim kept only to the
    /// next walk was gone by the walk that drew it.
    package var searchFieldClaimed: Bool { _searchFieldClaimedFrame.map { $0 >= frame - 1 } ?? false }

    /// The frame that last declared a `DefaultToolbarItem(kind: .search)`.
    private var _searchFieldClaimedFrame: Int?

    /// Records a `DefaultToolbarItem(kind: .search)` a walk declared.
    package func claimSearchField() {
        _searchFieldClaimedFrame = frame
    }

    /// Whether a `.toolbar(removing: .search)` was drawn, this frame or the
    /// last, for the reason ``searchFieldClaimed`` gives.
    package var searchFieldRemoved: Bool { _searchFieldRemovedFrame.map { $0 >= frame - 1 } ?? false }

    /// The frame that last drew a `.toolbar(removing: .search)`.
    private var _searchFieldRemovedFrame: Int?

    /// Records a `.toolbar(removing: .search)` a walk drew.
    package func removeSearchField() {
        _searchFieldRemovedFrame = frame
    }

    /// The field, with its scopes, that a claimed `searchable` handed over this
    /// walk for the search item to draw: the first one drawn.
    package var searchField: AnyView? { _searchField }

    /// ``searchField``'s storage.
    private var _searchField: AnyView?

    /// Hands over a claimed searchable's field, unless another drawn earlier
    /// this walk already did.
    package func offerSearchField(_ field: AnyView) {
        if _searchField == nil { _searchField = field }
    }

    // MARK: The panels' toggles

    /// A panel's toggle offered as the window's, with what an item drawing it
    /// in a bar needs: the environment of the view that offered it, and an
    /// identity under that view's for the item to keep its state at.
    package struct PanelToggleOffer {
        package let toggle: PanelToggle
        package let environment: EnvironmentValues
        package let itemIdentity: ViewIdentity
    }

    /// The window's toggle for each panel: the first offered this walk
    /// (``offerPanelToggle(_:environment:itemIdentity:)``).
    private var panelToggleOffers: [PanelToggle.Panel: PanelToggleOffer] = [:]

    /// The window's toggle for `panel` — for the sidebar, the first
    /// ``NavigationSplitView`` drawn this walk offered it — or `nil`. What a
    /// toolbar's button for the panel declared round the view that owns it,
    /// rather than inside, toggles.
    ///
    /// The first, because a view draws before its content does: a split view
    /// nested in another's column offers after the outer one, and of two side
    /// by side the first is the one a reader meets first.
    package func panelToggle(_ panel: PanelToggle.Panel) -> PanelToggle? {
        panelToggleOffers[panel]?.toggle
    }

    /// The window's toggle for `panel`, as it was offered.
    package func panelToggleOffer(_ panel: PanelToggle.Panel) -> PanelToggleOffer? {
        panelToggleOffers[panel]
    }

    /// Offers a panel's toggle as the window's, unless a view drawn earlier
    /// this walk already offered one for the same kind of panel.
    package func offerPanelToggle(
        _ toggle: PanelToggle, environment: EnvironmentValues, itemIdentity: ViewIdentity
    ) {
        guard panelToggleOffers[toggle.panel] == nil else { return }
        panelToggleOffers[toggle.panel] = PanelToggleOffer(
            toggle: toggle, environment: environment, itemIdentity: itemIdentity)
    }

    /// The frame that last drew a bar's button for each panel's toggle, by the
    /// identity of the view that owns the panel.
    private var barTogglesDrawn: [ViewIdentity: Int] = [:]

    /// The views whose panel's bar button went undrawn for a frame, since
    /// ``takeDroppedBarToggles()`` was last asked.
    private var barTogglesDropped: [ViewIdentity] = []

    /// Records that a bar drew a button toggling the panel of the view at
    /// `owner`, and returns whether that is news to it: whether
    /// ``hasBarToggle(for:)`` said `false` before. The button then redraws the
    /// view — a split view, drawn with its ▶ edge column before the bar was.
    @discardableResult
    package func noteBarToggleDrawn(for owner: ViewIdentity) -> Bool {
        let isNew = !hasBarToggle(for: owner)
        barTogglesDrawn[owner] = frame
        return isNew
    }

    /// The split views whose bar button stopped being drawn — so each must
    /// draw its ▶ edge column again — since this was last asked. The window's
    /// chrome redraws them.
    package func takeDroppedBarToggles() -> [ViewIdentity] {
        defer { barTogglesDropped.removeAll() }
        return barTogglesDropped
    }

    /// Whether a bar drew a button toggling the panel of the view at `owner`,
    /// this frame or the last.
    ///
    /// Last frame's counts because the bars are drawn after the page: a split
    /// view asks while it draws, before this frame's bars have.
    package func hasBarToggle(for owner: ViewIdentity) -> Bool {
        barTogglesDrawn[owner].map { $0 >= frame - 1 } ?? false
    }

    /// ``title`` and ``subtitle``, as ``offer(_:as:at:)`` chooses them.
    private var titles: (title: String, subtitle: String) {
        if let chosenTitles { return chosenTitles }
        let chosen = chooseTitles()
        chosenTitles = chosen
        return chosen
    }

    /// Chooses the title and its subtitle from this walk's offers: the title's
    /// own subtitle, else the outermost round it, else the one standing among
    /// those beside it that no other title would take.
    private func chooseTitles() -> (title: String, subtitle: String) {
        guard let title = Self.outermost(titleOffers) else {
            return ("", Self.outermost(subtitleOffers)?.text ?? "")
        }
        if let own = Self.outermost(subtitleOffers.filter({ Self.encloses(title, $0) })) {
            return (title.text, own.text)
        }
        if let round = Self.outermost(subtitleOffers.filter({ $0.identity.isAncestor(of: title.identity) })) {
            return (title.text, round.text)
        }
        // Beside the title: a subtitle no other title would show — one
        // declared on another titled view or inside it, or round one, is that
        // title's. Without this the window put "Info" over the "42 unread" of
        // the "Inbox" beside it, and a footer's "synced" displaced the
        // "3 notes" round the title.
        let others = titleOffers.filter { $0.identity != title.identity }
        let beside = subtitleOffers.filter { subtitle in
            !others.contains { Self.encloses($0, subtitle) || subtitle.identity.isAncestor(of: $0.identity) }
        }
        return (title.text, Self.outermost(beside)?.text ?? "")
    }

    /// Whether `inner` was declared on `outer`'s view or inside it.
    private static func encloses(_ outer: TitleOffer, _ inner: TitleOffer) -> Bool {
        outer.identity == inner.identity || outer.identity.isAncestor(of: inner.identity)
    }

    /// The offer that stands among `offers`, in declaration order: each one
    /// replaces the one standing unless that one's view encloses it.
    ///
    /// A view declares before its content renders, and a subtree renders
    /// whole before its next sibling, so an enclosing view's offer always
    /// comes first and is never replaced from inside; a later sibling's
    /// replaces it. Encloses: declared at an ancestor's identity, or at the
    /// SAME one — a modifier renders its content at its own identity, so two
    /// stacked on one view (`.navigationTitle("Inner").navigationTitle("Outer")`)
    /// offer at one identity, the outer first. `isAncestor(of:)` is strict,
    /// and alone it let the inner one displace the outer.
    private static func outermost(_ offers: [TitleOffer]) -> TitleOffer? {
        var standing: TitleOffer?
        for offer in offers {
            if let held = standing, held.identity == offer.identity || held.identity.isAncestor(of: offer.identity) {
                continue
            }
            standing = offer
        }
        return standing
    }

    /// Frames begun, counted by ``beginFrame()``.
    private(set) var frame = 0

    /// Whether the run loop's first-frame walk has seeded the reservations.
    private(set) var isSeeded = false

    /// The flips reported so far, oldest first — what a test reads instead of
    /// the diagnostic channel.
    private(set) var oscillationReports: [Edge] = []

    /// Rows of content `edge` holds this frame.
    package func rows(_ edge: Edge) -> Int {
        self[edge].rows
    }

    /// Counts a frame. Called by the run loop before the scene is walked.
    package func beginFrame() {
        frame += 1
        // A split view that stopped being toggled from a bar is forgotten once
        // its last frame has passed.
        if !barTogglesDrawn.isEmpty {
            for (owner, drawn) in barTogglesDrawn where drawn < frame - 1 {
                barTogglesDrawn[owner] = nil
                barTogglesDropped.append(owner)
            }
        }
    }

    /// Forgets the toolbar items the last walk declared. Called by the run loop
    /// before every walk of the scene: what a walk declares is that walk's.
    package func beginWalk() {
        dismissBehavior = .automatic
        toolbarEntries.removeAll(keepingCapacity: true)
        declaredIdentities.removeAll(keepingCapacity: true)
        declaredVisibility.removeAll(keepingCapacity: true)
        declaredBackground.removeAll(keepingCapacity: true)
        declaredBackgroundVisibility.removeAll(keepingCapacity: true)
        declaredTitleBesidePrincipal = nil
        _appLineHandlerIDs.removeAll(keepingCapacity: true)
        _tooltipRows = 0..<0
        _presentationsOverPage = []
        titleOffers.removeAll(keepingCapacity: true)
        subtitleOffers.removeAll(keepingCapacity: true)
        chosenTitles = nil
        _titleRemoved = false
        _searchField = nil
        panelToggleOffers.removeAll(keepingCapacity: true)
    }

    /// The window's dismiss behavior as the walk declared it
    /// (`windowDismissBehavior(_:)`): ``WindowInteractionBehavior/automatic``
    /// until a view in it says otherwise.
    package private(set) var dismissBehavior = WindowInteractionBehavior.automatic

    /// Records the dismiss behavior a view in the window declared; the last
    /// declaration wins, the one closest to the content.
    package func declareDismissBehavior(_ behavior: WindowInteractionBehavior) {
        dismissBehavior = behavior
    }

    /// A bar a bar modifier can name: one of the two toolbars, or one of the
    /// accessory bars under the top one.
    package enum BarKey: Hashable {
        case edge(Edge)
        case accessory(AccessoryBarID)
    }
    /// Records a bar visibility the walk declared. The last declaration of a
    /// bar wins — the one closest to the content it wraps, since a modifier
    /// declares before its content renders — and ``Visibility/automatic``
    /// states no preference.
    package func declare(_ visibility: Visibility, for bar: BarKey) {
        guard visibility != .automatic else { return }
        declaredVisibility[bar] = visibility
    }

    /// Whether this walk hid the bar at `edge` — or, for the top bar, the
    /// person did, from the menu bar (``topBarHiddenByCommand``).
    ///
    /// For the top bar, its own row: its accessory bars are hidden each by
    /// its own placement, and by the person's choice with the rest of the top
    /// bar (``toolbarEntries(for:)``).
    package func isHidden(_ edge: Edge) -> Bool {
        declaredVisibility[.edge(edge)] == .hidden || (edge == .top && _topBarHiddenByCommand)
    }

    /// What a bar is filled with: the palette's surface for it, a style the
    /// page stated, or nothing — the page's own background showing through.
    package enum Fill {
        /// ``Palette/appHeaderBackground`` for the top bar,
        /// ``Palette/statusBarBackground`` for the bottom one.
        case palette
        /// No fill: `.toolbarBackgroundVisibility(.hidden, for:)`.
        case hidden
        /// A `.toolbarBackground(_:for:)` style.
        case style(AnyShapeStyle)
    }

    /// Records a bar fill the walk declared. As for visibility, the last
    /// declaration of a bar wins.
    package func declareBackground(_ style: AnyShapeStyle, for bar: BarKey) {
        declaredBackground[bar] = style
    }

    /// Records whether the walk declared a bar's fill shown or not.
    /// ``Visibility/automatic`` states no preference.
    package func declareBackgroundVisibility(_ visibility: Visibility, for bar: BarKey) {
        guard visibility != .automatic else { return }
        declaredBackgroundVisibility[bar] = visibility
    }

    /// What `bar` is filled with this walk: nothing while its fill is
    /// declared hidden, else the style declared for it, else the palette's —
    /// for an accessory bar, the top bar's own fill, whatever that is.
    package func fill(_ bar: BarKey) -> Fill {
        if declaredBackgroundVisibility[bar] == .hidden { return .hidden }
        return declaredBackground[bar].map(Fill.style) ?? .palette
    }

    /// Whether this walk stated anything about `bar`'s fill: an accessory bar
    /// that states nothing is drawn on the top bar's.
    package func statesFill(_ bar: BarKey) -> Bool {
        declaredBackgroundVisibility[bar] == .hidden || declaredBackground[bar] != nil
    }

    /// Records the role a `.toolbarRole(_:)` the walk drew gives the top bar:
    /// whether its title keeps its place beside principal items. The last
    /// declaration wins, as for a bar's visibility.
    package func declareTitleBesidePrincipal(_ keeps: Bool) {
        declaredTitleBesidePrincipal = keeps
    }

    /// Whether the top bar shows its title beside its principal items this
    /// walk (`.toolbarRole(.editor)`), rather than giving them its place.
    package var titleBesidePrincipal: Bool { declaredTitleBesidePrincipal ?? false }

    /// Whether the menu bar's View ▸ Hide Toolbar (`ToolbarCommands`,
    /// TUIkitCommands) hid the top bar: the person's choice, which holds until
    /// Show Toolbar, whatever the page declares — as a window's toolbar hidden
    /// from its View menu stays hidden on macOS.
    package var topBarHiddenByCommand: Bool {
        get { _topBarHiddenByCommand }
        set { _topBarHiddenByCommand = newValue }
    }

    /// ``topBarHiddenByCommand``'s storage: private, under the `package`
    /// accessor (CONTRIBUTING.md, "Crossing a module boundary").
    private var _topBarHiddenByCommand = false

    /// Records a toolbar item the walk declared — once per identity.
    package func declare(_ entry: ToolbarEntry) {
        guard declaredIdentities.insert(entry.identity).inserted else { return }
        toolbarEntries.append(entry)
    }

    /// The items this walk declared for the toolbar at `edge`, less those a
    /// `.toolbarVisibility(.hidden, for:)` hides: the bar's own, and an
    /// accessory bar's each by its own placement. The person's View ▸ Hide
    /// Toolbar hides the top bar's accessory bars with it.
    package func toolbarEntries(for edge: Edge) -> [ToolbarEntry] {
        if edge == .top, _topBarHiddenByCommand { return [] }
        let ownHidden = isHidden(edge)
        return declaredEntries(for: edge).filter { entry in
            if let accessory = entry.placement.accessoryBar {
                return declaredVisibility[.accessory(accessory)] != .hidden
            }
            return !ownHidden
        }
    }

    /// The items this walk declared for the toolbar at `edge`, whether or not
    /// it is hidden.
    package func declaredEntries(for edge: Edge) -> [ToolbarEntry] {
        toolbarEntries.filter { $0.placement.bar == edge }
    }

    /// Takes `rows` as `edge`'s reservation outright: what the first frame's
    /// measuring walk found the content declaring.
    package func seed(_ edge: Edge, rows: Int) {
        self[edge].rows = rows
        isSeeded = true
    }

    /// Compares what the content declared for `edge` this walk with what the
    /// frame reserved, and adopts a difference for the next frame.
    ///
    /// - Parameters:
    ///   - edge: The bar.
    ///   - wanted: The rows of content the walk declared for it.
    ///   - nowNanos: This frame's instant on the frame clock, for a pin's lapse.
    /// - Returns: What the run loop owes the bar.
    package func settle(_ edge: Edge, wanting wanted: Int, nowNanos: Int64) -> Settlement {
        var bar = self[edge]
        defer { self[edge] = bar }
        bar.recent.removeAll { frame - $0.frame > Self.oscillationWindow }
        guard wanted != bar.rows else { return .settled }

        if let pinned = bar.pinned {
            if pinned.contains(wanted) {
                // Still flipping between the same two: hold the larger until
                // the pin lapses, then try the declaration again.
                let lapse = bar.pinnedAtNanos &+ Self.pinNanos
                guard nowNanos >= lapse else { return .frame(atNanos: lapse) }
                bar.recent = []
            }
            bar.pinned = nil
        }

        // Never release in the frame after reserving: wait one frame, and ask
        // for it, so a bounce that settles costs nothing and a real release
        // still happens on a still screen.
        if wanted < bar.rows, bar.lastChange == frame - 1 { return .nextFrame }

        // Back to a value two recent changes have both touched, one of them by
        // leaving it: the third flip. Hold the larger of the two.
        let flips = bar.recent.filter { $0.from == wanted || $0.to == wanted }
        if flips.count >= 2, flips.contains(where: { $0.from == wanted }) {
            let other = bar.rows
            bar.pinned = [wanted, other]
            bar.pinnedAtNanos = nowNanos
            bar.lastChange = frame
            report(edge, between: wanted, and: other)
            guard wanted > other else { return .frame(atNanos: nowNanos &+ Self.pinNanos) }
            bar.rows = wanted
            return .nextFrame
        }

        bar.recent.append(Adoption(frame: frame, from: bar.rows, to: wanted))
        bar.rows = wanted
        bar.lastChange = frame
        return .nextFrame
    }

    /// The bar's state for `edge`.
    private subscript(edge: Edge) -> Bar {
        get {
            switch edge {
            case .top: top
            case .bottom: bottom
            }
        }
        set {
            switch edge {
            case .top: top = newValue
            case .bottom: bottom = newValue
            }
        }
    }

    /// Says on the diagnostic channel that `edge` is flipping and has been
    /// pinned.
    private func report(_ edge: Edge, between first: Int, and second: Int) {
        oscillationReports.append(edge)
        DiagnosticChannel.emit(
            """
            [TUIkit] the window's \(edge) bar keeps changing between \(first) and \(second) rows \
            (frame \(frame)): the page declares it at one height and not at the other. Holding \
            the larger.

            """)
    }
}

// MARK: - Environment Key

/// Environment key for the window's chrome state.
private struct WindowChromeKey: EnvironmentKey {
    static let defaultValue: WindowChromeState? = nil
}

/// Environment key for the first frame's seeding walk.
private struct SeedsWindowChromeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether this walk is the first frame's measuring walk, which seeds the
    /// window's chrome: a `.toolbar` declares its items there although the walk
    /// measures, and nowhere else that measures. Read by the chrome host, which
    /// seeds the bars' rows from what that walk found, and by what declares
    /// what those rows depend on: `.toolbar`, `.toolbarVisibility(_:for:)`, and
    /// `.navigationTitle` / `.navigationSubtitle` (`PreferenceModifier`), whose
    /// title and subtitle are the top bar's rows.
    package var seedsWindowChrome: Bool {
        get { self[SeedsWindowChromeKey.self] }
        set { self[SeedsWindowChromeKey.self] = newValue }
    }

    /// The window's chrome state: the rows each bar holds this frame.
    ///
    /// `nil` outside a running application, as every runtime service is — a
    /// headless render of a scene reserves no chrome and draws every bar it is
    /// handed at its own height.
    package var windowChrome: WindowChromeState? {
        get { self[WindowChromeKey.self] }
        set { self[WindowChromeKey.self] = newValue }
    }
}

/// A surface presented over the page, as a frame's chrome found it
/// (``WindowChromeState/presentationsOverPage``): enough to tell two
/// presentations apart from one frame to the next.
package struct PresentedSurface: Equatable, Sendable {
    /// Whether it is placed over the content area — a sheet, a cover, an
    /// alert — rather than beside what opened it.
    package var isScreenLevel: Bool

    /// Whether it holds the input — a popover, a menu, a drop-down.
    package var holdsInput: Bool

    /// The identity of its content (`OverlayLayer.surfaceIdentity`), which
    /// it keeps while it is up, whatever that content does: another surface
    /// in its place has another. `nil` for a layer no presentation named.
    package var identity: ViewIdentity?

    package init(isScreenLevel: Bool, holdsInput: Bool, identity: ViewIdentity?) {
        self.isScreenLevel = isScreenLevel
        self.holdsInput = holdsInput
        self.identity = identity
    }
}
