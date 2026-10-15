//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollStepUnitTestSupport.swift
//
//  The scroll target behaviour that makes a `List` or `Table` step in a given
//  unit, for the suites that run under both — they were written against
//  `ScrollGranularity`'s `.row`, which `.scrollTargetBehavior(.viewAligned)`
//  replaced.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUIkitTestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitTestSupport

extension ScrollStepUnit {
    /// The scroll target behaviour a list steps in this unit under:
    /// `.viewAligned` for whole rows, none for lines.
    var behavior: any ScrollTargetBehavior {
        self == .row ? ViewAlignedScrollTargetBehavior() : _FreeScrollTargetBehavior()
    }
}

#endif
