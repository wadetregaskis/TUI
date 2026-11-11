//  🖥️ TUI — A Terminal UI framework for Swift
//  _ImageCore+FrameConversions.swift
//
//  A playing picture's frames converted to glyphs ahead of the frame clock, off
//  the main actor, and the one ink threshold they share.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIImage
import TUIStyling

// MARK: - Converting ahead

extension _ImageCore {
    /// A playing picture's frame that has no conversion at `settings`: starts
    /// converting every frame at them, off the main actor, unless that is under
    /// way already, and returns what to draw while it is — this frame as it was
    /// drawn before, at other settings, where that fills the same box. `nil` to
    /// convert this frame here, now, as a still picture is.
    ///
    /// ## Why ahead, and why not here
    ///
    /// A frame was converted the first time it showed, on the main actor, in
    /// the render that showed it. A conversion that takes longer than a frame
    /// of the animation made every frame of the first time round late, and
    /// again every time a setting changed: the owner saw the bouncing ball go
    /// "very choppy for a few seconds" on turning Shape-aware on, and a little
    /// on turning Dithering on (2026-11-10, item 21). Measured with
    /// `ImageHarness --image` at 140 × 45 cells: a shape-aware frame of the
    /// ball took 5 to 8 ms in a release build and 200 to 300 ms in a debug
    /// one (`swift run Example`), against a frame every 33 to 80 ms, and the
    /// first shape-aware or dithered conversion in a debug process 1.1 to
    /// 1.9 s more, building tables it keeps; a dithered frame 1.4 ms and 25 ms.
    ///
    /// So the frames are converted in a task, in the order they will show from
    /// the next one on, and the animation goes on playing meanwhile:
    ///
    /// - **A setting changed**, every frame drawn at the old one: the old
    ///   frames go on playing, and the new ones replace them all at once,
    ///   when the last is done. The picture changes a moment after the switch
    ///   rather than stuttering into it, and it never shows two settings at
    ///   once.
    /// - **Nothing to show meanwhile** — the first time round, or a box of a
    ///   new size: each frame is kept as soon as it is converted, so the frames
    ///   are ready before they are due wherever converting one takes less than
    ///   showing one, and a frame the task has not reached is converted here,
    ///   as before. The frame drawn is always the one the clock says.
    func framesConvertingAhead(
        _ playing: PlayingFrame, settings: ImageRenderCache, frame rawImage: RGBAImage, converter: ASCIIConverter,
        token: String, context: RenderContext
    ) -> ImageRenderCache? {
        let playback = playing.playback
        let held = playback.conversion(ofFrame: playing.index).flatMap {
            $0.source == settings.source && $0.decodedPixels == settings.decodedPixels
                && ($0.width, $0.height) == (settings.width, settings.height) ? $0 : nil
        }
        guard let animation = playback.animation, let lifecycle = context.environment.lifecycle,
            !(playback.convertingFor?.hasSameSettings(as: settings) ?? false)
        else { return held }

        let previous = playback.convertingFor
        playback.convertingFor = settings
        // As the decode's start is (`playingFrame(token:context:)`): a drawing
        // the walk throws away starts no task, so it must leave none recorded.
        context.stateStorage?.effectStage.noteUndo { playback.convertingFor = previous }
        context.environment.volatileReadTracker?.recordRenderSideEffect()

        let frames = animation.frames
        let order = (1...frames.count).map { (playing.index + $0) % frames.count }
        // All at once where every frame has something to show meanwhile.
        let atOnce = order.allSatisfy { index in
            playback.conversion(ofFrame: index).map { ($0.width, $0.height) == (settings.width, settings.height) }
                ?? false
        }
        let job = FrameConversionJob(
            converter: converter, width: settings.width, height: settings.height,
            crop: (rawImage.width, rawImage.height), templateInk: settings.templateInk,
            resizing: settings.resizing, cellAspect: settings.cellAspect,
            colorDepth: settings.colorDepth, terminalColors: settings.terminalColors)
        let box = animationPlayback(context: context)
        lifecycle.startTask(token: ImageAnimationPlayback.conversionToken(token), priority: .userInitiated) {
            var converted: [(index: Int, art: ASCIIArt)] = []
            for index in order {
                guard !Task.isCancelled else { return }
                // One the render has converted since, being due before this
                // reached it, is not converted again.
                let done = await MainActor.run {
                    !atOnce && playback.conversion(ofFrame: index)?.hasSameSettings(as: settings) == true
                }
                if done { continue }
                let art = await job.convert(frames[index].image)
                if atOnce {
                    converted.append((index, art))
                } else {
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        playback.keep(settings.converted(DecodedPixels(decode: frames[index].decode), to: art), ofFrame: index)
                    }
                }
            }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                for (index, art) in converted {
                    playback.keep(settings.converted(DecodedPixels(decode: frames[index].decode), to: art), ofFrame: index)
                }
                // A write, to ask for the frame that draws them.
                box.value = playback
            }
        }
        return held
    }
}

