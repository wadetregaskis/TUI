//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFilePanels

let importer = Text("Open").fileImporter(isPresented: .constant(false), allowedContentTypes: []) { _ in }

print("UsesTUIkitFilePanels: \(String(reflecting: type(of: importer)))")
