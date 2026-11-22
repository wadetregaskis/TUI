//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimatedImageDecoder+WIC.swift
//
//  Animated WebP on Windows: its frames as WIC's WebP codec composites them,
//  and its timing from the codec's metadata.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import Foundation
import WinSDK

extension AnimatedImageDecoder {
    /// The frames of the animated WebP `data` holds, or `nil` if it holds
    /// fewer than two, Windows has no WebP codec, the codec does not composite
    /// them, or the calling task was cancelled.
    ///
    /// WIC's WebP codec does the compositing: each frame it decodes is the
    /// whole canvas, with the frame's rectangle blended or replaced and the
    /// last one's disposed as the file says. It states each frame's duration,
    /// in milliseconds, as `/ANMF/FrameDuration`, and the plays as
    /// `/ANIM/LoopCount`, 0 for forever (measured 2026-11-20, build 26300, on
    /// a file of four frames that blend, replace and dispose). A frame of
    /// another size than the first would be one it did not composite, which
    /// this does not do either, so the file stays a still picture then.
    static func decodeWebPWithWIC(
        _ data: Data, maxPixelCount: Int?, byteBudget: Int, frameLimit: Int
    ) -> AnimatedImage? {
        try? unsafe WICSession.run { session -> AnimatedImage? in
            let decoder = try unsafe session.decoder(data: data)
            defer { _ = unsafe decoder.pointee.lpVtbl.pointee.Release(decoder) }
            return try unsafe session.animation(
                of: decoder, maxPixelCount: maxPixelCount, byteBudget: byteBudget, frameLimit: frameLimit)
        }
    }
}

extension WICSession {
    /// `decoder`'s frames, as ``AnimatedImageDecoder/decodeWebPWithWIC(_:maxPixelCount:byteBudget:frameLimit:)``
    /// keeps them. `decoder` is the caller's to release.
    fileprivate func animation(
        of decoder: UnsafeMutablePointer<IWICBitmapDecoder>, maxPixelCount: Int?, byteBudget: Int, frameLimit: Int
    ) throws -> AnimatedImage? {
        var count: UINT = 0
        _ = unsafe decoder.pointee.lpVtbl.pointee.GetFrameCount(decoder, &count)
        guard count > 1 else { return nil }
        let first = try unsafe frame(0, of: decoder)
        let canvas = unsafe Self.size(of: first)
        unsafe release(first)
        guard AnimatedImageDecoder.fits(width: canvas.width, height: canvas.height, maxPixelCount: maxPixelCount)
        else { return nil }
        var builder = AnimatedImageBuilder(
            plan: FramePlan(
                canvasWidth: canvas.width, canvasHeight: canvas.height, frameCount: Int(count),
                byteBudget: byteBudget, frameLimit: frameLimit))
        for index in 0..<count {
            guard !Task.isCancelled else { return nil }
            let frame = try unsafe self.frame(index, of: decoder)
            defer { unsafe release(frame) }
            guard unsafe Self.size(of: frame) == canvas else { return nil }
            let milliseconds = unsafe Self.duration(of: frame)
            builder.add(delayNanos: AnimatedImage.delayNanos(milliseconds: milliseconds)) {
                unsafe Self.pixels(of: frame)
            }
        }
        guard builder.frames.count > 1 else { return nil }
        return AnimatedImage(
            width: canvas.width, height: canvas.height, frames: builder.frames, plays: unsafe Self.plays(of: decoder))
    }

    /// How long `frame` shows, in milliseconds: 0 where it states none, which
    /// ``AnimatedImage/delayNanos(milliseconds:)`` shows as a browser would.
    private static func duration(of frame: UnsafeMutablePointer<IWICBitmapFrameDecode>) -> Int {
        var reader: UnsafeMutablePointer<IWICMetadataQueryReader>?
        guard unsafe frame.pointee.lpVtbl.pointee.GetMetadataQueryReader(frame, &reader) == S_OK,
            let reader = unsafe reader
        else { return 0 }
        defer { _ = unsafe reader.pointee.lpVtbl.pointee.Release(reader) }
        return unsafe unsignedMetadata("/ANMF/FrameDuration", in: reader) ?? 0
    }

    /// How many times `decoder`'s frames play, or `nil` for forever, as a file
    /// that states no count plays.
    private static func plays(of decoder: UnsafeMutablePointer<IWICBitmapDecoder>) -> Int? {
        var reader: UnsafeMutablePointer<IWICMetadataQueryReader>?
        guard unsafe decoder.pointee.lpVtbl.pointee.GetMetadataQueryReader(decoder, &reader) == S_OK,
            let reader = unsafe reader
        else { return nil }
        defer { _ = unsafe reader.pointee.lpVtbl.pointee.Release(reader) }
        let stated = unsafe unsignedMetadata("/ANIM/LoopCount", in: reader) ?? 0
        return stated > 0 ? stated : nil
    }

    /// `frame`'s pixels, as straight-alpha RGBA, or `nil` where they could
    /// not be read.
    private static func pixels(of frame: UnsafeMutablePointer<IWICBitmapFrameDecode>) -> RGBAImage? {
        try? unsafe frame.withMemoryRebound(to: IWICBitmapSource.self, capacity: 1) { try unsafe straightRGBA(of: $0) }
    }
}

#endif
