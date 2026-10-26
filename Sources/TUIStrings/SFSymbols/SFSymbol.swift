//  🖥️ TUI — A Terminal UI framework for Swift
//  SFSymbol.swift
//
//  Created by LAYERED.work
//  License: MIT

#if canImport(CoreText)
    import CoreGraphics
    import CoreText
    import Foundation
#endif

/// Resolves an SF Symbol name (`"star.fill"`, `"gearshape"`) to the terminal
/// glyph that renders it, and enumerates every known symbol.
///
/// ## Very limited circumstances
///
/// SF Symbols are not normal text — they live in a private region of Unicode
/// (the Plane-16 Private Use Area) and only render where a font supplies their
/// glyphs. In a terminal that means **all** of the following must hold:
///
/// - **An Apple platform** (macOS). On Linux every lookup here returns `nil`
///   and ``all`` is empty — the baked table isn't even compiled in.
/// - **A terminal whose font carries the glyphs.** In practice that is
///   **Terminal.app with SF Mono**, with the **SF Symbols font installed**
///   (it is *not* installed by default — download it from Apple's developer
///   site). Elsewhere the codepoints render as missing-glyph boxes.
///
/// Because most users won't have that setup, treat symbols as a progressive
/// enhancement: ``Label/init(_:systemImage:)-(LocalizedStringKey,_)`` falls back to showing just its title
/// when a symbol can't be resolved, so code that uses it stays correct
/// everywhere — the glyph simply appears only where it can.
///
/// The name → codepoint mapping is Apple's own, extracted from the SF Symbols
/// app (see `Tools/GenerateSFSymbols`). It is a plain functional mapping; no
/// glyph artwork is reproduced.
///
/// ```swift
/// Label("Favourite", systemImage: "star.fill")   // ★ glyph + title on Apple
/// SFSymbol.glyph(named: "gearshape")              // "􀍟" on Apple, nil elsewhere
/// ```
public enum SFSymbol {

    /// One symbol: its name and the terminal glyph (a single Private-Use
    /// grapheme) that renders it.
    public struct Entry: Sendable, Equatable {
        /// The SF Symbol name, e.g. `"square.and.arrow.up"`.
        public let name: String
        /// The glyph string — one Plane-16 Private-Use scalar.
        public let glyph: String
    }

    /// The glyph that renders the named symbol, or `nil` when it can't be
    /// resolved (an unknown name, or any non-Apple platform).
    ///
    /// The glyph is a single Private-Use grapheme; emit it in a ``Text`` and it
    /// is laid out as a 2-cell wide character (with Terminal.app cursor-advance
    /// compensation applied automatically — see
    /// `Character.terminalAppCursorAdvance`).
    ///
    /// - Parameter name: The SF Symbol name, e.g. `"star.fill"`.
    public static func glyph(named name: String) -> String? {
        #if canImport(AppKit)
        guard let scalar = scalar(forName: name) else { return nil }
        return String(scalar)
        #else
        return nil
        #endif
    }

    /// Whether the named symbol would actually appear on screen here.
    ///
    /// The two halves of the question, which have to be asked together:
    /// ``glyph(named:)`` says the name maps to a codepoint, and
    /// ``isFontAvailable`` says some installed font can draw one. Either alone
    /// is a trap — a resolved codepoint with no font behind it renders as a
    /// missing-glyph box, which is worse than no icon at all. The font is asked
    /// first, so where no font can draw a symbol the name is never looked up.
    ///
    /// This is what ``Label/init(_:systemImage:)-(LocalizedStringKey,_)`` gates its icon column on and
    /// what ``Image/init(systemName:)`` gates its whole self on, so both fall
    /// back the same way rather than each spelling the rule out again.
    ///
    /// - Parameter name: The SF Symbol name, e.g. `"star.fill"`.
    public static func canRender(named name: String) -> Bool {
        isFontAvailable && glyph(named: name) != nil
    }

    /// Every known symbol, sorted by name. Empty on non-Apple platforms.
    ///
    /// The names are materialised into `String`s lazily on first access — the
    /// only place this type builds a `String` (``glyph(named:)`` never does).
    /// Intended for tooling and browsers (such as the example app's symbol
    /// explorer), not per-frame use.
    public static var all: [Entry] {
        #if canImport(AppKit)
        return entries
        #else
        return []
        #endif
    }

