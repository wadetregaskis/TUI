//  🖥️ TUI — A Terminal UI framework for Swift
//  ConsoleFont.swift
//
//  The classic Windows console's font, which a program in the console can ask
//  about, as it cannot ask a terminal: the face the console names, and
//  whether that face has the glyphs TUI would draw.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import Foundation
import TUIFoundation
import WinSDK

/// The font the classic Windows console (conhost) draws in.
///
/// The console names its font (`GetCurrentConsoleFontEx`), and GDI says which
/// glyphs a font of that name has (`GetGlyphIndicesW`). Measured 2026-11-18,
/// build 26300: the console names Consolas, its default, and GDI finds none
/// of the quadrants in it, matching the boxes the console draws for them; set
/// to Cascadia Mono, the console names it at once, and GDI finds them all. A
/// pseudo console (Windows Terminal's, an ssh server's) names Consolas as
/// well, at a width and weight of 0, whatever its terminal draws in, so only
/// the classic console's answer is taken (``TerminalClient/fontHasQuadrants(_:)``).
enum ConsoleFont {
    /// The face the console draws standard output in, or `nil` where standard
    /// output is no console, or the console names none.
    static func faceName() -> String? {
        var info = CONSOLE_FONT_INFOEX()
        info.cbSize = ULONG(MemoryLayout<CONSOLE_FONT_INFOEX>.size)
        guard unsafe GetCurrentConsoleFontEx(StandardHandle.output, false, &info) else { return nil }
        // The name is a C array, imported as a tuple of 32 code units: read
        // through a mirror, it needs no pointer, safe on every toolchain.
        let units = Mirror(reflecting: info.FaceName).children.compactMap { $0.value as? WCHAR }
        let face = String(decoding: units.prefix { $0 != 0 }, as: UTF16.self)
        return face.isEmpty ? nil : face
    }

    /// Whether the font named `face` has a glyph for every one of `characters`,
    /// each one UTF-16 code unit; `nil` where GDI has no font of that name (it
    /// would choose another in its place) or cannot say.
    static func has(_ characters: [Character], face: String) -> Bool? {
        guard let screen = unsafe GetDC(nil) else { return nil }
        defer { _ = unsafe ReleaseDC(nil, screen) }
        let created = face.withCString(encodedAs: UTF16.self) { name in
            unsafe CreateFontW(
                16, 0, 0, 0, FW_NORMAL, 0, 0, 0, DWORD(DEFAULT_CHARSET), DWORD(OUT_DEFAULT_PRECIS),
                DWORD(CLIP_DEFAULT_PRECIS), DWORD(DEFAULT_QUALITY), DWORD(FF_DONTCARE), name)
        }
        guard let font = unsafe created else { return nil }
        defer { _ = unsafe DeleteObject(font) }
        let previous = unsafe SelectObject(screen, font)
        defer { _ = unsafe SelectObject(screen, previous) }
        // The face GDI chose: another, where none by this name is installed.
        var chosen = [WCHAR](repeating: 0, count: Int(LF_FACESIZE))
        guard unsafe GetTextFaceW(screen, Int32(chosen.count), &chosen) > 0,
            String(decoding: chosen.prefix { $0 != 0 }, as: UTF16.self).caseInsensitiveCompare(face) == .orderedSame
        else { return nil }
        let units = Array(String(characters).utf16)
        guard units.count == characters.count else { return nil }
        var glyphs = [WORD](repeating: 0, count: units.count)
        let converted = unsafe GetGlyphIndicesW(
            screen, units, Int32(units.count), &glyphs, DWORD(GGI_MARK_NONEXISTING_GLYPHS))
        guard converted != DWORD.max else { return nil }
        // A glyph the font lacks is marked 0xFFFF.
        return !glyphs.contains(0xFFFF)
    }

    /// Whether the console's font has the quadrants; `true` where that cannot
    /// be told, as no other terminal's font is doubted.
    static var hasQuadrants: Bool {
        guard let face = faceName() else { return true }
        return has(TerminalSymbols.quadrants.filter { $0 != " " }, face: face) ?? true
    }
}

#endif
