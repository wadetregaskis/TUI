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
/// (``SessionLocality``).
///
/// Every read is a plain system call or a `/proc` file, never a subprocess, so
/// a walk costs microseconds. A process that has exited, or that the kernel
/// will not describe to this user, reads as `nil`, and a walk that meets one
/// says so rather than guessing past it.
enum ProcessAncestry {

    /// A process as a chain reads it: its name, and the terminal it is
    /// attached to.
    struct Link: Equatable {
        /// The kernel's short name for it (``commandName(of:)``).
        let name: String
        /// The device number of its controlling terminal — `e_tdev` on
        /// Darwin, `tty_nr` of `/proc/<pid>/stat` on Linux — or `nil` where it
        /// has none (`NODEV` on Darwin, `0` on Linux).
        let terminal: Int32?
    }

    /// The process that holds the terminal `chain`'s first process is
    /// attached to: the first above it attached to another terminal, or to
    /// none — the terminal emulator that draws it, or the GNU screen, tmux,
    /// `sshd` or `mosh-server` that carries it on — or `nil` where that cannot
    /// be told: the first is attached to no terminal, or no process above it
    /// is attached to another.
    ///
    /// A process's terminal is the pty its shell runs on, and the process
    /// that opened the pty's other side runs on another one, or on none: GNU
    /// screen's server runs on none and its windows' processes on the
    /// window's pty (measured, screen 4.00.03 on macOS 15, 2026-10-07: `ps`
    /// shows `SCREEN` on `??` and its window's `login` on `ttys005`). What
    /// stands further up — the shell a GUI terminal was started from, say —
    /// does not stand between the process and what draws it.
    static func terminalHolder(of chain: [Link]) -> Link? {
        guard let own = chain.first?.terminal else { return nil }
        return chain.dropFirst().first { $0.terminal != own }
    }

    /// This process's command names up to the root (``commandNames(from:limit:)``),
    /// or `nil` where they cannot be read: a WebAssembly guest has no
    /// processes to walk, and Windows no walk here (see the `pid_t` API below).
    static func ownCommandNames() -> [String]? {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
            return commandNames(from: getpid())
        #else
            return nil
        #endif
    }

    // The walk by process id. `pid_t` is POSIX's, and wasi-libc declares it
    // too (where every read below answers `nil`: a wasm guest has no
    // processes). Windows has no walk here, and its C runtime is not where
    // `pid_t` comes from (it numbers processes with `DWORD`s), so none of this
    // is compiled there, and nothing above names a `pid_t`.
    #if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(WASILibc)

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
            return kernelInfo(of: pid).flatMap(commandName(in:))
        #elseif canImport(Glibc) || canImport(Musl)
            return procStat(of: pid)?.name
        #else
            return nil
        #endif
    }

    /// The name and controlling terminal of a process, read together, or
    /// `nil` if it has exited or is unreadable.
    static func link(of pid: pid_t) -> Link? {
        #if canImport(Darwin)
            guard let info = kernelInfo(of: pid), let name = commandName(in: info) else { return nil }
            // `NODEV`, `(dev_t)-1`: a macro Swift does not import.
            let terminal = info.kp_eproc.e_tdev
            return Link(name: name, terminal: terminal == -1 ? nil : terminal)
        #elseif canImport(Glibc) || canImport(Musl)
            guard let stat = procStat(of: pid), let terminal = stat.terminalField else { return nil }
            return Link(name: stat.name, terminal: terminal == 0 ? nil : terminal)
        #else
            return nil
        #endif
    }

    /// The links from `pid` up to the root (``chain(from:limit:reading:)``),
    /// `pid`'s own first, or `nil` where one could not be read.
    static func links(from pid: pid_t, limit: Int = 64) -> [Link]? {
        chain(from: pid, limit: limit, reading: link(of:))
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
        chain(from: pid, limit: limit, reading: commandName(of:))
    }

    /// What `read` says of each process from `pid` up to the root, `pid`'s
    /// own first — or `nil` when it said nothing of one, or a link could not
    /// be read, before the root was reached (``commandNames(from:limit:)``).
    static func chain<Value>(from pid: pid_t, limit: Int = 64, reading read: (pid_t) -> Value?) -> [Value]? {
        var values: [Value] = []
        var current = pid
        for _ in 0..<limit {
            guard let value = read(current) else { return nil }
            values.append(value)
            // pid 1 (launchd, init, systemd) roots every chain, and a parent of
            // 0 is the root too: the kernel's own, on Linux.
            guard current > 1, let parent = parent(of: current) else {
                return current <= 1 || parentIsRoot(current) ? values : nil
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

        /// The short name in a process's kernel record, or `nil` where it is
        /// empty or not UTF-8.
        private static func commandName(in info: kinfo_proc) -> String? {
            var info = info
            let name = withUnsafeBytes(of: &info.kp_proc.p_comm) { raw -> String? in
                String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8)
            }
            return name?.isEmpty == false ? name : nil
        }
    #elseif canImport(Glibc) || canImport(Musl)
        /// The fields of `/proc/<pid>/stat` a walk needs.
        private struct ProcStat {
            var name: String
            var parentField: Int32
            /// `tty_nr`, or `nil` where the line is cut short of it.
            var terminalField: Int32?
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
            // state, ppid, pgrp, session, tty_nr.
            let terminal = fields.count >= 5 ? Int32(fields[4]) : nil
            return ProcStat(name: name, parentField: parent, terminalField: terminal)
        }
    #endif

    #endif
}
