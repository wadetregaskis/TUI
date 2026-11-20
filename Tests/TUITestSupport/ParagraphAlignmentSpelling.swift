//  🖥️ TUI — A Terminal UI framework for Swift
//  ParagraphAlignmentSpelling.swift
//
//  The two ways an app states a paragraph's alignment (the owner's ruling
//  attralign, 2026-11-19), for the tests of `Text` and `TextEditor` to run
//  each case through both.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUI_TEST_SUPPORT && canImport(Testing)

import Foundation
import TUIFoundation

/// How a test states a paragraph's alignment.
package enum ParagraphAlignmentSpelling: String, CaseIterable, Sendable, CustomStringConvertible {
    /// SwiftUI's `alignment`: Core Text's type on the macOS 26 SDK, so macOS
    /// 26 only there; TUI's identical one elsewhere, with no gate.
    case alignment
    /// TUI's `paragraphAlignment`, on every platform and macOS.
    case paragraphAlignment

    /// The spellings this machine can run: both, but on a Mac before macOS
    /// 26, which has only TUI's. Each side is held to its own answer:
    /// `alignmentRunsWhereCoreTextHasIt` checks this list.
    package static var available: [Self] {
        if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) { return allCases }
        return [.paragraphAlignment]
    }

    package var description: String { rawValue }

    /// Sets the alignment of the paragraph `range` is in to `side`, this way.
    package func align(
        _ string: inout AttributedString, _ range: Range<AttributedString.Index>, _ side: TextAlignment
    ) {
        switch self {
        case .alignment:
            guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else {
                preconditionFailure("SwiftUI's alignment needs macOS 26 here; run only `available` spellings")
            }
            switch side {
            case .leading: string[range].alignment = .left
            case .center: string[range].alignment = .center
            case .trailing: string[range].alignment = .right
            }
        case .paragraphAlignment:
            string[range].paragraphAlignment = side
        }
    }

    /// The alignment `run` states this way, as TUI's ``TextAlignment``.
    package func alignment(of run: AttributedString.Runs.Run) -> TextAlignment? {
        switch self {
        case .alignment:
            guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else {
                preconditionFailure("SwiftUI's alignment needs macOS 26 here; run only `available` spellings")
            }
            switch run.alignment {
            case .left: return .leading
            case .center: return .center
            case .right: return .trailing
            default: return nil
            }
        case .paragraphAlignment:
            return run.paragraphAlignment
        }
    }
}

#endif
