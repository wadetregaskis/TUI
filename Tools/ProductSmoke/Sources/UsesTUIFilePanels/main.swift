//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFilePanels

let importer = Text("Open").fileImporter(isPresented: .constant(false), allowedContentTypes: []) { _ in }

print("UsesTUIFilePanels: \(String(reflecting: type(of: importer)))")
