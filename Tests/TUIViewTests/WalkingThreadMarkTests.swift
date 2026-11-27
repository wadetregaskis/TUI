//  🖥️ TUI — A Terminal UI framework for Swift
//  WalkingThreadMarkTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIView

#if !canImport(WASILibc)  // One thread there, and no `Thread` to start another.
    /// `BindingReads` notes a binding's read only on the thread walking a
    /// frame, which off Darwin and WebAssembly it knows by this mark: on Linux
    /// and Windows a pool thread drains the main actor, so the main thread is
    /// not the answer. Darwin asks `Thread.isMainThread` instead, but the mark
    /// is compiled there too, so what decides the other platforms is tested on
    /// every one.
    @Suite("Walking-thread mark")
    struct WalkingThreadMarkTests {

        @Test("No thread is marked until one marks itself")
        func unmarked() async {
            let mark = WalkingThreadMark()
            #expect(!mark.isCallingThread)
            #expect(await onAnotherThread { !mark.isCallingThread })
        }

        @Test("The thread that marks itself is marked, and no other is")
        func marksOnlyTheCaller() async {
            let mark = WalkingThreadMark()
            // Keep the marking thread alive while the other threads check it:
            // `WalkingThreadMark` identifies a thread by its `Thread` object's
            // address, which is unique only while that thread runs. Once an
            // exited `Thread` is freed, a cooperative pool thread's first lazy
            // `Thread.current` (or another spawned `Thread`) can reuse its
            // address.
            let release = DispatchSemaphore(value: 0)
            let markedThreadSeesIt: Bool = await withCheckedContinuation { continuation in
                Thread {
                    mark.set()
                    continuation.resume(returning: mark.isCallingThread)
                    release.wait()
                    mark.clear()
                }.start()
            }
            defer { release.signal() }
            #expect(markedThreadSeesIt)
            #expect(!mark.isCallingThread, "this test's thread found itself marked")
            #expect(await onAnotherThread { !mark.isCallingThread }, "a third thread found itself marked")
        }

        @Test("A mark cleared by another thread is gone for the thread that set it")
        func clearedFromAnotherThread() async {
            let mark = WalkingThreadMark()
            let stillMarked = await onAnotherThread {
                mark.set()
                let marked = mark.isCallingThread
                let done = DispatchSemaphore(value: 0)
                Thread {
                    mark.clear()
                    done.signal()
                }.start()
                done.wait()
                return marked && mark.isCallingThread
            }
            #expect(!stillMarked)
        }

        @Test("A thread marking itself takes the mark from the one before")
        func lastToMarkHoldsIt() async {
            let mark = WalkingThreadMark()
            let firstStillMarked = await onAnotherThread {
                mark.set()
                let done = DispatchSemaphore(value: 0)
                Thread {
                    mark.set()
                    done.signal()
                }.start()
                done.wait()
                return mark.isCallingThread
            }
            #expect(!firstStillMarked)
        }

        /// Runs `body` on a thread started for it, which is never this test's
        /// own nor one marked before it started.
        private func onAnotherThread<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
            await withCheckedContinuation { continuation in
                Thread { continuation.resume(returning: body()) }.start()
            }
        }
    }
#endif
