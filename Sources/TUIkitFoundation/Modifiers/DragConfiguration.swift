//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DragConfiguration.swift
//
//  SwiftUI's macOS 26 drag and drop configurations: the operations a drag's
//  source allows, the one a destination chooses, and how a drag's previews
//  are composed.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Drag Configuration

/// The behavior of the drag, proposed by the dragging source — SwiftUI's
/// `DragConfiguration`.
///
/// The value exists; the `dragConfiguration(_:)` modifier that applies one is
/// an open question (decisions A53), so its spelling does not compile
/// here. A macOS 26 API, written from its documentation: nothing about it
/// could be measured on macOS 15.8.
public struct DragConfiguration: CustomDebugStringConvertible {
    /// Describes the drag operations suggested to destinations within the
    /// app.
    ///
    /// To create a default configuration, initialize it without parameters:
    /// on macOS, drag-to-copy.
    public struct OperationsWithinApp: Sendable {
        let allowCopy: Bool
        let allowMove: Bool
        let allowDelete: Bool

        /// A Boolean value indicating if the drag operation supports creating
        /// aliases to the dropped items.
        public var allowAlias = false

        /// Creates a value that describes the operations allowed for drags
        /// that end within the application.
        public init(allowCopy: Bool = true, allowMove: Bool = false, allowDelete: Bool = false) {
            self.allowCopy = allowCopy
            self.allowMove = allowMove
            self.allowDelete = allowDelete
        }

        /// The operations, as a set.
        var operations: DropOperation.Set {
            DragConfiguration.operations(
                copy: allowCopy, move: allowMove, delete: allowDelete, alias: allowAlias)
        }
    }

    /// Describes the suggested drag operations to other applications.
    ///
    /// Recorded: a terminal app's drags never leave it, so these are never
    /// offered to anything.
    public struct OperationsOutsideApp: Sendable {
        let allowCopy: Bool
        let allowMove: Bool
        let allowDelete: Bool

        /// A Boolean value indicating if the drag operation supports creating
        /// aliases to the dropped items.
        public var allowAlias = false

        /// Creates a value that describes the operations allowed for drags to
        /// other applications.
        public init(allowCopy: Bool = true, allowMove: Bool = false, allowDelete: Bool = false) {
            self.allowCopy = allowCopy
            self.allowMove = allowMove
            self.allowDelete = allowDelete
        }

        /// The operations, as a set.
        var operations: DropOperation.Set {
            DragConfiguration.operations(
                copy: allowCopy, move: allowMove, delete: allowDelete, alias: allowAlias)
        }
    }

    /// The operations suggested by the drag source for drags within the
    /// application.
    public var operationsWithinApp: OperationsWithinApp

    /// The operations suggested by the drag source for drags to other
    /// applications.
    public var operationsOutsideApp: OperationsOutsideApp

    /// Creates a default drag configuration with operation `.copy` support
    /// for drags within the application and to other applications.
    public init(
        operationsWithinApp: OperationsWithinApp = .init(),
        operationsOutsideApp: OperationsOutsideApp = .init()
    ) {
        self.operationsWithinApp = operationsWithinApp
        self.operationsOutsideApp = operationsOutsideApp
    }

    /// Creates a drag configuration that can support drag-to-move in addition
    /// to drag-to-copy — within the app and, as on macOS, to other apps.
    public init(allowMove: Bool) {
        self.init(
            operationsWithinApp: OperationsWithinApp(allowMove: allowMove),
            operationsOutsideApp: OperationsOutsideApp(allowMove: allowMove))
    }

    /// Creates a drag configuration that can support drag-to-move and
    /// drag-to-delete in addition to drag-to-copy.
    public init(allowMove: Bool, allowDelete: Bool) {
        self.init(
            operationsWithinApp: OperationsWithinApp(allowMove: allowMove, allowDelete: allowDelete),
            operationsOutsideApp: OperationsOutsideApp(allowMove: allowMove, allowDelete: allowDelete))
    }

    /// `DragConfiguration(operationsWithinApp: [.copy, .move],
    /// operationsOutsideApp: [.copy])`.
    public var debugDescription: String {
        "DragConfiguration(operationsWithinApp: \(operationsWithinApp.operations), "
            + "operationsOutsideApp: \(operationsOutsideApp.operations))"
    }

    /// The operations a source allowing these offers.
    fileprivate static func operations(copy: Bool, move: Bool, delete: Bool, alias: Bool) -> DropOperation.Set {
        var set: DropOperation.Set = []
        if copy { set.insert(.copy) }
        if move { set.insert(.move) }
        if delete { set.insert(.delete) }
        if alias { set.insert(.alias) }
        return set
    }
}

// MARK: - Drop Configuration

/// Describes the behavior of the drop — SwiftUI's `DropConfiguration`, the
/// operation a drop destination chooses.
///
/// The value exists; the `dropConfiguration(_:)` modifier that asks a
/// destination for one is an open question (decisions A53). A macOS 26
/// API, written from its documentation.
public struct DropConfiguration {
    /// The drop operation that the drop chooses to perform.
    public let operation: DropOperation

    /// Specifies the number of items that the drop side wants to accept, or
    /// `nil` for all of them. On macOS, the number is displayed as a cursor
    /// badge.
    public var acceptedItemCount: Int?

    /// Creates a configuration value with the operation chosen by the drop
    /// destination.
    ///
    /// - Parameter operation: The drop operation that the drop destination
    ///   chooses to perform on the drop.
    public init(operation: DropOperation) {
        self.operation = operation
    }
}

// MARK: - Previews Formation

/// Describes the way the dragged previews are visually composed — SwiftUI's
/// `DragDropPreviewsFormation`. Both drag sources and drop destinations can
/// specify their desired preview formation.
///
/// The value exists; the `dragPreviewsFormation(_:)` and
/// `dropPreviewsFormation(_:)` modifiers that apply one are an open question
/// (decisions A53), so their spellings do not compile here.
public struct DragDropPreviewsFormation: Hashable, Sendable, CustomStringConvertible {
    /// Which formation this is.
    private let name: String

    /// System-determined composition.
    public static let `default` = Self(name: "default")

    /// Drag images are laid out vertically, non-overlapping, and the left
    /// edges are aligned.
    public static let list = Self(name: "list")

    /// Drag images maintain their set positions relative to each other.
    public static let none = Self(name: "none")

    /// Drag images are placed on top of each other with random rotations.
    public static let pile = Self(name: "pile")

    /// Drag images are laid out overlapping diagonally.
    public static let stack = Self(name: "stack")

    /// `.stack`.
    public var description: String { "." + name }
}
