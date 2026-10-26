//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  WindowRecorder: films one window with ScreenCaptureKit, to PNG frames and
//  the instant each was presented.
//
//      WindowRecorder --pid PID [--exclude ID,ID…] [--title TEXT] --out DIR [--markers FILE]
//                     [--scale 1] [--fps 30] [--wait 20] [--timeout 120] [--wake] [--refront PID]
//      WindowRecorder --list [--pid PID]      the windows on screen, with their ids
//      WindowRecorder --front                 the frontmost app's process id
//      WindowRecorder --spot WxH              where a W×H pt window shows most from behind the frontmost app
//      WindowRecorder --cursor PNG            the system's arrow pointer, at the main screen's scale,
//                                             and its hot spot in that image's pixels (printed `x y`)
//
//  The window is the newest on-screen window of process PID (not one in
//  --exclude, which lists the windows that app already had when it was asked
//  for a new one; and, with --title, one whose title contains TEXT, or one of
//  TEXT's `|`-separated alternatives), waited
//  for up to --wait seconds. Filming stops when the markers file says `end`,
//  or after --timeout seconds, or when the window goes. Once filming, it
//  appends `filming T` to the markers file, which the player waits for before
//  it takes down its calibration card. DIR gets frame-NNNNN.png and
//  frames.txt, a line per frame: its number and its presentation time, in
//  CLOCK_UPTIME_RAW nanoseconds.
//
//  The window is filmed where it is, behind whatever covers it: nothing is
//  brought to the front for it. Two terminals need help with that. Ghostty
//  makes its first window only when it is first activated, so a new instance
//  opened in the background (`open -g`) has none: --wake activates it if no
//  window has come after a second and a half. iTerm2 and Warp bring
//  themselves to the front for a document opened in them, `-g` or not. For
//  both, --refront PID gives the front back to that app (the one in front
//  before the terminal was opened, from --front) as soon as the window is
//  there, and again over the next few seconds — but only while the terminal is
//  still in front, so a person who has clicked elsewhere meanwhile is left
//  alone.
//
//  Behind is not the same as hidden. ScreenCaptureKit films a covered window
//  as well as an uncovered one, but a terminal may stop drawing a window that
//  macOS reports as wholly occluded: Ghostty does (a covered Ghostty window's
//  film freezes on its last picture), Terminal.app does not. So the window
//  must show at least a sliver from behind the frontmost app's windows (those
//  are the only ones above it once the front is given back). --spot picks,
//  from the screen's four corners, the one where a window of that size shows
//  most, as `x y shown` (the top-left in points from the top-left of the
//  screen's visible area, which is how Ghostty's window-position-x/y count,
//  and the fraction that shows); the recorder warns if the filmed window is
//  wholly covered.
//
//  ScreenCaptureKit sends a frame only when the window's pixels change, so a
//  still screen is one frame, not one per tick: the encoder turns the gaps
//  between presentation times into each frame's duration.
//
//  Needs Screen Recording permission for the app it runs under (System
//  Settings → Privacy & Security → Screen & System Audio Recording).
//
//  Created by Wade Tregaskis
//  License: MIT

import Accelerate
import AppKit
import CoreMedia
import Foundation
import ScreenCaptureKit
import UniformTypeIdentifiers

struct Options {
    var pid: pid_t?
    var exclude: Set<CGWindowID> = []
    var out = "frames"
    var markers: String?
    var scale = 1.0
    var fps = 30
    var wait = 20.0
    var timeout = 120.0
    var list = false
    var front = false
    var title: String?
    var wake = false
    var refront: pid_t?
    var spot: CGSize?
    var cursor: String?

    init(_ arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        func value(_ name: String) -> String {
            guard let value = iterator.next() else { Self.usage("\(name) needs a value") }
            return value
        }
        while let argument = iterator.next() {
            switch argument {
            case "--pid": pid = pid_t(value(argument))
            case "--exclude": exclude = Set(value(argument).split(separator: ",").compactMap { CGWindowID($0) })
            case "--out": out = value(argument)
            case "--markers": markers = value(argument)
            case "--scale": scale = Double(value(argument)) ?? scale
            case "--fps": fps = Int(value(argument)) ?? fps
            case "--wait": wait = Double(value(argument)) ?? wait
            case "--timeout": timeout = Double(value(argument)) ?? timeout
            case "--list": list = true
            case "--front": front = true
            case "--title": title = value(argument)
            case "--wake": wake = true
            case "--refront": refront = pid_t(value(argument))
            case "--cursor": cursor = value(argument)
            case "--spot":
                let parts = value(argument).split(separator: "x").compactMap { Double($0) }
                if parts.count == 2 { spot = CGSize(width: parts[0], height: parts[1]) }
            default: Self.usage("unknown argument \(argument)")
            }
        }
        if !list, !front, spot == nil, cursor == nil, pid == nil { Self.usage("--pid is required") }
    }

