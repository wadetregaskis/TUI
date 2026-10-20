//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Paint+Shadows.swift
//
//  A paint's shadows, apart from what it draws: what each consumer splits off
//  before drawing, and casts from what it drew.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

extension Paint {
    /// What this paint draws: the paint without its shadows and its blend mode.
    ///
    /// Everything that draws with a paint draws this, and casts ``shadows``
    /// from the cells it drew, and marks them with ``blendMode``; a renderer
    /// below it never sees either.
    public var unshadowed: Paint {
        switch self {
        case .shadowed(let base, _), .blended(let base, _): base.unshadowed
        default: self
        }
    }

    /// The shadows this paint is drawn with, the one applied first first —
    /// empty for almost every paint, which costs nothing to ask.
    public var shadows: [ShadowStyle] {
        switch self {
        case .shadowed(let base, let shadow): base.shadows + [shadow]
        case .blended(let base, _): base.shadows
        default: []
        }
    }

    /// Whether this paint is drawn with a shadow.
    public var hasShadows: Bool {
        switch self {
        case .shadowed: true
        case .blended(let base, _): base.hasShadows
        default: false
        }
    }

    /// The blend mode this paint is drawn with (``ShapeStyle/blendMode(_:)``), the
    /// outermost where it names several, or `nil`.
    public var blendMode: BlendMode? {
        switch self {
        case .blended(_, let mode): mode
        case .shadowed(let base, _): base.blendMode
        default: nil
        }
    }

    /// Whether whatever draws with this paint has more to do than draw it: a
    /// shadow to cast or a blend mode to mark. One comparison for nearly every
    /// paint.
    public var castsAnything: Bool {
        switch self {
        case .shadowed, .blended: true
        default: false
        }
    }

    /// `drawn` with this paint's shadows: what a control keeps when it draws an
    /// inherited paint in another colour — a hovered label lifted, say — so the
    /// shadow the app asked for stays on the label.
    ///
    /// - Parameter drawn: The paint to draw instead of this one's own.
    /// - Returns: `drawn`, shadowed as this paint is.
    public func keepingShadows(on drawn: Paint) -> Paint {
        switch self {
        case .shadowed(let base, let shadow): .shadowed(base.keepingShadows(on: drawn), shadow)
        case .blended(let base, let mode): .blended(base.keepingShadows(on: drawn), mode)
        default: drawn
        }
    }

    /// This paint with what it draws replaced by `transform`'s answer for it,
    /// its shadows kept — how a style that changes a paint's drawing (a fixed
    /// extent, an animation) passes the shadows through.
    func mappingUnshadowed(_ transform: (Paint) -> Paint) -> Paint {
        switch self {
        case .shadowed(let base, let shadow): .shadowed(base.mappingUnshadowed(transform), shadow)
        case .blended(let base, let mode): .blended(base.mappingUnshadowed(transform), mode)
        default: transform(self)
        }
    }

    /// How strongly what this paint draws casts a shadow: its alpha, so a
    /// paint at half strength casts a shadow at half — as SwiftUI casts from a
    /// drawing's alpha, measured on macOS 15.8 for a faded colour whichever side
    /// of the shadow the fade is written.
    ///
    /// The representative's alpha, so a ramp casts at one strength: a ramp
    /// fading along its length casts evenly (decisions W1B, B-W1B-1).
    ///
    /// - Parameter palette: The palette a semantic colour resolves in.
    /// - Returns: The strength, `0…1`.
    func castingStrength(in palette: any Palette) -> Double {
        Double(unshadowed.representative.resolve(with: palette).alpha) / 255
    }
}

extension Optional where Wrapped == Paint {
    /// `drawn`, shadowed as this paint is: `drawn` itself where there is no
    /// paint, or one with no shadow — what a control writes over an inherited
    /// foreground style to draw a label in a colour of its own (hovered,
    /// disabled, secondary) without dropping the shadow the app asked for.
    ///
    /// - Parameter drawn: The paint to draw the label in.
    /// - Returns: `drawn`, with this paint's shadows.
    package func keepingShadows(on drawn: Paint) -> Paint {
        self?.keepingShadows(on: drawn) ?? drawn
    }
}
