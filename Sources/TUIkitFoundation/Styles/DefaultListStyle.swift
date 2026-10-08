//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DefaultListStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Default

/// The list style that describes a platform's default behavior and appearance
/// for a list: in TUIkit, a bordered box — the look a list has always had
/// here, where SwiftUI's macOS default draws no border (decisions A46).
///
/// `Equatable` for the reason given under ``ListStyle``.
public struct DefaultListStyle: ListStyle, Equatable {
    /// Creates a default list style.
    public init() {}

    public var showsBorder: Bool { true }
    public var rowPadding: EdgeInsets { EdgeInsets(all: 0) }
    public var alternatingRowColors: Bool { false }
}
