//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Visibility.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Visibility

/// Visibility options for list row separators.
///
/// Matches SwiftUI's Visibility enum for API compatibility.
public enum Visibility: Sendable {
    /// The separator is automatically shown or hidden based on context.
    case automatic

    /// The separator is always visible.
    case visible

    /// The separator is always hidden.
    case hidden
}

extension Visibility: Equatable {}