/// What converting one frame of a playing picture takes, off the main actor.
private struct FrameConversionJob: Sendable {
    let converter: ASCIIConverter
    let width: Int
    let height: Int
    /// The top-leading pixels of each frame the box shows, which a zoom cuts
    /// the same from every frame (`drawing(_:laidOutAs:in:zoom:environment:)`).
    let crop: (columns: Int, rows: Int)
    let templateInk: RGBA?
    let resizing: _ImageResizing?
    let cellAspect: Double
    /// What the converter reads of the terminal, as the render that started
    /// this read them: the conversion is filed under them.
    let colorDepth: ColorDepth
    let terminalColors: TerminalColors

    /// ``converted(_:)``, off the main actor.
    @concurrent
    func convert(_ image: RGBAImage) async -> ASCIIArt { converted(image) }

    /// `image` converted as `renderImage` converts a frame.
    func converted(_ image: RGBAImage) -> ASCIIArt {
        ColorDepth.withCurrent(colorDepth) {
            TerminalColors.withCurrent(terminalColors) {
                var pixels = image.croppedToLeading(columns: crop.columns, rows: crop.rows)
                if let templateInk { pixels = pixels.templated(in: templateInk) }
                if let resizing, resizing.slices {
                    pixels = pixels.sliced(resizing, columns: width, rows: height, cellAspect: cellAspect)
                }
                return converter.convert(pixels, width: width, height: height)
            }
        }
    }
}

// MARK: - One ink threshold for every frame

/// What an animation's shared ink threshold depends on: the settings that move
/// its tones (``ASCIIConverter/sharedInkThreshold(of:)``).
struct SharedInkThresholdSettings: Equatable {
    let toneCurve: ASCIIToneCurve?
    let adjustments: ImageAdjustments
    let posterizationLevels: Int?
    let dithering: DitheringMode
}

extension _ImageCore {
    /// The ink threshold to draw `playing`'s frame with: the one stated, else,
    /// where the drawing is ink or none — mono, or braille's dots — the one its
    /// frames share. `nil` to measure it from the picture, a still one.
    func inkThreshold(
        for playing: PlayingFrame?, colorMode: ASCIIColorMode, characterSet: ASCIICharacterSet?,
        context: RenderContext
    ) -> Double? {
        let environment = context.environment
        if let stated = environment.imageInkThreshold { return stated }
        guard let playing, colorMode == .mono || characterSet == .blocks(.braille) else { return nil }
        return playing.sharedInkThreshold(
            SharedInkThresholdSettings(
                toneCurve: environment.imageToneCurve?.resolved(with: environment.palette),
                adjustments: environment.imageAdjustments, posterizationLevels: environment.imagePosterization,
                dithering: environment.imageDithering))
    }
}

extension PlayingFrame {
    /// The ink threshold every frame of this picture is drawn with, where none
    /// is stated, measured across them all once for these settings: so that a
    /// part of the picture that holds still is on one side of it in every
    /// frame (``ASCIIConverter/sharedInkThreshold(of:)``).
    ///
    /// `nil` before the frames have decoded, when the still picture showing is
    /// the only one there is.
    func sharedInkThreshold(_ settings: SharedInkThresholdSettings) -> Double? {
        guard let animation = playback.animation else { return nil }
        if let held = playback.sharedInkThreshold, held.settings == settings { return held.value }
        let converter = ASCIIConverter(
            dithering: settings.dithering, toneCurve: settings.toneCurve, adjustments: settings.adjustments,
            posterizationLevels: settings.posterizationLevels)
        let value = converter.sharedInkThreshold(of: animation.frames.map(\.image))
        playback.sharedInkThreshold = (settings, value)
        return value
    }
}
