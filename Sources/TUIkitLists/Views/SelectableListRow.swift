//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SelectableListRow.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitFoundation

// MARK: - List Row Type

/// Defines the type of a row in a List, controlling selectability and focus behavior.
///
/// Section headers and footers are non-selectable visual separators, while content rows
/// are individually selectable and focusable. This enum provides type-safe classification.
public enum ListRowType<SelectionValue: Hashable & Sendable>: Sendable, Equatable {
    /// A section header (non-selectable, non-focusable).
    ///
    /// Headers render with dimmed styling and never participate in selection or focus.
    case header

    /// A content row with a selectable ID.
    ///
    /// Content rows are individually selectable and focusable. The associated ID
    /// is used for selection binding and focus navigation.
    case content(id: SelectionValue)

    /// A section footer (non-selectable, non-focusable).
    ///
    /// Footers render with dimmed styling and never participate in selection or focus.
    case footer

    /// A content row the selection cannot name (non-selectable, non-focusable).
    ///
    /// A static row — `List(selection:) { Text("alpha") }` — has no identity of
    /// its own, so the only id it can be given is its index. That works when
    /// the selection is an `Int`, and cannot be expressed at all when it is a
    /// `String`, a `UUID` or a `Set` of either. Such a row is drawn like
    /// ordinary content and simply left out of selection, which is what
    /// SwiftUI does with a row carrying no `tag(_:)`.
    ///
    /// It exists because the alternative was worse: the extraction used to
    /// `continue` past a row whose index would not cast, so a whole list of
    /// static rows silently rendered as the empty placeholder.
    case unselectable
}

extension ListRowType {
    /// Whether a list's stripe count counts this row: every row but a
    /// section's header and footer, on across the sections, as a macOS list
    /// counts them (decisions B-D6L-4) — a row the selection cannot name
    /// too, which is drawn as a content row is.
    var countsAsStripedRow: Bool {
        switch self {
        case .header, .footer: false
        case .content, .unselectable: true
        }
    }
}

// MARK: - Selectable List Row

/// A List row with type information for selection and focus handling.
///
/// This structure replaces the generic ListRow to provide type-safe classification
/// of rows as headers, content, or footers. The type determines:
/// - Whether the row is selectable/focusable
/// - How the row renders (dimmed for headers/footers, normal for content)
/// - Whether the row ID participates in selection binding
///
/// The row's ``buffer`` and ``badge`` are rendered lazily (see
/// `LazyListRowContent`): a `List` builds one row per item but only the rows
/// in the visible window are ever rendered. ``type``/``id``/``isSelectable``
/// are resolved eagerly and cheaply, which is all the scroll/selection handler
/// needs for off-screen rows.
public struct SelectableListRow<SelectionValue: Hashable & Sendable>: Sendable {
    /// The row type (header, content with ID, or footer).
    public let type: ListRowType<SelectionValue>

    /// The lazily-rendered buffer + badge for this row.
    let content: LazyListRowContent

    /// A background this row paints instead of the one its type would choose —
    /// how the reorder drop slot carries the "you are steering this" emphasis.
    ///
    /// It has to be painted by the row renderer rather than baked into the
    /// buffer: the leading selection gutter is added around the buffer, so a
    /// background inside it starts one cell late and leaves the row's first
    /// cell at the terminal default.
    ///
    /// A ``RowBackground`` rather than a `Color` so the slot can BREATHE the
    /// way the cursor row does — through the same machinery, so the slot's
    /// lines get their runs without a second path to maintain.
    var backgroundOverride: RowBackground = .none

    /// The rendered content buffer.
    ///
    /// Forces the lazy render on first access (then memoised). Only ever read
    /// for rows in the visible window, so off-screen rows never render.
    @MainActor public var buffer: FrameBuffer {
        // Borrowed through, so a read of a row's buffer copies nothing at
        // either level — see ``LazyListRowContent/buffer``.
        _read { yield content.buffer }
    }

    /// The badge value for this row (from environment). Forces the lazy render.
    @MainActor public var badge: BadgeValue? { content.badge }

    /// The prominence written around the row's own `.badge(_:)`, or `nil` for
    /// the list's — see ``LazyListRowContent/badgeProminence``. Forces the
    /// lazy render.
    @MainActor var badgeProminence: BadgeProminence? { content.badgeProminence }

    /// ``badge``, without rendering the row to find there is none — see
    /// ``LazyListRowContent/carriesBadge``.
    @MainActor var badgeWithoutRendering: BadgeValue? { content.carriesBadge ? content.badge : nil }

    /// ``buffer``'s width without rendering, where the content can answer —
    /// see ``LazyListRowContent/widthWithoutRendering``.
    @MainActor var widthWithoutRendering: Int? { content.widthWithoutRendering }

    /// The identity this row's content renders under, or `nil` for chrome and
    /// the eager fallbacks. Computed, not stored — see
    /// ``LazyListRowContent/rowIdentity``. Forces nothing.
    var rowIdentity: ViewIdentity? { content.rowIdentity }

    /// Creates a selectable list row with type, buffer, and optional badge.
    ///
    /// The buffer is already rendered; use this for chrome (section
    /// headers/footers) and fallback single-row cases. The hot ForEach path
    /// uses the lazy initializer instead.
    ///
    /// - Parameters:
    ///   - type: The row type (header, content, or footer).
    ///   - buffer: The rendered row content.
    ///   - badge: The badge value for this row (default: nil).
    public init(type: ListRowType<SelectionValue>, buffer: FrameBuffer, badge: BadgeValue? = nil) {
        self.type = type
        self.content = LazyListRowContent(buffer: buffer, badge: badge)
    }

    /// Creates a selectable list row whose content is rendered on demand.
    init(type: ListRowType<SelectionValue>, content: LazyListRowContent) {
        self.type = type
        self.content = content
    }

    /// Indicates whether this row can be selected and focused.
    ///
    /// Only content rows are selectable. Headers and footers are always false.
    public var isSelectable: Bool {
        if case .content = type {
            return true
        }
        return false
    }

    /// The row ID if this is a content row, otherwise nil.
    ///
    /// Only content rows have an ID. Headers, footers and unselectable rows
    /// always return nil.
    public var id: SelectionValue? {
        if case .content(let id) = type {
            return id
        }
        return nil
    }
}
