//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SidebarRowSizeTests.swift
//
//  `\.sidebarRowSize` reads `.medium`, the one size a terminal row has. A
//  write does not compile (the property has no setter), which no test here can
//  state; the declaration's documentation records why.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation

@Suite("Sidebar row size")
struct SidebarRowSizeTests {
    @Test("A sidebar's rows are always medium")
    func alwaysMedium() {
        #expect(EnvironmentValues().sidebarRowSize == .medium)
        #expect(Set<SidebarRowSize>([.small, .medium, .large]).count == 3)
    }
}
