//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ProcessAncestry.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// A process's parents, as the kernel records them.
///
/// TUIkit reads a process chain to learn which terminal application owns a
/// tmux client's window (``TerminalHost``).
///
/// Every read is a plain system call or a `/proc` file, never a subprocess, so
/// a walk costs microseconds. A process that has exited, or that the kernel
/// will not describe to this user, reads as `nil`, and a walk that meets one
/// says so rather than guessing past it.
enum ProcessAncestry {

    /// The parent of a process, or `nil` if it has exited or is unreadable.
    static func parent(of pid: pid_t) -> pid_t? {
        #if canImport(Darwin)
            guard let info = kernelInfo(of: pid) else { return nil }
            let parent = info.kp_eproc.e_ppid
            return parent > 0 ? parent : nil
        #elseif canImport(Glibc) || canImport(Musl)
            return procStat(of: pid)?.parent
        #else
            // WebAssembly's wasip1 has no processes to walk.
            return nil
        #endif
    }

    #if canImport(Darwin)
        /// The kernel's record of a process, or `nil` if it has exited.
        private static func kernelInfo(of pid: pid_t) -> kinfo_proc? {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            let ok = mib.withUnsafeMutableBufferPointer {
                sysctl($0.baseAddress, u_int($0.count), &info, &size, nil, 0) == 0
            }
            // A dead pid succeeds with size 0 rather than failing — hence both checks.
            guard ok, size > 0 else { return nil }
            return info
        }
    #elseif canImport(Glibc) || canImport(Musl)
        /// The fields of `/proc/<pid>/stat` a walk needs.
        private struct ProcStat {
            var parentField: Int32
            var parent: pid_t? { parentField > 0 ? parentField : nil }
        }

        /// `/proc/<pid>/stat`, read as `pid (comm) state ppid …`.
        ///
        /// The name is parenthesised and may itself hold spaces and
        /// parentheses, so it runs to the LAST `)`; the fields after it are
        /// plain, and the parent is the second of them.
        private static func procStat(of pid: pid_t) -> ProcStat? {
            guard let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
                let close = stat.lastIndex(of: ")")
            else { return nil }
            let fields = stat[stat.index(after: close)...].split(separator: " ")
            guard fields.count >= 2, let parent = Int32(fields[1]) else { return nil }
            return ProcStat(parentField: parent)
        }
    #endif
}
