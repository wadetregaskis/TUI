// The half of `pixel_mouse_probe.py` outside the terminal: opens a window of the
// terminal under test, then posts clicks and moves into THAT window, so each
// phase of the probe hears the same physical points.
//
//   swiftc -O pixel_mouse_driver.swift -o /tmp/pixel_mouse_driver
//   /tmp/pixel_mouse_driver iTerm RESULT.json /path/to/pixel_mouse_probe.py
//
// Takes the pointer for about a minute, so run it when nobody is using the Mac.
// It needs the Accessibility permission to post events (it says so if it has
// not), and it stops rather than click when anything else covers the point. A
// click goes only to a window that was not there when it started. Script and
// wrapper are copied beside RESULT.json: keep that out of ~/Documents, whose
// folder consent stops Ghostty reading them.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 4 else {
    print("usage: pixel_mouse_driver OWNER RESULT.json PROBE.py [--reuse-window]  (OWNER: iTerm, Ghostty, Warp, Terminal, kitty)")
    exit(2)
}
let owner = CommandLine.arguments[1]
let resultPath = CommandLine.arguments[2]
let probeSource = CommandLine.arguments[3]
// A terminal that opens the script as a tab of a window it has (iTerm2, Warp)
// makes no new window: this names the front one instead. Only for a window a
// previous run left, or one that is otherwise yours to click in.
let reuseWindow = CommandLine.arguments.contains("--reuse-window")
guard CGPreflightPostEventAccess() else {
    print("this process may not post events (Accessibility)")
    exit(2)
}

let fileManager = FileManager.default
let controlDirectory = (resultPath as NSString).deletingPathExtension + ".ctl"
try? fileManager.removeItem(atPath: controlDirectory)
try fileManager.createDirectory(atPath: controlDirectory, withIntermediateDirectories: true)
let probe = controlDirectory + "/probe.py"
try fileManager.copyItem(atPath: probeSource, toPath: probe)
let rawOutput = controlDirectory + "/raw.json"
let wrapper = controlDirectory + "/run.command"
try """
#!/bin/sh
export PROBE_OUT='\(rawOutput)'
export PROBE_CTL='\(controlDirectory)'
exec /usr/bin/python3 '\(probe)'
""".write(toFile: wrapper, atomically: true, encoding: .utf8)
try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper)

struct Window {
    var id: Int
    var bounds: CGRect
}

/// The on-screen windows of `owner`, front to back.
func windows(of owner: String?) -> [Window] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { info in
        guard info[kCGWindowLayer as String] as? Int == 0,
            owner == nil || info[kCGWindowOwnerName as String] as? String == owner,
            let id = info[kCGWindowNumber as String] as? Int,
            let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsInfo)
        else { return nil }
        return Window(id: id, bounds: bounds)
    }
}

let before = Set(windows(of: owner).map(\.id))

let launch = Process()
launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
switch owner {
case "Ghostty":
    launch.arguments = [
        "-na", "/Applications/Ghostty.app", "--args", "--initial-command=direct:\(wrapper)",
        "--quit-after-last-window-closed=true", "--window-save-state=never", "--config-default-files=false",
    ]
case "kitty":
    launch.arguments = ["-na", "/Applications/kitty.app", "--args", wrapper]
case "iTerm":
    launch.arguments = ["-a", "iTerm", wrapper]
default:
    launch.arguments = ["-a", owner, wrapper]
}
try launch.run()
launch.waitUntilExit()

func exists(_ name: String) -> Bool { fileManager.fileExists(atPath: controlDirectory + "/" + name) }
func touch(_ name: String) { fileManager.createFile(atPath: controlDirectory + "/" + name, contents: nil) }
func waitFor(_ name: String, seconds: Double = 20) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !exists(name) {
        if Date() > deadline { return false }
        usleep(20_000)
    }
    return true
}

