//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DropOperation.swift
//
//  SwiftUI's description of what a drop does — the values a drop delegate
//  proposes — and the drop's location.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Drop Operation

/// What a drop does with what it carries — SwiftUI's `DropOperation`, which a
/// ``DropProposal`` names.
///
/// Drags in TUIkit never leave the app, and nothing is drawn at the pointer to
/// say which operation is proposed, so of these only ``cancel`` and
/// ``forbidden`` change what happens: either refuses the drop. The others
/// accept it, and what they mean to the data is the app's to carry out.
public enum DropOperation: Hashable, Sendable {
    /// Cancel the drag: nothing is dropped.
    case cancel
    /// The drop is not allowed here.
    case forbidden
    /// Copy the data to the view.
    case copy
    /// Move the data to the view.
    case move
    /// Delete the data.
    case delete
    /// Link to the data.
    case alias

    /// A set of drop operations — SwiftUI's `DropOperation.Set`.
    ///
    /// The raw values are TUIkit's own: SwiftUI does not document its.
    public struct Set: OptionSet, Hashable, Sendable, CustomStringConvertible {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// Cancel the operation.
        public static let cancel = Self(rawValue: 1 << 0)
        /// Copy the data to the modified view.
        public static let copy = Self(rawValue: 1 << 1)
        /// Move the data to the modified view.
        public static let move = Self(rawValue: 1 << 2)
        /// The operation is not allowed.
        public static let forbidden = Self(rawValue: 1 << 3)
        /// Delete the data.
        public static let delete = Self(rawValue: 1 << 4)
        /// Link to the data.
        public static let alias = Self(rawValue: 1 << 5)

        /// The members, `[.copy, .move]`.
        public var description: String {
            let names: [(Self, String)] = [
                (.cancel, ".cancel"), (.copy, ".copy"), (.move, ".move"),
                (.forbidden, ".forbidden"), (.delete, ".delete"), (.alias, ".alias"),
            ]
            return "[" + names.filter { contains($0.0) }.map(\.1).joined(separator: ", ") + "]"
        }
    }
}

// MARK: - Drop Proposal

/// The operation a drop delegate proposes for a drop — SwiftUI's
/// `DropProposal`.
public struct DropProposal: Sendable, CustomDebugStringConvertible {
    /// The operation the drop would perform.
    public let operation: DropOperation

    /// The operation for a drop outside the source application. Recorded; a
    /// TUIkit drag never leaves its application, so it never applies.
    public let operationOutsideApplication: DropOperation?

    /// A proposal of `operation`, wherever the drop is.
    public init(operation: DropOperation) {
        self.operation = operation
        self.operationOutsideApplication = nil
    }

    /// A proposal of one operation within the application and another
    /// outside it.
    public init(withinApplication: DropOperation, outsideApplication: DropOperation) {
        self.operation = withinApplication
        self.operationOutsideApplication = outsideApplication
    }

    /// `DropProposal(operation: .move)`.
    public var debugDescription: String {
        guard let operationOutsideApplication else { return "DropProposal(operation: .\(operation))" }
        return "DropProposal(withinApplication: .\(operation), outsideApplication: .\(operationOutsideApplication))"
    }
}
