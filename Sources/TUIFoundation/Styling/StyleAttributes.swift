//  🖥️ TUI — A Terminal UI framework for Swift
//  StyleAttributes.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIStyling

// MARK: - Text case

/// A case transform applied to text, mirroring SwiftUI's `Text.Case`.
public enum TextCase: Sendable, Hashable {
    case uppercase
    case lowercase
}

// MARK: - Font weight

/// A font weight, mirroring SwiftUI's `Font.Weight`.
///
/// Terminals have no real font weights, so weight maps to the nearest SGR
/// emphasis: heavier-than-regular weights render **bold**, lighter-than-regular
/// weights render **faint** (dim), and `regular`/`medium` render normal.
public enum FontWeight: Sendable, Hashable {
    case ultraLight
    case thin
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black

    /// The text attributes this weight maps to on a terminal. Sets `bold` and
    /// `dim` explicitly (rather than leaving them `nil`) so that, e.g.,
    /// `.fontWeight(.regular)` actively clears an inherited bold/faint.
    ///
    /// `.medium` draws as `.regular` does. A terminal has bold, normal and
    /// faint, and medium (500) is a step above regular (400) where bold (700)
    /// is three; a bold under it leaves it medium, as SwiftUI's does, so a
    /// text's own `bold()` under a view's `.fontWeight(.medium)` draws normal,
    /// like the medium text beside it, rather than standing out as bold where
    /// SwiftUI's does not (``StyleAttributes/weightIgnoresBold``).
    var styleAttributes: StyleAttributes {
        var attributes: StyleAttributes
        switch self {
        case .semibold, .bold, .heavy, .black:
            attributes = StyleAttributes(bold: true, dim: false)
        case .ultraLight, .thin, .light:
            attributes = StyleAttributes(bold: false, dim: true)
            attributes.weightIgnoresBold = true
        case .medium:
            attributes = StyleAttributes(bold: false, dim: false)
            attributes.weightIgnoresBold = true
        case .regular:
            attributes = StyleAttributes(bold: false, dim: false)
        }
        attributes.boldIsWeight = true
        return attributes
    }
}

// MARK: - Style attributes

/// The themeable text attributes, expressed as a *partial* overlay: every field
/// is optional, where `nil` means "inherit / not set at this level".
///
/// This is the type an app styles with. `StyleAttributes` is the value carried
/// by the scoped style cascade (``StyleCascade``): container-level modifiers
/// like ``View/bold(_:)`` and ``View/style(_:_:)-(_,StyleAttributes)``
/// contribute these, every `…TextStyle { }` builder hands one out to fill in,
/// and ``Text`` merges the resolved result beneath its own explicit attributes
/// when it renders.
///
/// The tri-state (`Bool?`) lets a subtree turn an attribute **on** and a
/// descendant turn it **off** (e.g. `.bold()` then `.bold(false)` deeper),
/// matching SwiftUI. The framework's internal `TextStyle` now carries the same
/// tri-state for the five attributes this type can state, and for the same
/// reason: it was described here as "the fully-resolved end of the pipeline
/// with nothing left to defer to", which was wrong — a `Text`'s own answer is
/// resolved AGAINST the cascade, so it needs to be able to say *no* and not
/// merely *nothing*.
public struct StyleAttributes: Sendable, Hashable {
    public var foreground: Color?
    public var background: Color?
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var strikethrough: Bool?
    public var dim: Bool?

    /// Whether ``dim`` was stated by a weight a bold leaves as it is: a light
    /// one (``FontWeight/light`` and lighter) or ``FontWeight/medium``, rather
    /// than by `dim` itself, a font's faint tier or another weight. A bold
    /// applies to the weight below it, as SwiftUI's does, and leaves these as
    /// they are: under a view's `.fontWeight(.ultraLight)` or `.medium`,
    /// `Text("x").bold()` and a view's `.bold()` are that weight, a text's own
    /// weight alone deciding otherwise (measured, macOS 15.8.3,
    /// `Tools/SwiftUIProbes/Text foregroundStyle levels (TXTFG)/nested.out`
    /// and `variants.out`). It travels with ``dim``, which every weight
    /// states, as a line's style travels with its line.
    var weightIgnoresBold = false

    /// Whether ``bold`` was stated by a weight (``FontWeight/styleAttributes``)
    /// rather than by a bold. It travels with ``bold``.
    var boldIsWeight = false

    /// What the nearest bold the cascade states as a bold — a view's
    /// `.bold()`, not a weight — comes to against the weight above it, or
    /// `nil` where there is none. It decides a text's own `bold()`, as
    /// SwiftUI's does (measured, `variants.out`): a view's `.bold()` farther
    /// out than a view's `.fontWeight(.medium)` makes a text's own bold bold,
    /// one nearer leaves it medium, and one under a `.fontWeight(.ultraLight)`
    /// leaves it ultralight, whatever weight is nearer. Set where that bold is
    /// merged over what is above it, and kept from then on.
    var viewBold: ViewBold?

    /// What a view's `.bold()` comes to, against the weight above it.
    enum ViewBold: UInt8, Sendable, Hashable {
        /// `.bold(false)`: a text's own bold applies to the nearest weight.
        case off
        /// Bold: no weight above it, or one a bold makes bold.
        case bold
        /// Normal: under a ``FontWeight/medium``.
        case keepsRegular
        /// Faint: under a light weight.
        case keepsFaint
    }

