//  🖥️ TUI — A Terminal UI framework for Swift
//  AllocationCount.swift
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(Darwin)
import Darwin
#endif

/// How many heap allocations a piece of work makes, by libmalloc's logging hook
/// (`malloc_logger`, the one MallocStackLogging installs): a count, not a
/// timing, so it needs no quiet machine.
///
/// In a debug build, where generics are not specialised, so an absolute number
/// is not a release build's; what a test can state is a difference, or a count
/// that has to be zero whatever the optimiser does. A `realloc` counts once.
///
/// The count is the TASK's, as the repo's other test seams are
/// (`EditorLayout.buildReporter`, `TabLayout.walkReporter`): ``during(_:)``
/// binds a counter to a task-local, and the hook counts an allocation into the
/// counter the allocating task has bound, if any. So tests counting in
/// parallel each see their own, and a count follows its task across a
/// suspension and into its child tasks, where a per-thread count would lose it
/// and a process-wide one would gather its neighbours'. Not a
/// `TaskLocalReporter`, which is TUIFoundation's and which this module sits
/// below; the counter is a box, not a function, so the compiler bug that type
/// works round does not arise.
public enum AllocationCount {

    /// A count in progress.
    private final class Counter: @unchecked Sendable {
        // Written only by the allocating task, one allocation at a time.
        var count = 0
    }

    /// The counter of the work being counted, while ``during(_:)`` runs it.
    @TaskLocal private static var counter: Counter?

    /// Whether this platform has the hook. Where it does not,
    /// ``during(_:)`` runs the work and answers `-1`.
    public static var isAvailable: Bool {
        #if canImport(Darwin)
        unsafe hook != nil
        #else
        false
        #endif
    }

    #if canImport(Darwin)
    private typealias Logger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

    /// The hook's slot, with the hook in it: installed the first time it is
    /// asked for, and left in, since taking it out could race a test still
    /// counting in another task. Left in, it costs a task-local read per
    /// allocation, which allocates nothing.
    nonisolated(unsafe) private static let hook: UnsafeMutablePointer<Logger?>? = {
        guard let symbol = unsafe dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else { return nil }
        let slot = unsafe symbol.assumingMemoryBound(to: Logger?.self)
        // The task-local's key is a lazily made global: made here, before the
        // hook goes in, not by the hook's first read, inside malloc.
        _ = $counter
        unsafe slot.pointee = { type, _, _, _, _, _ in
            // MALLOC_LOG_TYPE_ALLOCATE is 2. A realloc logs as both.
            guard type & 2 != 0, let counter = Self.counter else { return }
            counter.count &+= 1
        }
        return unsafe slot
    }()
    #endif

    /// The allocations `work` makes, in this task and the tasks it starts as
    /// children, or `-1` where the hook is not available.
    ///
    /// - Parameter work: The work to count.
    public static func during(_ work: () -> Void) -> Int {
        #if canImport(Darwin)
        guard unsafe hook != nil else {
            work()
            return -1
        }
        let counter = Counter()
        $counter.withValue(counter) {
            // Zeroed inside, so binding the task-local is not counted.
            counter.count = 0
            work()
        }
        return counter.count
        #else
        work()
        return -1
        #endif
    }
}
