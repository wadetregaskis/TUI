//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIEnvironmentDocs

let section = TUIEnvironmentVariables.manPageSection()

print("UsesTUIEnvironmentDocs: \(TUIEnvironmentVariables.all.count) variables, \(section.utf8.count) bytes")
