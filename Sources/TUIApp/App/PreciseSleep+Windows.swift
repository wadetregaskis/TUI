//  🖥️ TUI — A Terminal UI framework for Swift
//  PreciseSleep+Windows.swift
//
//  A sleep that wakes when it was asked to on Windows, where `Task.sleep`
//  wakes up to two of the clock's 15.6 ms ticks late: what the run loop's
//  timed wait sleeps by there, so a frame lands when it is due.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import Synchronization
import WinSDK

/// Sleeps for a time on Windows to within a millisecond, as `Task.sleep` does
/// elsewhere.
///
/// Every wait on libdispatch's timers keeps Windows' 15.6 ms tick, whatever
/// the process asks of the clock: measured 2026-11-18 (Swift 6.3.3, build
/// 26300), 60 sleeps of 16 ms each took a mean of 30–31 ms with
/// `Task.sleep` (any clock, any tolerance) and 33 ms with `asyncAfter`, with
/// or without `timeBeginPeriod(1)`; a high-resolution waitable timer
/// (`CREATE_WAITABLE_TIMER_HIGH_RESOLUTION`) took 16.4–16.5, and needs no
/// change to the clock. The run loop paces its frames with a timed wait
/// (`StdinArrivalNotifier`), so on the Spinners page, whose animations step on
/// a 16.7 ms lattice, the gaps between frames were the tick's multiples (15–16,
/// 30–32 and 45–48 ms, for 351 of 393): a step due before a tick drew at the
/// one after it, as much as a tick late. With this sleep most are the step's
/// (17–18, 33–36 and 49–52 ms, for 159 of 230), each frame a millisecond or so
/// after it was due.
///
/// So the sleep is a timer of that kind, which the thread pool waits on
/// (`RegisterWaitForSingleObject`) and which resumes the task when it fires.
/// Awaited from the main actor it came back 0.6–0.7 ms after it was due
/// (measured the same day: 16.7 ms for 16, 5.5 for 5). Cancelling the task
/// ends the sleep at once, as `Task.sleep`'s cancellation does (0.2 ms for one
/// of 2 s), without its error: the caller asks `Task.isCancelled`.
enum PreciseSleep {
    /// Sleeps `nanoseconds`, or until the task is cancelled. Where a timer
    /// cannot be made, `Task.sleep`, late as it is.
    static func sleep(nanoseconds: UInt64) async {
        let signal = Signal()
        // Armed before the task suspends, so the wait's handle is known before
        // anything can resume it.
        guard let armed = arm(after: nanoseconds, signalling: signal) else {
            try? await Task.sleep(nanoseconds: nanoseconds)
            return
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in signal.hold(continuation) }
        } onCancel: {
            signal.finish()
        }
        disarm(armed)
    }

    /// A timer and the wait on it, as their handles' bits, and the context
    /// handed to the wait's callback: the signal, retained until ``disarm(_:)``
    /// has made sure the callback will not run again.
    private struct Armed {
        let timer: UInt
        let wait: UInt
        let context: UInt
    }

    /// What `TIMER_ALL_ACCESS` is, which the SDK spells with a macro Swift
    /// does not import.
    private static let timerAccess: DWORD = 0x1F_0003

    /// A high-resolution timer due in `nanoseconds`, and the thread pool's
    /// wait on it, which finishes `signal`.
    private static func arm(after nanoseconds: UInt64, signalling signal: Signal) -> Armed? {
        guard
            let timer = unsafe CreateWaitableTimerExW(
                nil, nil, DWORD(CREATE_WAITABLE_TIMER_HIGH_RESOLUTION), timerAccess)
        else { return nil }
        // Relative, in 100 ns units, as a negative due time says.
        var due = LARGE_INTEGER(QuadPart: -Int64(clamping: max(1, nanoseconds / 100)))
        let context = unsafe Unmanaged.passRetained(signal).toOpaque()
        var wait: HANDLE?
        guard unsafe SetWaitableTimer(timer, &due, 0, nil, nil, false),
            unsafe RegisterWaitForSingleObject(
                &wait, timer, callback, context, INFINITE, ULONG(WT_EXECUTEONLYONCE | WT_EXECUTEINWAITTHREAD)),
            let wait = unsafe wait
        else {
            unsafe Unmanaged<Signal>.fromOpaque(context).release()
            _ = unsafe CloseHandle(timer)
            return nil
        }
        return Armed(timer: UInt(bitPattern: timer), wait: UInt(bitPattern: wait), context: UInt(bitPattern: context))
    }

    /// Ends the wait, waiting for a callback already running, and lets go of
    /// the timer and the wait's hold on the signal.
    private static func disarm(_ armed: Armed) {
        _ = unsafe UnregisterWaitEx(HANDLE(bitPattern: armed.wait), INVALID_HANDLE_VALUE)
        if let context = unsafe UnsafeMutableRawPointer(bitPattern: armed.context) {
            unsafe Unmanaged<Signal>.fromOpaque(context).release()
        }
        _ = unsafe CloseHandle(HANDLE(bitPattern: armed.timer))
    }

    /// The wait's callback, on the thread pool's wait thread: the timer fired.
    private static let callback: WAITORTIMERCALLBACK = { context, _ in
        guard let context = unsafe context else { return }
        unsafe Unmanaged<Signal>.fromOpaque(context).takeUnretainedValue().finish()
    }

    /// Who is waiting, and whether the wait is over: the timer fired, or the
    /// task was cancelled, whichever came first, resumes the waiter once.
    private final class Signal: Sendable {
        private struct State: ~Copyable {
            var continuation: CheckedContinuation<Void, Never>?
            var finished = false
        }

        private let state = Mutex(State())

        /// Holds `continuation` until the wait is over; resumes it at once
        /// where it is over already.
        func hold(_ continuation: CheckedContinuation<Void, Never>) {
            let finished = state.withLock { state in
                if !state.finished { state.continuation = continuation }
                return state.finished
            }
            if finished { continuation.resume() }
        }

        /// The wait is over: resumes the waiter, if one is held, once.
        func finish() {
            let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
                state.finished = true
                defer { state.continuation = nil }
                return state.continuation
            }
            continuation?.resume()
        }
    }
}

#endif
