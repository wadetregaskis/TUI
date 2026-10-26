//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  ScreenClips: the README's clips, each a TUI app that plays itself.
//
//      ScreenClips list                      every clip: id, size, length, terminal, title
//      ScreenClips info <clip>               one clip's size and length, as shell variables
//      ScreenClips framing <clip>            its camera's moves and output width, as JSON, for encode.py
//      ScreenClips play <clip> [--markers F] run it in this terminal, its script typed into it
//
//  `--child <clip>` is the app itself, as the player starts it under its own
//  pseudo-terminal; run on its own it is the app with nobody at the keys.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

@MainActor
func clip(named id: String?) -> Clip {
    guard let id, let clip = (clips + reviewScenes).first(where: { $0.id == id }) else {
        let known = clips.map(\.id).joined(separator: ", ")
        FileHandle.standardError.write(Data("ScreenClips: no clip named \(id ?? "(none)"); known: \(known)\n".utf8))
        exit(2)
    }
    return clip
}

switch arguments.first {
case "list":
    for clip in clips {
        let length = String(format: "%.1f s", clip.duration)
        print("\(clip.id)\t\(clip.columns)×\(clip.rows)\t\(length)\t\(clip.terminal)\t\(clip.title)")
    }
case "info":
    let clip = clip(named: arguments.dropFirst().first)
    print("columns=\(clip.columns)")
    print("rows=\(clip.rows)")
    print("duration=\(clip.duration)")
    print("terminal=\(clip.terminal)")
    print("title='\(clip.title)'")
    print("output=\(clip.output)")
    print("carousel='\(clip.carousel.joined(separator: " "))'")
case "framing":
    print(clip(named: arguments.dropFirst().first).framingJSON)
case "play":
    let clip = clip(named: arguments.dropFirst().first)
    var markers: String?
    if let index = arguments.firstIndex(of: "--markers"), index + 1 < arguments.count { markers = arguments[index + 1] }
    exit(Player(clip: clip, markers: markers).play())
case "--child":
    await clip(named: arguments.dropFirst().first).run()
default:
    print("usage: ScreenClips list | info <clip> | framing <clip> | play <clip> [--markers FILE]")
    exit(arguments.isEmpty ? 0 : 2)
}
