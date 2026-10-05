//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ProcessAncestryTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

@Suite("Process ancestry")
struct ProcessAncestryTests {
    @Test("A process's parent is the one the kernel reports to the process itself")
    func ownParent() {
        #expect(ProcessAncestry.parent(of: getpid()) == getppid())
    }

    @Test("Following parents from this process reaches the root of the tree")
    func reachesTheRoot() {
        var current = getpid()
        var steps = 0
        while let parent = ProcessAncestry.parent(of: current), steps < 64 {
            current = parent
            steps += 1
        }
        #expect(current == 1)
    }
}
