//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextInputAlertActionControl.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

/// A text field among an alert's actions is one SwiftUI's alert shows and
/// TUIkit's does not, so it is reported as left out (`DroppedMember`, owner
/// ruling RC5), where a `Text` there is left out quietly, as SwiftUI leaves it.
extension TextField: AlertActionControl {}

/// As ``TextField``'s.
extension SecureField: AlertActionControl {}