    /// Whether the running system actually carries a font that can draw SF Symbol
    /// glyphs — in practice, whether the **SF Symbols font is installed** (it is
    /// *not* by default; users download it from Apple's developer site).
    ///
    /// ``glyph(named:)`` maps a name to its Private-Use codepoint on every Apple
    /// build whether or not that font is present, so a resolved codepoint alone
    /// doesn't mean anything will render — without the font the terminal draws a
    /// missing-glyph box. This probes CoreText's font-substitution cascade with a
    /// known anchor symbol (`star.fill`): if some installed font supplies a real
    /// glyph for its codepoint, symbols are renderable here; otherwise they are
    /// not, and callers should fall back (``Label/init(_:systemImage:)-(LocalizedStringKey,_)`` shows just its
    /// title, the example's browser shows a "not available" placeholder).
    ///
    /// The anchor's codepoint is a constant the table's generator writes beside
    /// the table, so the probe searches no names; and ``canRender(named:)`` asks
    /// this first, so on a Mac without the font it answers — and ``Label``,
    /// ``Image/init(systemName:)`` and a tab's symbol fall back — without
    /// reading the table at all.
    ///
    /// Evaluated once and cached. `false` wherever the table is not compiled in:
    /// any platform without CoreText (Linux) or without AppKit.
    public static let isFontAvailable: Bool = {
        #if canImport(CoreText) && canImport(AppKit)
        let glyph = String(fontProbeScalar)
        let utf16 = Array(glyph.utf16)  // a Plane-16 scalar → one UTF-16 surrogate pair
        guard !utf16.isEmpty else { return false }
        // A base font whose CoreText cascade the system extends: the SF Symbols
        // font, once installed, joins that cascade, so substitution finds the
        // Private-Use glyph. Menlo is Terminal.app's default and always present.
        let base = CTFontCreateWithName("Menlo" as CFString, 12, nil)
        let substitute = CTFontCreateForString(
            base, glyph as CFString, CFRange(location: 0, length: utf16.count))
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        _ = utf16.withUnsafeBufferPointer { buffer in
            CTFontGetGlyphsForCharacters(substitute, buffer.baseAddress!, &glyphs, utf16.count)
        }
        // For a surrogate pair CTFontGetGlyphsForCharacters puts the composed
        // glyph in [0] and 0 in [1], and reports `false` for that trailing unit —
        // so the mapped glyph in [0], not the bool return, is the real signal.
        return glyphs[0] != 0
        #else
        return false
        #endif
    }()

    #if canImport(AppKit)
    /// The Plane-16 Private Use Area base every codepoint offset is measured from.
    private static let puaBase: UInt32 = 0x10_0000

    /// The baked names, searched in place (``FrontCodedNames``).
    private static let names = FrontCodedNames(
        blocks: nameBlocks, blockStarts: blockStarts, blockSize: nameBlockSize, count: bakedCount)

    /// Name `index`'s `codepoint - 0x100000`: the generated table packs four
    /// to a `UInt64`, the first in the high 16 bits.
    private static func codepointOffset(at index: Int) -> UInt16 {
        let shift = UInt64(truncatingIfNeeded: (3 - index % 4) * 16)
        return UInt16(truncatingIfNeeded: packedCodepointOffsets[index / 4] &>> shift)
    }

    /// The glyph scalar for `name`, or `nil`: a search of the baked,
    /// front-coded names that builds no `String`.
    static func scalar(forName name: String) -> Unicode.Scalar? {
        guard let position = names.index(of: name) else { return nil }
        return Unicode.Scalar(puaBase + UInt32(codepointOffset(at: position)))
    }

    /// The position of `bytes` among the baked names, or `nil`, searched in
    /// one copy of them: the path a string without contiguous UTF-8 takes.
    /// Internal so a test reaches it directly.
    static func index(copying bytes: String.UTF8View) -> Int? {
        names.index(copying: bytes)
    }

    /// Public-facing entries (name + glyph). Built once, on first access to
    /// ``all`` — the only place a name becomes a `String`: one pass over
    /// `nameBlocks`, each name rebuilt from the one before it.
    private static let entries: [Entry] = {
        var result: [Entry] = []
        result.reserveCapacity(bakedCount)
        names.forEachName { index, name in
            let scalar = Unicode.Scalar(puaBase + UInt32(codepointOffset(at: index)))!
            let text = String(unsafeUninitializedCapacity: name.count) { $0.initialize(fromContentsOf: name) }
            result.append(Entry(name: text, glyph: String(scalar)))
        }
        return result
    }()
    #endif
}
