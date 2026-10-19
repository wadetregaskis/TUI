//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PointerStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitTerminalHost

/// A style describing the appearance of the pointer (also called a cursor)
/// when it's hovered over a view — SwiftUI's `PointerStyle`.
///
/// Use the ``View/pointerStyle(_:)`` view modifier to set a view's pointer
/// style.
///
/// ## Where the pointer changes
///
/// A terminal draws the mouse pointer, and only some let an app choose its
/// shape: by name, with OSC 22, and not in the same names. TUIkit speaks to
/// the ones that document it — Ghostty from 1.0.0, kitty and foot in CSS's
/// names; iTerm2 from 3.5.0 and xterm in X11's — and leaves every other
/// terminal alone, where a style changes nothing. Read
/// ``TerminalFeatures/pointerShapes`` (`\.terminalFeatures`) to tell which is
/// the case. See *Terminal compatibility survey*, "Pointer shapes (OSC 22)".
///
/// A style a terminal has no name for — a closed hand on iTerm2, say — shows
/// that terminal's own pointer. SwiftUI's `image(_:hotSpot:)` is not available: no
/// terminal takes a picture for its pointer.
public struct PointerStyle: Hashable, Sendable {
    /// What the style asks the terminal for.
    package let shape: PointerShape

    package init(shape: PointerShape) {
        self.shape = shape
    }

    /// The pointer style that uses the default platform appearance: the arrow.
    ///
    /// Set it explicitly to override another style further out.
    public static let `default` = Self(shape: .arrow)

    /// The pointer style appropriate for selecting or inserting text in a
    /// horizontal layout: the I-beam.
    public static let horizontalText = Self(shape: .text)

    /// The pointer style appropriate for selecting or inserting text in a
    /// vertical layout: the vertical I-beam.
    public static let verticalText = Self(shape: .verticalText)

    /// The pointer style appropriate for content that opens a URL link to a
    /// webpage, document, or other item when clicked: a pointing hand.
    public static let link = Self(shape: .link)

    /// The pointer style appropriate to indicate that dragging to reposition
    /// content within specific bounds, such as panning a large image, is
    /// possible: an open hand.
    public static let grabIdle = Self(shape: .grab)

    /// The pointer style appropriate for actively dragging to reposition
    /// content within specific bounds: a closed hand.
    public static let grabActive = Self(shape: .grabbing)

    /// The pointer style appropriate for precise rectangular selection, such
    /// as selecting a portion of an image or multiple lines of text: a
    /// crosshair.
    public static let rectSelection = Self(shape: .crosshair)

    /// The pointer style appropriate to indicate that the content can be
    /// zoomed in: a magnifying glass with a plus symbol.
    public static let zoomIn = Self(shape: .zoomIn)

    /// The pointer style appropriate to indicate that the content can be
    /// zoomed out: a magnifying glass with a minus symbol.
    public static let zoomOut = Self(shape: .zoomOut)

    /// The pointer style for resizing a column, or vertical division, in
    /// either direction.
    public static let columnResize = Self(shape: .columnResize)

    /// The pointer style for resizing a row, or horizontal division, in
    /// either direction.
    public static let rowResize = Self(shape: .rowResize)

    /// The pointer style for resizing a column, or vertical division.
    ///
    /// - Parameter directions: The horizontal directions in which a column can
    ///   be resized. Both, or none, is `.columnResize`.
    /// - Returns: A pointer style for resizing a column.
    public static func columnResize(directions: HorizontalDirection.Set) -> Self {
        switch directions {
        case .leading: Self(shape: .columnResizeLeft)
        case .trailing: Self(shape: .columnResizeRight)
        default: columnResize
        }
    }

    /// The pointer style for resizing a row, or horizontal division.
    ///
    /// - Parameter directions: The vertical directions in which a row can be
    ///   resized. Both, or none, is `.rowResize`.
    /// - Returns: A pointer style for resizing a row.
    public static func rowResize(directions: VerticalDirection.Set) -> Self {
        switch directions {
        case .up: Self(shape: .rowResizeUp)
        case .down: Self(shape: .rowResizeDown)
        default: rowResize
        }
    }

    /// The pointer style for resizing a rectangular frame from a specific edge
    /// or corner.
    ///
    /// An arrow pointing away from the frame where it may only grow, toward it
    /// where it may only shrink, and both ways where it may do either.
    ///
    /// - Parameters:
    ///   - position: The position along the perimeter of the frame (its edges
    ///     and corners) from which it's resized.
    ///   - directions: The directions in which the frame can be resized.
    /// - Returns: A pointer style for resizing a frame.
    public static func frameResize(
        position: FrameResizePosition, directions: FrameResizeDirection.Set = .all
    ) -> Self {
        let outward = position.outwardShape
        switch directions {
        case .outward: return Self(shape: outward)
        case .inward: return Self(shape: position.opposite.outwardShape)
        default: return Self(shape: position.bothWaysShape)
        }
    }
}

// MARK: - A frame's compass

extension FrameResizePosition {
    /// The arrow pointing out of the frame at this position.
    fileprivate var outwardShape: PointerShape {
        switch self {
        case .top: .resizeNorth
        case .bottom: .resizeSouth
        case .leading: .resizeWest
        case .trailing: .resizeEast
        case .topLeading: .resizeNorthWest
        case .topTrailing: .resizeNorthEast
        case .bottomLeading: .resizeSouthWest
        case .bottomTrailing: .resizeSouthEast
        }
    }

    /// The arrow pointing both ways through this position.
    fileprivate var bothWaysShape: PointerShape {
        switch self {
        case .top, .bottom: .resizeNorthSouth
        case .leading, .trailing: .resizeEastWest
        case .topLeading, .bottomTrailing: .resizeNorthWestSouthEast
        case .topTrailing, .bottomLeading: .resizeNorthEastSouthWest
        }
    }

    /// The position across the frame from this one, whose outward arrow is
    /// this one's inward.
    fileprivate var opposite: Self {
        switch self {
        case .top: .bottom
        case .bottom: .top
        case .leading: .trailing
        case .trailing: .leading
        case .topLeading: .bottomTrailing
        case .topTrailing: .bottomLeading
        case .bottomLeading: .topTrailing
        case .bottomTrailing: .topLeading
        }
    }
}
