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
/// Two questions TUIkit asks of a process chain read it: which terminal
/// application owns a tmux client's window (``TerminalHost``), and whether the
/// person at the keyboard is on this machine at all — a chain that passes
/// through `sshd` or `mosh-server` reached the terminal over the network
/// (``ClipboardLocality``).
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

    /// The short command name the kernel keeps for a process — `p_comm` on
    /// Darwin, the `comm` field of `/proc/<pid>/stat` on Linux — or `nil` if it
    /// has exited or is unreadable.
    ///
    /// The kernel's name, not the executable's path, on purpose: it is readable
    /// for a process another user owns (the root half of `sshd-session`), where
    /// `proc_pidpath` is refused. It is cut to 15 or 16 bytes, which every name
    /// matched against it fits.
    static func commandName(of pid: pid_t) -> String? {
        #if canImport(Darwin)
            guard var info = kernelInfo(of: pid) else { return nil }
            let name = withUnsafeBytes(of: &info.kp_proc.p_comm) { raw -> String? in
                String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8)
            }
            return name?.isEmpty == false ? name : nil
        #elseif canImport(Glibc) || canImport(Musl)
            return procStat(of: pid)?.name
        #else
            return nil
        #endif
    }

    /// The command names from `pid` up to the root of the process tree,
    /// `pid`'s own first — or `nil` when a link could not be read before the
    /// root was reached.
    ///
    /// `nil` is a refusal to answer, not an empty chain: a caller deciding
    /// something from what is NOT in the chain must not decide it from a chain
    /// that stopped early. The bound is for a pid recycled into a cycle
    /// mid-walk, which would otherwise spin forever; a real chain is a handful
    /// of links.
    static func commandNames(from pid: pid_t, limit: Int = 64) -> [String]? {
        var names: [String] = []
        var current = pid
        for _ in 0..<limit {
            guard let name = commandName(of: current) else { return nil }
            names.append(name)
            // pid 1 (launchd, init, systemd) roots every chain, and a parent of
            // 0 is the root too: the kernel's own, on Linux.
            guard current > 1, let parent = parent(of: current) else {
                return current <= 1 || parentIsRoot(current) ? names : nil
            }
            current = parent
        }
        return nil
    }

    /// Whether `pid`'s recorded parent is 0, which is the root of the tree
    /// rather than an unreadable link.
    private static func parentIsRoot(_ pid: pid_t) -> Bool {
        #if canImport(Darwin)
            return kernelInfo(of: pid)?.kp_eproc.e_ppid == 0
        #elseif canImport(Glibc) || canImport(Musl)
            return procStat(of: pid)?.parentField == 0
        #else
            return false
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
            var name: String
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
                let open = stat.firstIndex(of: "("),
                let close = stat.lastIndex(of: ")"), open < close
            else { return nil }
            let name = String(stat[stat.index(after: open)..<close])
            let fields = stat[stat.index(after: close)...].split(separator: " ")
            guard fields.count >= 2, let parent = Int32(fields[1]) else { return nil }
            return ProcStat(name: name, parentField: parent)
        }
    #endif
}
