//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  WindowRecorder: films one window with ScreenCaptureKit, to PNG frames and
//  the instant each was presented.
//
//      WindowRecorder --pid PID [--exclude ID,ID…] --out DIR [--markers FILE]
//                     [--scale 1] [--fps 30] [--wait 20] [--timeout 120] [--activate]
//      WindowRecorder --list [--pid PID]      the windows on screen, with their ids
//
//  The window is the newest on-screen window of process PID (not one in
//  --exclude, which lists the windows that app already had when it was asked
//  for a new one), waited for up to --wait seconds. Filming stops when the
//  markers file says `end`, or after --timeout seconds, or when the window
//  goes. --activate brings the window's app to the front once the window is
//  there, so it is filmed with an active title bar. DIR gets frame-NNNNN.png and frames.txt, a line per frame: its number
//  and its presentation time, in CLOCK_UPTIME_RAW nanoseconds.
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
    var activate = false

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
            case "--activate": activate = true
            default: Self.usage("unknown argument \(argument)")
            }
        }
        if !list, pid == nil { Self.usage("--pid is required") }
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

        lock.lock()
        let index = count
        count += 1
        log.append("\(index) \(nanoseconds)")
        lock.unlock()
        encoder.addOperation { [self] in
            write(frame, width: width, height: height, rowBytes: rowBytes, index: index)
        }
    }

    /// Scales one BGRA frame (premultiplied, as the stream delivers it) and
    /// writes it as frame-NNNNN.png.
    private func write(_ frame: Data, width: Int, height: Int, rowBytes: Int, index: Int) {
        var frame = frame
        let outWidth = max(1, Int((Double(width) * scale).rounded()))
        let outHeight = max(1, Int((Double(height) * scale).rounded()))
        let outRowBytes = outWidth * 4
        var scaled = Data(count: outRowBytes * outHeight)
        let error = frame.withUnsafeMutableBytes { source in
            scaled.withUnsafeMutableBytes { destination in
                var from = vImage_Buffer(data: source.baseAddress, height: vImagePixelCount(height),
                                         width: vImagePixelCount(width), rowBytes: rowBytes)
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

        if options.list {
            for window in try await windows(of: options.pid) {
                let owner = window.owningApplication
                print("\(window.windowID)\t\(owner?.processID ?? 0)\t\(owner?.bundleIdentifier ?? "-")\t"
                      + "\(Int(window.frame.width))×\(Int(window.frame.height))\t\(window.title ?? "")")
            }
            return
        }

        let waitUntil = now() + UInt64(options.wait * 1e9)
        var found: SCWindow?
        while found == nil {
            found = try await windows(of: options.pid)
                .filter { !options.exclude.contains($0.windowID) }
                .max { $0.windowID < $1.windowID }
            if found == nil {
                if now() > waitUntil { Options.usage("no new window of process \(options.pid ?? 0) appeared") }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        guard let window = found else { return }
        if options.activate, let pid = options.pid {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
        }

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

        let deadline = now() + UInt64(options.timeout * 1e9)
        var reason = "timeout"
        while now() < deadline {
            if markersSay("end", in: options.markers) { reason = "end marker"; break }
            if writer.stopped != nil { reason = "stream stopped"; break }
            try await Task.sleep(for: .milliseconds(30))
        }
        // A beat more, so the frame that was on the screen at `end` is in.
        try await Task.sleep(for: .milliseconds(150))
        try? await stream.stopCapture()
        queue.sync {}  // the last frame's handler has run
        try writer.writeLog()
        print("WindowRecorder: \(writer.count) frames of window \(window.windowID) to \(directory.path) (\(reason))")
        if reason == "timeout" { exit(1) }
    }
}
