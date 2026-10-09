//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableRowBuilder.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Table Row Builder

/// A result builder that creates table row content from closures.
///
/// The `buildBlock` methods in this type create ``TableRowContent`` instances
/// based on the number and types of sources provided as parameters. Don't use
/// this type directly; the `rows` parameter of the ``Table`` initializers is
/// annotated with it, and so is `ForEach`'s row content.
///
/// An `if` and an `if`/`else` compose rows; a `for` loop does not, exactly as
/// in SwiftUI — ``ForEach`` builds rows from a collection.
@MainActor
@resultBuilder
public struct TableRowBuilder<Value: Identifiable> {
    /// Creates a single row result.
    public static func buildExpression<Content: TableRowContent>(_ content: Content) -> Content
    where Value == Content.TableRowValue {
        content
    }

    /// Creates a single row result.
    public static func buildBlock<C: TableRowContent>(_ content: C) -> C
    where Value == C.TableRowValue {
        content
    }

    /// Produces optional row content for an `if` with no `else`.
    public static func buildIf<C: TableRowContent>(_ content: C?) -> C?
    where Value == C.TableRowValue {
        content
    }

    /// Creates a row result for the first of two row content alternatives:
    /// the `if` branch of an `if`/`else`.
    public static func buildEither<T: TableRowContent, F: TableRowContent>(
        first: T
    ) -> _ConditionalContent<T, F>
    where Value == T.TableRowValue, T.TableRowValue == F.TableRowValue {
        .trueContent(first)
    }

    /// Creates a row result for the second of two row content alternatives:
    /// the `else` branch of an `if`/`else`.
    public static func buildEither<T: TableRowContent, F: TableRowContent>(
        second: F
    ) -> _ConditionalContent<T, F>
    where Value == T.TableRowValue, T.TableRowValue == F.TableRowValue {
        .falseContent(second)
    }

    /// Unavailable, as it is in SwiftUI: an `if #available(…)` goes around
    /// the table rather than inside its rows.
    @available(
        *, unavailable,
        message: "add 'if #available' version check around the Table instead"
    )
    public static func buildLimitedAvailability(
        _ content: some TableRowContent<Value>
    ) -> some TableRowContent<Value> {
        content
    }
}
