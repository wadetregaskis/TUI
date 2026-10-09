//  🖥️ TUIkit — Terminal UI Kit for Swift
//  _ImageCore+Template.swift
//
//  A raster image drawn as a template: its pixels in the foreground colour,
//  at their own alpha (`Image.renderingMode(.template)`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation
import TUIkitImage

// MARK: - Template rendering

extension _ImageCore {
    /// The colour a template image is drawn in: the foreground style in force,
    /// else the palette's foreground, as numbers.
    static func templateInk(in environment: EnvironmentValues) -> RGBA {
        let ink = environment.foregroundStyle?.representative ?? environment.palette.foreground
        let resolved = ink.resolve(in: environment)
        func byte(_ component: Float) -> UInt8 { UInt8((min(1, max(0, component)) * 255).rounded()) }
        return RGBA(r: byte(resolved.red), g: byte(resolved.green), b: byte(resolved.blue))
    }
}

extension RGBAImage {
    /// This image as a template: every pixel `ink`, at the pixel's own alpha.
    func templated(in ink: RGBA) -> RGBAImage {
        RGBAImage(
            width: width, height: height,
            pixels: pixels.map { RGBA(r: ink.r, g: ink.g, b: ink.b, a: $0.a) })
    }
}
