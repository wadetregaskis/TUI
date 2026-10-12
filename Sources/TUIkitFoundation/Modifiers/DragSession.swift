//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DragSession.swift
//
//  SwiftUI's descriptions of a drag in progress, as its source and as a
//  destination see it: macOS 26's `DragSession` and `DropSession`, with
//  their phases and identifiers.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Drag Session

/// Describes the ongoing dragging session — SwiftUI's `DragSession`, as a
/// drag's source sees it.
///
/// The values exist; nothing in TUIkit hands one out yet. SwiftUI's
/// `onDragSessionUpdated(_:)`, which reports them, is an open question
/// (decisions A53), so its spelling does not compile here.
///
/// A macOS 26 API, so nothing about it could be measured on the machine this
/// was written on (macOS 15.8): it follows SwiftUI's documentation, and its
/// descriptions are TUIkit's own spelling.
public struct DragSession: Identifiable {
    /// The identifier of a drag session.
    ///
    /// SwiftUI's `matches(_:)`, which compares one with AppKit's
    /// `NSDraggingSession`, is not here: a TUIkit drag is never AppKit's.
    public struct ID: Hashable, Sendable, CustomDebugStringConvertible {
        /// The drag's number, counted up per drag for the life of the app.
        let raw: UInt64

        /// `DragSession.ID(3)`.
        public var debugDescription: String { "DragSession.ID(\(raw))" }
    }

    /// The phase of the current drag session.
    public enum Phase: Hashable, Sendable, CustomStringConvertible {
        /// The drag session is about to begin.
        case initial
        /// The drag has moved to a new location.
        case active
        /// The drag has ended, with the operation it ended in: `.cancel` for a
        /// drag that nothing took.
        case ended(DropOperation)
        /// Dragged items have been transferred. You can remove temporary
        /// items, perform any cleanup if needed.
        case dataTransferCompleted

        /// `.ended(.move)`.
        public var description: String {
            switch self {
            case .initial: ".initial"
            case .active: ".active"
            case .ended(let operation): ".ended(.\(operation))"
            case .dataTransferCompleted: ".dataTransferCompleted"
            }
        }
    }

    /// The identifier of the drag session.
    public let id: ID

    /// The current phase of the drag session.
    public let phase: Phase

    /// Location of the drag session in the local coordinate space — in the
    /// source view's own cells, a ``CellPoint`` where SwiftUI's is a `CGPoint`
    /// (§2.2 of `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`).
    public var location: CellPoint

    /// The index of the dragged item under the cursor.
    public let draggedItemIndex: Int

    /// The identifiers of the dragged items, in the drag's order.
    let itemIDs: [AnyHashable]

    /// A session as its source sees it at one moment of the drag.
    init(id: ID, phase: Phase, location: CellPoint, draggedItemIndex: Int = 0, itemIDs: [AnyHashable] = []) {
        self.id = id
        self.phase = phase
        self.location = location
        self.draggedItemIndex = draggedItemIndex
        self.itemIDs = itemIDs
    }

    /// The identifiers of the currently dragged items, when the items are
    /// `Identifiable` or their identifiers were given separately.
    ///
    /// - Parameter type: The type of the identifiers.
    /// - Returns: The identifiers of the dragged items that are of `type`, or
    ///   an empty array when none is.
    public func draggedItemIDs<ItemID: Hashable>(for type: ItemID.Type) -> [ItemID] {
        itemIDs.compactMap { $0.base as? ItemID }
    }
}

// MARK: - Drop Session

/// Describes a drag over a drop destination — SwiftUI's `DropSession`, as the
/// destination sees it.
///
/// The values exist; nothing in TUIkit hands one out yet — see
/// ``DragSession``, and decisions A53 for `onDropSessionUpdated(_:)`
/// and `dropConfiguration(_:)`, which do in SwiftUI. A macOS 26 API, written
/// from its documentation.
public struct DropSession: Identifiable, CustomDebugStringConvertible {
    /// The identifier of a drop session.
    ///
    /// SwiftUI's `matches(_:)`, which compares one with AppKit's
    /// `NSDraggingInfo`, is not here: a TUIkit drag is never AppKit's.
    public struct ID: Hashable, Sendable, CustomStringConvertible {
        /// The drag's number — the same as its ``DragSession/ID``'s.
        let raw: UInt64

        /// `DropSession.ID(3)`.
        public var description: String { "DropSession.ID(\(raw))" }
    }

    /// The phase of the current drop session.
    public enum Phase: Hashable, Sendable, CustomStringConvertible {
        /// The drop session is entering the drop destination.
        case entering
        /// The drop session is active inside the drop destination.
        case active
        /// The drop session has exited the drop destination.
        case exiting
        /// The drop has ended, with the operation it ended in.
        case ended(DropOperation)
        /// Dragged items have been transferred. You can remove temporary
        /// items, perform any cleanup if needed.
        case dataTransferCompleted

        /// `.ended(.copy)`.
        public var description: String {
            switch self {
            case .entering: ".entering"
            case .active: ".active"
            case .exiting: ".exiting"
            case .ended(let operation): ".ended(.\(operation))"
            case .dataTransferCompleted: ".dataTransferCompleted"
            }
        }
    }

    /// Describes a session that originated within the app — which, in a
    /// terminal, every session does.
    public struct LocalSession {
        /// The identifiers of the dragged items, in the drag's order.
        let itemIDs: [AnyHashable]

        /// The identifiers of the currently dragged items, if the drag started
        /// within the application and its items have identifiers.
        ///
        /// - Parameter type: The type of the identifiers.
        /// - Returns: The identifiers of the dragged items that are of `type`,
        ///   or an empty array when none is.
        public func draggedItemIDs<ItemID: Hashable>(for type: ItemID.Type) -> [ItemID] {
            itemIDs.compactMap { $0.base as? ItemID }
        }
    }

    /// The unique identifier of the drop session.
    public let id: ID

    /// The phase of the current drop session.
    public let phase: Phase

    /// Location of the drop in the local coordinate space — the destination's
    /// own cells, a ``CellPoint`` where SwiftUI's is a `CGPoint`, as
    /// ``DropInfo/location`` is.
    public var location: CellPoint

    /// Size of the drop destination view, in cells.
    public var size: CellSize

    /// Number of items for the drop.
    public var itemsCount: Int

    /// Information about the session if it originated within the app — never
    /// `nil` here, since a terminal app's drags all start inside it.
    public var localSession: LocalSession?

    /// Operations suggested by the drag source.
    public var suggestedOperations: DropOperation.Set

    /// A session as a destination sees it at one moment of the drag.
    init(
        id: ID, phase: Phase, location: CellPoint, size: CellSize, itemsCount: Int = 1,
        localSession: LocalSession? = LocalSession(itemIDs: []),
        suggestedOperations: DropOperation.Set = .copy
    ) {
        self.id = id
        self.phase = phase
        self.location = location
        self.size = size
        self.itemsCount = itemsCount
        self.localSession = localSession
        self.suggestedOperations = suggestedOperations
    }

    /// `DropSession(id: 3, phase: .active, location: (2, 1), size: 10×4,
    /// itemsCount: 1, suggestedOperations: [.copy])`.
    public var debugDescription: String {
        "DropSession(id: \(id.raw), phase: \(phase), location: (\(location.x), \(location.y)), "
            + "size: \(size.width)×\(size.height), itemsCount: \(itemsCount), "
            + "suggestedOperations: \(suggestedOperations))"
    }
}
