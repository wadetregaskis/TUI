//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ConditionalContent.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Conditional content

/// The content an `if`/`else` produces in a table's column or row builder.
///
/// You don't use this type directly: ``TableColumnBuilder`` and
/// ``TableRowBuilder`` build it from the two branches of an `if`/`else`. It is
/// SwiftUI's name for the same thing. A view builder's `if`/`else` builds a
/// ``ConditionalView`` instead, which is a view; this type is table content
/// when both of its branches are.
public enum _ConditionalContent<TrueContent, FalseContent> {
    /// The `if` branch ran.
    case trueContent(TrueContent)

    /// The `else` branch ran.
    case falseContent(FalseContent)
}
