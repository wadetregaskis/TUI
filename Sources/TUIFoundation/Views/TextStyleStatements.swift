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

/// The ink a `Text` stated for itself: nothing, a colour, or one of the content
/// levels (`.primary` … `.quinary`), which is resolved where the text is drawn,
/// against the style in force there (`Text.foregroundStyle(_:)`).
///
/// A `StatedColor` with five more cases, and the same five bytes: the levels
/// carry no payload, so they are spelled in the colour's spare values, as
/// `unstated` is, and a `Text` is no bigger for being able to say one. Its own
/// enum rather than `StatedColor`'s, because a background has no levels.
enum StatedInk: Hashable, _AllBytesDefined {
    case unstated
    case stated(Color)
    case primaryLevel
    case secondaryLevel
    case tertiaryLevel
    case quaternaryLevel
    case quinaryLevel

    init(_ color: Color?) {
        if let color { self = .stated(color) } else { self = .unstated }
    }

    /// The statement of content level `level`, 0 (primary) through 4 (quinary).
    init(level: Int) {
        switch level {
        case 0: self = .primaryLevel
        case 1: self = .secondaryLevel
        case 2: self = .tertiaryLevel
        case 3: self = .quaternaryLevel
        default: self = .quinaryLevel
        }
    }

    var value: Color? {
        if case .stated(let color) = self { color } else { nil }
    }

    /// The content level stated, 0 (primary) through 4 (quinary), or `nil` for
    /// a colour or nothing.
    var level: Int? {
        switch self {
        case .unstated, .stated: nil
        case .primaryLevel: 0
        case .secondaryLevel: 1
        case .tertiaryLevel: 2
        case .quaternaryLevel: 3
        case .quinaryLevel: 4
        }
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

/// The faint attribute a `TextStyle` stores — a `Bool?`, never stated, on or
/// off — and, in the same byte, whether the text stated its font's own weight
/// (`Text.fontWeight(nil)`), which a `Bool?` has no room to say beside it.
enum StatedDim: Equatable, _AllBytesDefined {
    case unstated
    case on
    case off
    case fontsWeight
    case fontsWeightOn
    case fontsWeightOff

    init(isDim: Bool?, weightIsFonts: Bool) {
        switch (isDim, weightIsFonts) {
        case (nil, false): self = .unstated
        case (true?, false): self = .on
        case (false?, false): self = .off
        case (nil, true): self = .fontsWeight
        case (true?, true): self = .fontsWeightOn
        case (false?, true): self = .fontsWeightOff
        }
    }

    var isDim: Bool? {
        switch self {
        case .unstated, .fontsWeight: nil
        case .on, .fontsWeightOn: true
        case .off, .fontsWeightOff: false
        }
    }

    var weightIsFonts: Bool {
        switch self {
        case .unstated, .on, .off: false
        case .fontsWeight, .fontsWeightOn, .fontsWeightOff: true
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