guard waitFor("ready", seconds: 30) else {
    print("the probe never started in \(owner)")
    exit(1)
}
// A window comes on screen a little after its process starts.
var candidate: Window?
for _ in 0..<40 where candidate == nil {
    usleep(100_000)
    candidate = windows(of: owner).first { reuseWindow || !before.contains($0.id) }
}
usleep(300_000)
guard let target = candidate else {
    print("no new \(owner) window")
    exit(1)
}

/// Whether the target is the front window at `point`.
func isFront(at point: CGPoint) -> Bool {
    windows(of: nil).first { $0.bounds.contains(point) }?.id == target.id
}

func post(_ type: CGEventType, at point: CGPoint) {
    let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
    event?.post(tap: .cghidEventTap)
}

/// When each click was posted, phase by phase, on the clock the probe stamps
/// its reads with: a report lost on the way must not shift the rest.
var clickTimes: [String: [Double]] = [:]
var currentPhase = ""

func click(_ point: CGPoint) {
    clickTimes[currentPhase, default: []].append(Date().timeIntervalSince1970)
    post(.mouseMoved, at: point)
    usleep(30_000)
    post(.leftMouseDown, at: point)
    usleep(30_000)
    post(.leftMouseUp, at: point)
    usleep(60_000)
}

// Points inside the text area, in window-relative points: well clear of the
// title bar and edges, and at scattered positions within their cells. Seeded,
// so each run and each terminal gets the same.
var seed: UInt64 = 0x1016
func next() -> Double {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Double((seed >> 33) % 100_000) / 100_000
}
let inset = CGRect(
    x: 14, y: 60, width: target.bounds.width - 28, height: target.bounds.height - 76)
let points = (0..<24).map { _ in
    CGPoint(x: (inset.minX + next() * inset.width).rounded(), y: (inset.minY + next() * inset.height).rounded())
}
let screen = points.map { CGPoint(x: target.bounds.minX + $0.x, y: target.bounds.minY + $0.y) }

guard screen.allSatisfy(isFront) else {
    print("something covers the \(owner) window; not clicking")
    touch("end-cells")
    exit(1)
}

// A first click to take focus, before the probe is listening.
click(screen[0])
usleep(400_000)

func phase(_ name: String, _ body: () -> Void) -> Bool {
    currentPhase = name
    touch("begin-\(name)")
    guard waitFor("go-\(name)") else { return false }
    usleep(100_000)
    body()
    usleep(200_000)
    touch("end-\(name)")
    return waitFor("ack-\(name)")
}

func clickAll(_ list: [CGPoint]) {
    for point in list {
        guard isFront(at: point) else {
            print("covered at \(point); stopping")
            exit(1)
        }
        click(point)
    }
}

func sweep() {
    let start = screen[screen.count / 2]
    post(.mouseMoved, at: start)
    usleep(50_000)
    for step in 0..<64 {
        post(.mouseMoved, at: CGPoint(x: start.x + Double(step % 32), y: start.y))
        usleep(8000)
    }
}

let ok =
    phase("cells") { clickAll(screen) }
    && phase("pixels") { clickAll(screen) }
    && phase("motion-cells", sweep)
    && phase("motion-pixels", sweep)
    && phase("reset") { clickAll(Array(screen.prefix(3))) }
    && phase("resend") { clickAll(Array(screen.prefix(3))) }
guard ok else {
    print("a phase never finished")
    exit(1)
}
// The probe writes its record as it exits.
let deadline = Date().addingTimeInterval(5)
while !fileManager.fileExists(atPath: rawOutput), Date() < deadline { usleep(50_000) }
guard let data = fileManager.contents(atPath: rawOutput),
    var record = try JSONSerialization.jsonObject(with: data) as? [String: Any]
else {
    print("no record")
    exit(1)
}
record["points"] = points.map { [$0.x, $0.y] }
record["window"] = [target.bounds.width, target.bounds.height]
record["owner"] = owner
record["clicks"] = clickTimes
let output = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
try output.write(to: URL(fileURLWithPath: resultPath))
print("wrote \(resultPath)")