    static func usage(_ message: String) -> Never {
        FileHandle.standardError.write(Data("WindowRecorder: \(message)\n".utf8))
        exit(2)
    }
}

/// Writes each complete frame as a PNG, scaled to the output size, and logs
/// its presentation time.
///
/// The stream's handler only copies the frame's pixels out and returns: the
/// stream hands out a few buffers at a time (`queueDepth`), and a handler that
/// held one while it scaled and compressed a Retina frame (tens of
/// milliseconds) left the stream without buffers, so it dropped every frame
/// that changed meanwhile — eight frames, then a gap of 0.6 s, measured. The
/// scaling (vImage, Lanczos) and the PNG are done on a queue of their own.
final class FrameWriter: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let directory: URL
    let scale: Double
    private(set) var count = 0
    private var log: [String] = []
    private let lock = NSLock()
    private(set) var stopped: Error?
    let encoder: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        return queue
    }()

    init(directory: URL, scale: Double) {
        self.directory = directory
        self.scale = scale
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let pixels = CMSampleBufferGetImageBuffer(buffer)
        else { return }
        // Presentation time on the host clock, which is mach_absolute_time:
        // CLOCK_UPTIME_RAW, in nanoseconds, is the same clock.
        let time = CMSampleBufferGetPresentationTimeStamp(buffer)
        let nanoseconds = UInt64(CMTimeGetSeconds(time) * 1_000_000_000)

        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        let width = CVPixelBufferGetWidth(pixels)
        let height = CVPixelBufferGetHeight(pixels)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
        guard let base = CVPixelBufferGetBaseAddress(pixels) else {
            CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
            return
        }
        let frame = Data(bytes: base, count: rowBytes * height)
        CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
        // Where in the buffer the window's picture is. Mostly all of it, but
        // now and then the stream sends a frame drawn at 1× into the 2× buffer
        // — the picture in its top-left quarter, the rest blank (seen with a
        // Ghostty window, 2026-10-25) — and says so in these two attachments:
        // the content's rectangle in points and its scale. That region is
        // scaled to the full output size like any other frame.
        var region = CGRect(x: 0, y: 0, width: width, height: height)
        if let info = attachments.first,
           let rectDictionary = info[.contentRect] as? NSDictionary,
           let rect = CGRect(dictionaryRepresentation: rectDictionary),
           let scale = info[.scaleFactor] as? Double, scale > 0 {
            let pixelsRect = CGRect(
                x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
                .integral.intersection(region)
            if !pixelsRect.isEmpty, pixelsRect.width >= 16, pixelsRect.height >= 16 { region = pixelsRect }
        }

        let picture = region
        lock.lock()
        let index = count
        count += 1
        log.append("\(index) \(nanoseconds)")
        lock.unlock()
        encoder.addOperation { [self] in
            write(frame, width: width, height: height, rowBytes: rowBytes, region: picture, index: index)
        }
    }

    /// Scales one BGRA frame (premultiplied, as the stream delivers it) — the
    /// `region` of it the window's picture fills — to the output size, and
    /// writes it as frame-NNNNN.png.
    private func write(_ frame: Data, width: Int, height: Int, rowBytes: Int, region: CGRect, index: Int) {
        var frame = frame
        let outWidth = max(1, Int((Double(width) * scale).rounded()))
        let outHeight = max(1, Int((Double(height) * scale).rounded()))
        let regionX = Int(region.minX), regionY = Int(region.minY)
        let regionWidth = Int(region.width), regionHeight = Int(region.height)
        let outRowBytes = outWidth * 4
        var scaled = Data(count: outRowBytes * outHeight)
        let error = frame.withUnsafeMutableBytes { source in
            scaled.withUnsafeMutableBytes { destination in
                var from = vImage_Buffer(
                    data: source.baseAddress! + regionY * rowBytes + regionX * 4,
                    height: vImagePixelCount(regionHeight), width: vImagePixelCount(regionWidth), rowBytes: rowBytes)
                var to = vImage_Buffer(data: destination.baseAddress, height: vImagePixelCount(outHeight),
                                       width: vImagePixelCount(outWidth), rowBytes: outRowBytes)
                return vImageScale_ARGB8888(&from, &to, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }
        guard error == kvImageNoError, let provider = CGDataProvider(data: scaled as CFData),
              let image = CGImage(
                width: outWidth, height: outHeight, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: outRowBytes,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                         | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return }
        let url = directory.appendingPathComponent(String(format: "frame-%05d.png", index))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock(); stopped = error; lock.unlock()
    }

    func writeLog() throws {
        encoder.waitUntilAllOperationsAreFinished()
        lock.lock(); let lines = log; lock.unlock()
        try (lines.joined(separator: "\n") + "\n").write(
            to: directory.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)
    }
}

func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

/// Whether the screen is locked. Nothing is drawn behind the lock screen (and
/// the frames the stream sends around it are not the window's own), so a clip
/// filmed through a lock is spoiled.
func screenIsLocked() -> Bool {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
}

/// Appends a line to the markers file (`O_APPEND`: the player writes to it too).
func mark(_ line: String, in path: String?) {
    guard let path else { return }
    let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
    guard descriptor >= 0 else { return }
    let bytes = Array((line + "\n").utf8)
    _ = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    close(descriptor)
}

/// The frontmost app's on-screen windows, in global display coordinates
/// (top-left origin, points): what covers a window just behind them.
func frontmostCover() -> [CGRect] {
    guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
          let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
    else { return [] }
    return list.compactMap { info in
        guard (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == front,
              (info[kCGWindowLayer as String] as? Int) == 0,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds)
        else { return nil }
        return rect
    }
}

/// How much of `rect` the rectangles in `cover` leave showing, as a fraction:
/// counted on a 10-point lattice, which is plenty to tell none from some.
func shownFraction(of rect: CGRect, under cover: [CGRect]) -> Double {
    var shown = 0, total = 0
    for x in stride(from: rect.minX + 5, to: rect.maxX, by: 10) {
        for y in stride(from: rect.minY + 5, to: rect.maxY, by: 10) {
            total += 1
            if !cover.contains(where: { $0.contains(CGPoint(x: x, y: y)) }) { shown += 1 }
        }
    }
    return total == 0 ? 0 : Double(shown) / Double(total)
}

/// The corner of the main screen's visible area where a window of `size`
/// shows most from behind the frontmost app's windows.
@MainActor
func bestSpot(for size: CGSize) -> (x: Double, y: Double, shown: Double) {
    guard let screen = NSScreen.screens.first else { return (0, 0, 0) }
    // NSScreen counts from the bottom-left, the window list from the top-left.
    let full = screen.frame, visible = screen.visibleFrame
    let area = CGRect(x: visible.minX, y: full.maxY - visible.maxY, width: visible.width, height: visible.height)
    let cover = frontmostCover()
    let width = min(size.width, area.width), height = min(size.height, area.height)
    var best = (x: 0.0, y: 0.0, shown: -1.0)
    for (x, y) in [(area.maxX - width, area.minY), (area.maxX - width, area.maxY - height),
                   (area.minX, area.maxY - height), (area.minX, area.minY)] {
        let shown = shownFraction(of: CGRect(x: x, y: y, width: width, height: height), under: cover)
        if shown > best.shown { best = (x - area.minX, y - area.minY, shown) }
    }
    return best
}

/// Gives the front back to `pid` if `terminal` has taken it.
@MainActor
func refront(_ pid: pid_t?, from terminal: pid_t?) {
    guard let pid, let terminal, NSWorkspace.shared.frontmostApplication?.processIdentifier == terminal else { return }
    NSRunningApplication(processIdentifier: pid)?.activate(options: [])
}

func markersSay(_ word: String, in path: String?) -> Bool {
    guard let path, let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
    return text.split(separator: "\n").contains { $0.hasPrefix(word + " ") }
}

/// The process's windows a person would call windows: on screen, in the
/// normal layer, and bigger than a tooltip.
func windows(of pid: pid_t?) async throws -> [SCWindow] {
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    return content.windows.filter {
        (pid == nil || $0.owningApplication?.processID == pid)
            && $0.windowLayer == 0 && $0.frame.width > 120 && $0.frame.height > 80
    }
}

@main
struct WindowRecorder {
    static func main() async throws {
        let options = Options(CommandLine.arguments)
        // Connects to the window server before anything asks about screens.
        _ = NSApplication.shared
        if let path = options.cursor {
            try saveCursor(to: path)
            return
        }
        if !options.list, !options.front, options.spot == nil, screenIsLocked() {
            Options.usage("the screen is locked: nothing can be filmed until it is unlocked")
        }

        if options.front {
            print(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
            return
        }
        if let size = options.spot {
            let spot = bestSpot(for: size)
            print(Int(spot.x), Int(spot.y), String(format: "%.2f", spot.shown))
            return
        }
        if options.list {
            for window in try await windows(of: options.pid) {
                let owner = window.owningApplication
                print("\(window.windowID)\t\(owner?.processID ?? 0)\t\(owner?.bundleIdentifier ?? "-")\t"
                      + "\(Int(window.frame.width))×\(Int(window.frame.height))\t\(window.title ?? "")")
            }
            return
        }

        let started = now()
        let waitUntil = started + UInt64(options.wait * 1e9)
        var found: SCWindow?
        var woken = false
        while found == nil {
            found = try await windows(of: options.pid)
                .filter { !options.exclude.contains($0.windowID) }
                .filter { window in
                    // Alternatives, `|` between them: a terminal may title the window by the
                    // script's own title or by the command running in it.
                    options.title.map { $0.split(separator: "|").contains { (window.title ?? "").contains($0) } } ?? true
                }
                .max { $0.windowID < $1.windowID }
            if found == nil {
                if now() > waitUntil { Options.usage("no new window of process \(options.pid ?? 0) appeared") }
                if options.wake, !woken, now() > started + 1_500_000_000, let pid = options.pid {
                    woken = true
                    NSRunningApplication(processIdentifier: pid)?.activate(options: [])
                }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        guard let window = found else { return }
        refront(options.refront, from: options.pid)

        let directory = URL(fileURLWithPath: options.out)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        // Filmed at the display's own resolution and scaled by the writer,
        // with Lanczos (vImage's high-quality resampling), which keeps text
        // sharper than the stream's own scaler.
        let backing = Double(filter.pointPixelScale)
        configuration.width = Int(window.frame.width * backing)
        configuration.height = Int(window.frame.height * backing)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.queueDepth = 8
        // sRGB, as the WebP is: the encoder writes the bytes as they come.
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        let writer = FrameWriter(directory: directory, scale: options.scale / backing)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: writer)
        let queue = DispatchQueue(label: "frames")
        try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        FileHandle.standardError.write(Data(
            "WindowRecorder: filming window \(window.windowID) (\(Int(window.frame.width))×\(Int(window.frame.height)) pt)\n".utf8))
        mark("filming \(now())", in: options.markers)
        if shownFraction(of: window.frame, under: frontmostCover()) == 0,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != options.pid {
            FileHandle.standardError.write(Data(
                "WindowRecorder: warning: the window is wholly covered; a terminal that stops drawing a window it cannot see (Ghostty) will freeze\n".utf8))
        }

        let deadline = now() + UInt64(options.timeout * 1e9)
        let refrontUntil = now() + 6_000_000_000
        var reason = "timeout"
        while now() < deadline {
            if now() < refrontUntil { refront(options.refront, from: options.pid) }
            if markersSay("end", in: options.markers) { reason = "end marker"; break }
            if screenIsLocked() { reason = "screen locked"; break }
            if writer.stopped != nil { reason = "stream stopped"; break }
            try await Task.sleep(for: .milliseconds(30))
        }
        // A beat more, so the frame that was on the screen at `end` is in.
        try await Task.sleep(for: .milliseconds(150))
        try? await stream.stopCapture()
        queue.sync {}  // the last frame's handler has run
        try writer.writeLog()
        print("WindowRecorder: \(writer.count) frames of window \(window.windowID) to \(directory.path) (\(reason))")
        if reason == "timeout" || reason == "screen locked" { exit(1) }
    }
}

/// Writes the system's arrow pointer to `path` as a PNG, at the main screen's
/// backing scale (the scale the films are taken at), and prints its hot spot
/// in that image's pixels. The encoder draws it where a clip's script points:
/// the pointer a person on this machine would have seen, not a drawing of one.
@MainActor
func saveCursor(to path: String) throws {
    let cursor = NSCursor.arrow
    let scale = NSScreen.main?.backingScaleFactor ?? 2
    let size = cursor.image.size
    // Drawn into a bitmap of exactly the pointer's size at the screen's scale.
    // `cgImage(forProposedRect:)` hands back whichever representation it
    // likes best, and the arrow's include large ones (for the accessibility
    // pointer sizes): written as they came, the clips drew a pointer several
    // times its size.
    let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { Options.usage("the arrow pointer could not be drawn") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    cursor.image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        Options.usage("the arrow pointer could not be written as a PNG")
    }
    try png.write(to: URL(fileURLWithPath: path))
    let hotSpot = cursor.hotSpot
    print(Int((hotSpot.x * scale).rounded()), Int((hotSpot.y * scale).rounded()))
}