    /// How the underline is drawn where ``underline`` is `true`: `nil` for a
    /// single line in the text's colour. It travels with ``underline``, so the
    /// nearest entry to state an underline decides its line too.
    public var underlineStyle: Text.LineStyle?

    /// How the strikethrough is drawn where ``strikethrough`` is `true`, as
    /// ``underlineStyle`` says it for the underline.
    public var strikethroughStyle: Text.LineStyle?

    /// The case transform, as a THIRD state: `nil` is "nothing was said",
    /// `.some(nil)` is "cleared here", `.some(.some(c))` is `c`.
    ///
    /// SwiftUI's `textCase(_:)` writes an environment value of type
    /// `Text.Case?`, so passing `nil` overrides an ancestor's transform rather
    /// than declining to speak. A single Optional cannot tell those apart, and
    /// collapsing them made `.textCase(nil)` a silent no-op — an inherited
    /// `.uppercase` could not be escaped from anywhere in the subtree. Same
    /// shape as `Font??` on `TextStyle` and `UnitPoint??` on the scroll
    /// anchor, and for the same reason.
    public var textCase: TextCase??

    /// The text scale: `.secondary` draws one intensity tier down. See
    /// ``Text/Scale``.
    public var textScale: Text.Scale?

    public init(
        foreground: Color? = nil,
        background: Color? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: Bool? = nil,
        strikethrough: Bool? = nil,
        dim: Bool? = nil,
        textCase: TextCase?? = nil,
        textScale: Text.Scale? = nil,
        underlineStyle: Text.LineStyle? = nil,
        strikethroughStyle: Text.LineStyle? = nil
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.dim = dim
        self.textCase = textCase
        self.textScale = textScale
        self.underlineStyle = underlineStyle
        self.strikethroughStyle = strikethroughStyle
    }

    /// The underline these attributes state, as a `Text` states one: `nil`
    /// if they say nothing, `.some(nil)` for none, or the line.
    var underlineLine: Text.LineStyle?? {
        underline.map { $0 ? underlineStyle ?? .single : nil }
    }

    /// The strikethrough these attributes state, as ``underlineLine`` states
    /// the underline.
    var strikethroughLine: Text.LineStyle?? {
        strikethrough.map { $0 ? strikethroughStyle ?? .single : nil }
    }

    /// The case transform to actually apply.
    ///
    /// Flattens ``textCase``'s third state: both "cleared here" and "nobody
    /// said" mean no transform, and only the merge needs to tell them apart.
    public var effectiveTextCase: TextCase? { textCase.flatMap { $0 } }

    /// Whether no attribute is set (every field is `nil`).
    public var isEmpty: Bool {
        guard foreground == nil, background == nil, bold == nil, italic == nil,
            underline == nil, strikethrough == nil, dim == nil, textCase == nil
        else { return false }
        return textScale == nil
    }

    /// Returns a copy where `self`'s non-`nil` fields win over `base` — the
    /// merge primitive the cascade uses. Applying an inner (closer) entry's
    /// attributes `merged(over:)` the accumulated outer ones makes the closest
    /// setter of each property win (proximity, per property).
    public func merged(over base: Self) -> Self {
        var merged = Self(
            foreground: foreground ?? base.foreground,
            background: background ?? base.background,
            bold: bold ?? base.bold,
            italic: italic ?? base.italic,
            underline: underline ?? base.underline,
            strikethrough: strikethrough ?? base.strikethrough,
            dim: dim ?? base.dim,
            textCase: textCase ?? base.textCase,
            textScale: textScale ?? base.textScale,
            // A line's style goes with whoever stated the line.
            underlineStyle: underline != nil ? underlineStyle : base.underlineStyle,
            strikethroughStyle: strikethrough != nil ? strikethroughStyle : base.strikethroughStyle)
        merged.weightIgnoresBold = dim != nil ? weightIgnoresBold : base.weightIgnoresBold
        merged.boldIsWeight = bold != nil ? boldIsWeight : base.boldIsWeight
        if let viewBold {
            // Already merged over what was above it: a resolved cascade.
            merged.viewBold = viewBold
        } else if let bold, !boldIsWeight {
            merged.viewBold = if !bold {
                .off
            } else if !base.weightIgnoresBold {
                .bold
            } else {
                base.dim == true ? .keepsFaint : .keepsRegular
            }
        } else {
            merged.viewBold = base.viewBold
        }
        return merged
    }

    /// The bold, and the faint where a weight's changes, of a text under these
    /// attributes that states no weight or faint of its own, given its own
    /// bold (`nil` for none). A `nil` faint leaves the faint as resolved.
    ///
    /// A bold applies to the weight it is under, as SwiftUI's does
    /// (``weightIgnoresBold``, ``viewBold``): the cascade's own bold gives way
    /// to a light or medium weight, and a text's own bold takes what a view's
    /// `.bold()` came to, or with none applies to the nearest weight. Where it
    /// wins over a light weight it is bold, not bold and faint.
    func emphasis(ownBold: Bool?) -> (bold: Bool?, faint: Bool?) {
        guard let ownBold else { return (weightIgnoresBold ? false : bold, nil) }
        guard ownBold else { return (false, nil) }
        let faintIsWeight = dim == true && weightIgnoresBold
        switch viewBold {
        case .bold: return (true, faintIsWeight ? false : nil)
        case .keepsRegular: return (false, faintIsWeight ? false : nil)
        case .keepsFaint: return (false, true)
        case .off, nil: return (!weightIgnoresBold, nil)
        }
    }
}
