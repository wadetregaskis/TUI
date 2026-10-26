//  🖥️ TUI — A Terminal UI framework for Swift
//  TextStyleStatements.swift
//
//  What a `TextStyle` stores for the attributes a `Text` may or may not have
//  stated: `Optional`s in all but name, spelled as enums of this module's own.
//
//  Created by Wade Tregaskis
//  License: MIT

// Why not `Optional`: the per-pass memos key a view by a hash of its value,
// and that hash may read only bytes the value defines. An optional whose `nil`
// is spelled in its payload's spare values — `Color?`, `LineLimit?`, `Font??`
// all are — has bytes that a `nil` stored by generic code never writes, so the
// hash has to read such an optional's case through `== nil` before its payload:
// a typed step, and a `Text` had four, on every measured `Text`.
//
// These are the same values, and trivial non-generic enums whose cases only
// this module builds — so every byte of every value is written, and the hash
// reads a `Text` whole, word by word (`_AllBytesDefined`,
// `AllBytesDefinedTests`). Each converts to and from the optional it replaces;
// `TextStyle`'s properties keep the optional spelling.
//
// "Only this module builds" means built where the layout is known, payload
// included: `Font` and `LineLimit` are this module's own, and `Color` — from
// TUIStyling — is `@frozen` for exactly this, as its value is. (It changes
// nothing without library evolution, which is how TUI is built.)

/// A `Color?` a `TextStyle` stores: see the note above.
enum StatedColor: Hashable, _AllBytesDefined {
    case unstated
    case stated(Color)

    init(_ color: Color?) {
        if let color { self = .stated(color) } else { self = .unstated }
    }

    var value: Color? {
        if case .stated(let color) = self { color } else { nil }
    }
}

/// A `LineLimit?` a `TextStyle` stores: see the note above.
enum StatedLineLimit: Equatable, _AllBytesDefined {
    case unstated
    case stated(LineLimit)

    init(_ limit: LineLimit?) {
        if let limit { self = .stated(limit) } else { self = .unstated }
    }

    var value: LineLimit? {
        if case .stated(let limit) = self { limit } else { nil }
    }
}

/// A `Font??` a `TextStyle` stores — never stated, stated as no font, or
/// stated as a font: see the note above.
enum StatedFont: Equatable, _AllBytesDefined {
    case unstated
    case statedNone
    case stated(Font)

    init(_ font: Font??) {
        switch font {
        case .none: self = .unstated
        case .some(.none): self = .statedNone
        case .some(.some(let font)): self = .stated(font)
        }
    }

    var value: Font?? {
        switch self {
        case .unstated: .none
        case .statedNone: .some(.none)
        case .stated(let font): .some(.some(font))
        }
    }
}

/// A colour's value, or none: a `Color?` without the colour's alpha, for a
/// line, whose colour SGR draws opaque. Four bytes where a `StatedColor` is
/// five — which keeps a `Text` at 64, a multiple of its alignment, so a view
/// holding one has no padding after it. See the note above.
enum StatedColorValue: Hashable, _AllBytesDefined {
    case unstated
    case stated(Color.ColorValue)

    init(_ color: Color?) {
        if let color { self = .stated(color.value) } else { self = .unstated }
    }

    var value: Color? {
        if case .stated(let value) = self { Color.opaque(value) } else { nil }
    }
}

/// A line — an underline or a strikethrough — a `TextStyle` stores: never
/// stated, stated off, or stated on in a style. A `Text.LineStyle??` in all but
/// name: see the note above.
enum StatedLine: Equatable, _AllBytesDefined {
    case unstated
    case off
    case on(Text.LineStyle)

    init(_ line: Text.LineStyle??) {
        switch line {
        case .none: self = .unstated
        case .some(.none): self = .off
        case .some(.some(let line)): self = .on(line)
        }
    }

    var value: Text.LineStyle?? {
        switch self {
        case .unstated: .none
        case .off: .some(.none)
        case .on(let line): .some(.some(line))
        }
    }
}
