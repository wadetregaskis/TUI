//  🖥️ TUI — A Terminal UI framework for Swift
//  LargeStack.swift
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)
    import WinSDK
#endif

/// Runs a frame's walk on a stack large enough for a deep page, wherever the
/// thread it is asked on has a small one.
///
/// A Windows thread gets the stack its executable names, 1 MiB unless the
/// program was linked asking for more: an app's main thread, and the
/// libdispatch workers Swift Testing runs a `@MainActor` test on there. macOS
/// gives a main thread 8 MiB and Linux 8 MiB, and a deep page drawn in a debug
/// build needs more than the 768 KiB a 1 MiB thread leaves above
/// ``StackGuard/reserveBytes``: the guard then draws its deepest views empty
/// (the Example's Animation page lost its panel, built by Swift 6.4.2). An app
/// should not have to link with a bigger stack to draw its pages whole (owner,
/// 2026-11-17), so TUI brings its own.
///
/// On Windows, where the thread's stack is smaller than ``bytes``, `body` runs
/// on a fiber: a stack of ``bytes`` reserved once for the thread and committed
/// only as it is used, switched to and back on the same thread. The thread is
/// the same, so its thread-locals, the running task and the main actor's
/// checks see nothing different; Windows reports the fiber's stack to
/// `GetCurrentThreadStackLimits` while it runs, which is what ``StackGuard``
/// measures by. Everywhere else, and on a thread whose stack is already as
/// large, `body` just runs.
package enum LargeStack {
    /// The stack a walk is given: what macOS gives a main thread.
    package static let bytes = 8 << 20

    /// `body`, on a stack of at least ``bytes``.
    ///
    /// Nests: asked again from inside `body`, it runs the inner body where it
    /// is. Not reentrant across a suspension, as nothing synchronous is.
    package static func run<T>(_ body: () -> T) -> T {
        #if os(Windows)
            return FiberStack.run(body)
        #else
            return body()
        #endif
    }
}

#if os(Windows)
    /// One thread's fiber and what it is to run: kept in a fiber-local slot of
    /// the thread's own fiber, made the first time the thread asks, and let go
    /// of, the large fiber deleted, when the thread ends.
    ///
    /// The fibers are kept as their addresses' bits: a fiber is a raw pointer
    /// in Swift, and this class's storage then has nothing unsafe in it.
    private final class FiberStack {
        /// The thread's own fiber, which the walk switches back to.
        private var threadFiber: UInt = 0

        /// The fiber with the large stack.
        private var largeFiber: UInt = 0

        /// What the large fiber runs next.
        private var work: (() -> Void)?

        /// Whether the large fiber is running: a nested ask runs where it is.
        private var running = false

        /// The slot each thread's instance is kept in. A process-wide index of
        /// the operating system's, private, through which nothing outside this
        /// file can see one thread's instance from another.
        ///
        /// Fiber-local, not thread-local, for its callback: when the thread
        /// ends, Windows hands ``release`` what the slot holds on the fiber the
        /// thread ends on, its own, and the large fiber's stack — 8 MiB
        /// reserved, and as much committed as the deepest walk used — goes
        /// with the thread. A thread-local slot has no such callback, and a
        /// libdispatch worker that drew a frame and later ended left its stack
        /// behind. Read from the large fiber, the slot is that fiber's and
        /// empty, so a nested ask finds no instance and runs where it is.
        private static let slot: DWORD = unsafe FlsAlloc(release)

        /// What the slot's callback does with a thread's instance as the
        /// thread ends: deletes the large fiber, which is not running, as the
        /// thread ends on its own, and lets go of the instance.
        private static let release: PFLS_CALLBACK_FUNCTION = { value in
            guard let value = unsafe value else { return }
            let stack = unsafe Unmanaged<FiberStack>.fromOpaque(value).takeRetainedValue()
            unsafe DeleteFiber(UnsafeMutableRawPointer(bitPattern: stack.largeFiber))
        }

        /// Whether a walk on this thread needs the large stack: its own is
        /// smaller than ``LargeStack/bytes``.
        private static var threadStackIsSmall: Bool {
            var low: ULONG_PTR = 0
            var high: ULONG_PTR = 0
            unsafe GetCurrentThreadStackLimits(&low, &high)
            return high > low && Int(high - low) < LargeStack.bytes
        }

        static func run<T>(_ body: () -> T) -> T {
            // `FLS_OUT_OF_INDEXES`, which the SDK spells with a cast Swift
            // does not import.
            guard slot != DWORD.max, threadStackIsSmall else { return body() }
            guard let stack = current(), !stack.running else { return body() }
            var result: T?
            withoutActuallyEscaping(body) { body in
                stack.work = { result = body() }
                stack.running = true
                unsafe SwitchToFiber(UnsafeMutableRawPointer(bitPattern: stack.largeFiber))
                stack.running = false
                stack.work = nil
            }
            // swift-format-ignore: NeverForceUnwrap
            return result!
        }

        /// This thread's instance, made — and the thread made a fiber, and the
        /// large fiber created — the first time it asks; `nil` where the
        /// thread is a fiber already, of someone else's, or a fiber cannot be
        /// made, and the walk then runs where it is.
        private static func current() -> FiberStack? {
            if let existing = unsafe FlsGetValue(slot) {
                return unsafe Unmanaged<FiberStack>.fromOpaque(existing).takeUnretainedValue()
            }
            guard !IsThreadAFiber() else { return nil }
            let stack = FiberStack()
            let opaque = unsafe Unmanaged.passRetained(stack).toOpaque()
            guard let large = unsafe CreateFiberEx(64 * 1024, SIZE_T(LargeStack.bytes), 0, fiberMain, opaque) else {
                unsafe Unmanaged<FiberStack>.fromOpaque(opaque).release()
                return nil
            }
            guard let thread = unsafe ConvertThreadToFiber(nil) else {
                unsafe DeleteFiber(large)
                unsafe Unmanaged<FiberStack>.fromOpaque(opaque).release()
                return nil
            }
            stack.threadFiber = UInt(bitPattern: thread)
            stack.largeFiber = UInt(bitPattern: large)
            // Kept for the thread's life, retained by the slot, as the fiber
            // that refers to it is, until ``release`` lets go of both.
            _ = unsafe FlsSetValue(slot, opaque)
            return stack
        }

        /// Runs ``work`` and lets go of it, in a frame of its own, so nothing
        /// of it is still held on the large stack when the fiber switches back:
        /// `withoutActuallyEscaping` traps if the body outlives its call.
        @inline(never)
        private func runWork() {
            work?()
        }

        /// The large fiber: runs each walk it is handed, then switches back. It
        /// never returns, which would end the thread.
        private static let fiberMain: LPFIBER_START_ROUTINE = { parameter in
            guard let parameter = unsafe parameter else { fatalError("the large fiber was made with no FiberStack") }
            let stack = unsafe Unmanaged<FiberStack>.fromOpaque(parameter).takeUnretainedValue()
            while true {
                stack.runWork()
                unsafe SwitchToFiber(UnsafeMutableRawPointer(bitPattern: stack.threadFiber))
            }
        }
    }
#endif
