//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollView+Canvas.swift
//
//  What a scroll view publishes for its content's canvas — the visible
//  viewport's size and the vertical window a lazy stack bands itself to — and
//  how a subtree drawn elsewhere forgets it.
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Viewport size publication

/// The size, in cells, of the innermost enclosing ``ScrollView``'s visible viewport
/// — its content area, excluding any scrollbar column.
///
/// ``ScrollView`` publishes this into the environment so a descendant can size
/// itself relative to the *visible* area rather than the (deliberately unbounded
/// on the scroll axis) proposed size. ``Image`` consumes it for
/// ``ImageFitTarget/viewport``. `nil` when there is no enclosing scroll view.
package struct ScrollViewportSize: Sendable, Hashable {
    package var width: Int
    package var height: Int
}

private struct ScrollViewportSizeKey: EnvironmentKey {
    static let defaultValue: ScrollViewportSize? = nil
}

extension EnvironmentValues {
    /// The innermost enclosing ``ScrollView``'s visible viewport size — see
    /// ``ScrollViewportSize``.
    ///
    /// A read DECLARES itself (``VolatileReadTracker/recordUnkeyedRead()``), so
    /// the memos decline to keep whatever depended on it: no memo keys on the
    /// viewport, and under a two-axis view the extent they do key on can stay
    /// put while it moves — a resize, or the column a vertical bar takes.
    /// Only a view that sizes itself to the viewport reads it.
    package var scrollViewportSize: ScrollViewportSize? {
        get {
            volatileReadTracker?.recordUnkeyedRead()
            return self[ScrollViewportSizeKey.self]
        }
        set { self[ScrollViewportSizeKey.self] = newValue }
    }
}

// MARK: - Scroll Content Window

/// The vertical slice of the scroll content that is currently visible: the
/// scroll `offset` (in content lines) and the viewport `height`. A vertical
/// ``ScrollView`` publishes this so its *direct* content — specifically a
/// ``LazyVStack`` — can render only the rows intersecting the viewport (true
/// viewport windowing) rather than materialising every row into the ScrollView's
/// tall measure canvas. `nil` when there is no enclosing vertical scroll view.
///
/// Consumed once: the responding stack clears it for its children, so it only
/// affects a `LazyVStack` sitting at the scroll content's origin. A `LazyVStack`
/// nested below other content isn't at `offset == 0` in the ScrollView's
/// coordinate space, so it is left un-windowed (renders normally). A `Section`
/// that draws a header or footer around its content hands the window on moved
/// below its header (`ScrollWindowRelay`), since single-child steps still lead
/// from the content to a stack there.
private struct ScrollContentWindowKey: EnvironmentKey {
    static let defaultValue: ScrollContentWindow? = nil
}

extension EnvironmentValues {
    /// The visible vertical slice a ``LazyVStack`` should window to — see
    /// ``ScrollContentWindow``.
    var scrollContentWindow: ScrollContentWindow? {
        get { self[ScrollContentWindowKey.self] }
        set { self[ScrollContentWindowKey.self] = newValue }
    }

    /// Forgets the canvas an enclosing ``ScrollView`` published for its content
    /// — ``scrollViewportSize``, `asksWholeContentWidth` and
    /// ``scrollContentWindow`` — for a subtree drawn somewhere else. Called
    /// through `RenderContext.leaveScrollCanvas()`, which forgets the content
    /// origin the scroll view marks on the context as well.
    ///
    /// A sheet, a popover, an alert or a pop-up menu is attached inside the
    /// content that presents it, but drawn over the screen, and its context
    /// starts as the presenter's. So a sheet presented from a horizontal strip
    /// of thumbnails fitted its image to the STRIP's viewport — a photo a few
    /// rows tall in the middle of a full-screen sheet — and a lazy stack in it
    /// answered for all its rows as if it were the strip's canvas.
    ///
    /// Writes only what is set, since most presenters sit in no scroll view.
    /// The viewport is tested through its key rather than its getter, which
    /// would declare a volatile read and stop every memo above from storing.
    mutating func leaveScrollCanvas() {
        if self[ScrollViewportSizeKey.self] != nil { self[ScrollViewportSizeKey.self] = nil }
        if asksWholeContentWidth { asksWholeContentWidth = false }
        if scrollContentWindow != nil { scrollContentWindow = nil }
    }
}

extension RenderContext {
    /// Forgets the canvas an enclosing ``ScrollView`` published for its content
    /// — the environment's share (``EnvironmentValues/leaveScrollCanvas()``)
    /// and the content origin marked on the context itself
    /// (`scrollContentOriginDepth`) — for a subtree drawn somewhere else.
    ///
    /// The origin has to go with the rest: a lazy stack in a sheet presented
    /// from inside a scroll view is not in that scroll view's content, and
    /// told it was, it would measure every row its budget reaches rather than
    /// the sample, for a drawing that is not there.
    package mutating func leaveScrollCanvas() {
        environment.leaveScrollCanvas()
        scrollContentOriginDepth = 0
    }

    /// For a subtree drawn BELOW the scroll content's origin, inside the same
    /// canvas: the rows of a windowed stack, which consumes the window itself
    /// or draws them whole. The window is withheld, so nothing below bands
    /// itself against it, and the origin is marked passed
    /// (`RenderContext.belowScrollContentOrigin`), so a lazy stack below knows
    /// at measure time that it will be drawn whole
    /// (`_VStackCore.isNestedInScrollContent`).
    ///
    /// Both halves, because the window only reaches a render and the mark is
    /// what a measure reads: withholding the window alone left a lone lazy
    /// stack in an outer one — or a custom view whose body is that stack —
    /// drawn whole by the render into the height its measure had ESTIMATED,
    /// since single-child steps lead to it from the content and the depth
    /// alone read it as the stack the window bands. Outside scroll content
    /// there is no origin to pass, and none is marked.
    ///
    /// Writes only what is set: a measure carries no window.
    mutating func leaveScrollOrigin() {
        if environment.scrollContentWindow != nil { environment.scrollContentWindow = nil }
        if scrollContentOriginDepth != 0 {
            scrollContentOriginDepth = Self.belowScrollContentOrigin
        }
    }
}
