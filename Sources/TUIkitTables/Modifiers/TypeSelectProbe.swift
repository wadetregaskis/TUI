//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TypeSelectProbe.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

/// Whether a render is asking a table's view cell for its type-select text:
/// the cell answers with the text its view states, where it states one, rather
/// than drawing (`_TableCellSource.content`). Set on a measuring context only,
/// and read only by that cell closure, so nothing drawn or kept ever sees it.
private struct TypeSelectProbeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// See `TypeSelectProbeKey`.
    var isTypeSelectProbe: Bool {
        get { self[TypeSelectProbeKey.self] }
        set { self[TypeSelectProbeKey.self] = newValue }
    }
}
