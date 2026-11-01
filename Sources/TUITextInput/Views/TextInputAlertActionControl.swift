//  🖥️ TUI — A Terminal UI framework for Swift
//  TextInputAlertActionControl.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// A text field among an alert's actions is one SwiftUI's alert shows and
/// TUI's does not, so it is reported as left out (`DroppedMember`, owner
/// ruling RC5), where a `Text` there is left out quietly, as SwiftUI leaves it.
@MainActor extension TextField: AlertActionControl {}

/// As ``TextField``'s.
@MainActor extension SecureField: AlertActionControl {}
