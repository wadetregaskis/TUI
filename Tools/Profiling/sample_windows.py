#!/usr/bin/env python3
"""
Sample a running TUI app on Windows and print its hot functions, the way
`analyze_timeprofile.py` does for an Instruments trace on macOS. Standard
library only (ctypes), and no elevation: Windows' own samplers (WPR, the
Visual Studio profiler) need kernel tracing, which needs an administrator.

How it samples. Every interval it suspends each of the process's threads in
turn, reads its registers (`GetThreadContext`), unwinds its stack
(`dbghelp`'s `StackWalk64`, from each image's `.pdata`: Swift keeps no
frame-pointer chain on Windows), and resumes it. A thread is counted only when it has spent more than
`--min-cycles` since the last sample (`QueryThreadCycleTime`), so a thread
blocked in a wait adds nothing: the counts are CPU, not wall time. Not any
cycles at all: reading a waiting thread's context runs a little of it, so
every thread sampled once would count as running ever after. Each sample weighs one
round; the header says how long a round took.

How it names them. The addresses are mapped to their modules
(`EnumProcessModulesEx`), and named afterwards by the toolchain's
`llvm-symbolizer` (the DWARF Swift writes into a PE on Windows; Swift's own
DLLs by their exports), then demangled by `swift-demangle`. Both are found
from `--toolchain`, or `PATH`.

Run it with an ARM64 Python to sample an ARM64 process (the Swift toolchain's
own, `%LOCALAPPDATA%\\Programs\\Swift\\Python-<v>\\usr\\bin\\python.exe`): an
emulated x64 Python cannot read an ARM64 thread's context.

Usage:
    sample_windows.py --pid PID [--seconds 10] [--interval-ms 1] [--min-cycles N]
                      [--toolchain DIR] [--top 30] [--within PATTERN] [--stacks N]

`--within PATTERN` keeps only the samples with a frame whose name contains
PATTERN, as the macOS analyzer's does.
"""
import argparse
import bisect
import ctypes
import ctypes.wintypes as wt
import os
import platform
import shutil
import struct
import subprocess
import sys
import time
from collections import Counter, defaultdict

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
psapi = ctypes.WinDLL("psapi", use_last_error=True)
winmm = ctypes.WinDLL("winmm")

PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_READ = 0x0010
THREAD_SUSPEND_RESUME = 0x0002
THREAD_GET_CONTEXT = 0x0008
THREAD_QUERY_INFORMATION = 0x0040
TH32CS_SNAPTHREAD = 0x00000004
LIST_MODULES_ALL = 0x03

ARM64 = platform.machine().upper() == "ARM64"
if ARM64:
    # CONTEXT_ARM64 | CONTROL | INTEGER | FLOATING_POINT (the unwind restores
    # d8-d15); the ARM64 CONTEXT is 0x390 bytes.
    CONTEXT_FLAGS = 0x00400000 | 0x1 | 0x2 | 0x4
    CONTEXT_SIZE = 0x390
    OFFSET_FP, OFFSET_SP, OFFSET_PC = 8 + 29 * 8, 8 + 31 * 8, 8 + 32 * 8  # X0..X28, then Fp, Lr, Sp and Pc
else:
    # CONTEXT_AMD64 | CONTROL | INTEGER | FLOATING_POINT; the x64 CONTEXT is 0x4D0 bytes.
    CONTEXT_FLAGS = 0x00100000 | 0x1 | 0x2 | 0x8
    CONTEXT_SIZE = 0x4D0
    OFFSET_FP, OFFSET_SP, OFFSET_PC = 0xA0, 0x98, 0xF8  # Rbp, Rsp, Rip
CONTEXT_FLAGS_OFFSET = 0 if ARM64 else 0x30


class THREADENTRY32(ctypes.Structure):
    _fields_ = [
        ("dwSize", wt.DWORD), ("cntUsage", wt.DWORD), ("th32ThreadID", wt.DWORD),
        ("th32OwnerProcessID", wt.DWORD), ("tpBasePri", wt.LONG), ("tpDeltaPri", wt.LONG),
        ("dwFlags", wt.DWORD),
    ]


class MODULEINFO(ctypes.Structure):
    _fields_ = [("lpBaseOfDll", ctypes.c_void_p), ("SizeOfImage", wt.DWORD), ("EntryPoint", ctypes.c_void_p)]


kernel32.OpenProcess.restype = wt.HANDLE
kernel32.OpenThread.restype = wt.HANDLE
kernel32.CreateToolhelp32Snapshot.restype = wt.HANDLE
kernel32.SuspendThread.restype = wt.DWORD
kernel32.ResumeThread.restype = wt.DWORD
kernel32.GetThreadContext.argtypes = [wt.HANDLE, ctypes.c_void_p]
kernel32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t,
                                       ctypes.POINTER(ctypes.c_size_t)]
kernel32.QueryThreadCycleTime.argtypes = [wt.HANDLE, ctypes.POINTER(ctypes.c_ulonglong)]
psapi.EnumProcessModulesEx.argtypes = [wt.HANDLE, ctypes.POINTER(wt.HMODULE), wt.DWORD,
                                       ctypes.POINTER(wt.DWORD), wt.DWORD]
psapi.GetModuleInformation.argtypes = [wt.HANDLE, wt.HMODULE, ctypes.POINTER(MODULEINFO), wt.DWORD]
psapi.GetModuleFileNameExW.argtypes = [wt.HANDLE, wt.HMODULE, wt.LPWSTR, wt.DWORD]


def threads_of(pid):
    snapshot = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0)
    entry = THREADENTRY32()
    entry.dwSize = ctypes.sizeof(entry)
    ids = []
    ok = kernel32.Thread32First(snapshot, ctypes.byref(entry))
    while ok:
        if entry.th32OwnerProcessID == pid:
            ids.append(entry.th32ThreadID)
        ok = kernel32.Thread32Next(snapshot, ctypes.byref(entry))
    kernel32.CloseHandle(snapshot)
    return ids


def modules_of(process):
    needed = wt.DWORD()
    handles = (wt.HMODULE * 1024)()
    psapi.EnumProcessModulesEx(process, handles, ctypes.sizeof(handles), ctypes.byref(needed), LIST_MODULES_ALL)
    modules = []
    for handle in handles[: needed.value // ctypes.sizeof(wt.HMODULE)]:
        info = MODULEINFO()
        psapi.GetModuleInformation(process, handle, ctypes.byref(info), ctypes.sizeof(info))
        name = ctypes.create_unicode_buffer(1024)
        psapi.GetModuleFileNameExW(process, handle, name, 1024)
        modules.append((info.lpBaseOfDll, info.lpBaseOfDll + info.SizeOfImage, name.value))
    return sorted(modules)


dbghelp = ctypes.WinDLL("dbghelp", use_last_error=True)
dbghelp.SymInitializeW.argtypes = [wt.HANDLE, wt.LPCWSTR, wt.BOOL]
dbghelp.SymRefreshModuleList.argtypes = [wt.HANDLE]
dbghelp.SymFunctionTableAccess64.restype = ctypes.c_void_p
dbghelp.SymFunctionTableAccess64.argtypes = [wt.HANDLE, ctypes.c_uint64]
dbghelp.SymGetModuleBase64.restype = ctypes.c_uint64
dbghelp.SymGetModuleBase64.argtypes = [wt.HANDLE, ctypes.c_uint64]
FUNCTION_TABLE_ACCESS = ctypes.WINFUNCTYPE(ctypes.c_void_p, wt.HANDLE, ctypes.c_uint64)(
    lambda process, address: dbghelp.SymFunctionTableAccess64(process, address))
MODULE_BASE = ctypes.WINFUNCTYPE(ctypes.c_uint64, wt.HANDLE, ctypes.c_uint64)(
    lambda process, address: dbghelp.SymGetModuleBase64(process, address))
dbghelp.StackWalk64.argtypes = [wt.DWORD, wt.HANDLE, wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p,
                                ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
MACHINE = 0xAA64 if ARM64 else 0x8664
# STACKFRAME64: five ADDRESS64s (Offset, Segment, Mode: 16 bytes each) from
# AddrPC, then fields this never reads, KDHELP64 last; 512 bytes is room.
STACKFRAME_SIZE = 512
ADDRESS_MODE_FLAT = 3
# The modules a thread's role is never named after: Windows' own, the C
# runtime's, and the dispatch pool's, which every pool thread starts in.
SYSTEM_MODULES = {"ntdll.dll", "kernel32.dll", "kernelbase.dll", "ucrtbase.dll", "dispatch.dll",
                  "swift_concurrency.dll", "vcruntime140.dll", "advapi32.dll", "win32u.dll", "user32.dll"}


def stack_of(process, thread, context, frame):
    """The thread's PC and its callers, unwound by dbghelp from each image's
    `.pdata`. A frame-pointer walk is no use here: Swift on Windows keeps no
    frame-pointer chain, so x29 leads straight to the thread's first frame."""
    ctypes.memset(context, 0, CONTEXT_SIZE)
    struct.pack_into("<I", context, CONTEXT_FLAGS_OFFSET, CONTEXT_FLAGS)
    if not kernel32.GetThreadContext(thread, ctypes.addressof(context)):
        return None
    pc = struct.unpack_from("<Q", context, OFFSET_PC)[0]
    fp = struct.unpack_from("<Q", context, OFFSET_FP)[0]
    sp = struct.unpack_from("<Q", context, OFFSET_SP)[0]
    ctypes.memset(frame, 0, STACKFRAME_SIZE)
    for offset, value in ((0, pc), (32, fp), (48, sp)):  # AddrPC, AddrFrame, AddrStack
        struct.pack_into("<QHxxI", frame, offset, value, 0, ADDRESS_MODE_FLAT)
    frames = []
    for _ in range(256):
        if not dbghelp.StackWalk64(MACHINE, process, thread, ctypes.addressof(frame), ctypes.addressof(context),
                                   None, FUNCTION_TABLE_ACCESS, MODULE_BASE, None):
            break
        address = struct.unpack_from("<Q", frame, 0)[0]
        if address == 0:
            break
        # A caller's address is the return address: back it into the call.
        frames.append(address if not frames else address - (4 if ARM64 else 1))
    return frames or [pc]


def sample(pid, seconds, interval_ms, min_cycles):
    process = kernel32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
    if not process:
        sys.exit(f"cannot open process {pid}: error {ctypes.get_last_error()}")
    context = (ctypes.c_char * (CONTEXT_SIZE + 16))()
    # GetThreadContext wants the CONTEXT 16-byte aligned.
    aligned = ctypes.c_char.from_buffer(context, (-ctypes.addressof(context)) % 16)
    aligned_context = (ctypes.c_char * CONTEXT_SIZE).from_address(ctypes.addressof(aligned))
    frame = (ctypes.c_char * STACKFRAME_SIZE)()
    if not dbghelp.SymInitializeW(process, None, True):
        sys.exit(f"SymInitialize failed: error {ctypes.get_last_error()}")
    handles, cycles = {}, {}
    spent_by_thread = Counter()
    stacks = Counter()
    rounds = taken = 0
    winmm.timeBeginPeriod(1)  # this process's timer, not the system's
    began = time.perf_counter()
    deadline = began + seconds
    try:
        while time.perf_counter() < deadline:
            rounds += 1
            if rounds % 200 == 1:
                dbghelp.SymRefreshModuleList(process)
                for tid in threads_of(pid):
                    if tid not in handles:
                        handle = kernel32.OpenThread(
                            THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, False, tid)
                        if handle:
                            handles[tid] = handle
            for tid, thread in list(handles.items()):
                now = ctypes.c_ulonglong()
                if not kernel32.QueryThreadCycleTime(thread, ctypes.byref(now)):
                    kernel32.CloseHandle(thread)
                    del handles[tid]
                    continue
                spent = now.value - cycles[tid] if tid in cycles else 0
                ran = spent > min_cycles
                cycles[tid] = now.value
                spent_by_thread[tid] += spent
                if not ran or kernel32.SuspendThread(thread) == 0xFFFFFFFF:
                    continue
                try:
                    frames = stack_of(process, thread, aligned_context, frame)
                finally:
                    kernel32.ResumeThread(thread)
                if frames:
                    stacks[(tid, tuple(frames))] += 1
                    taken += 1
            time.sleep(interval_ms / 1000)
        elapsed = time.perf_counter() - began
        modules = modules_of(process)
    finally:
        winmm.timeEndPeriod(1)
        dbghelp.SymCleanup(process)
        for thread in handles.values():
            kernel32.CloseHandle(thread)
        kernel32.CloseHandle(process)
    return stacks, modules, rounds, taken, elapsed, spent_by_thread


def image_base(path):
    """The address the PE asks to be loaded at, which llvm-symbolizer counts from."""
    with open(path, "rb") as file:
        header = file.read(4096)
    pe = struct.unpack_from("<I", header, 0x3C)[0]
    optional = pe + 24
    magic = struct.unpack_from("<H", header, optional)[0]
    return struct.unpack_from("<Q", header, optional + 24)[0] if magic == 0x20B else struct.unpack_from(
        "<I", header, optional + 28)[0]


def exports(path):
    """A PE's exported functions as sorted (rva, name) pairs: the names a DLL
    without debug information still has, `ntdll`'s system calls among them."""
    with open(path, "rb") as file:
        data = file.read()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    sections_count = struct.unpack_from("<H", data, pe + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    optional = pe + 24
    pe32_plus = struct.unpack_from("<H", data, optional)[0] == 0x20B
    directory = optional + (112 if pe32_plus else 96)
    export_rva, export_size = struct.unpack_from("<II", data, directory)
    sections = []
    for index in range(sections_count):
        header = optional + optional_size + 40 * index
        virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from("<IIII", data, header + 8)
        sections.append((virtual_address, max(virtual_size, raw_size), raw_offset))

    def offset(rva):
        for virtual_address, size, raw_offset in sections:
            if virtual_address <= rva < virtual_address + size:
                return rva - virtual_address + raw_offset
        raise ValueError(rva)

    if not export_rva:
        return []
    table = offset(export_rva)
    count_functions, count_names, functions, names, ordinals = struct.unpack_from("<IIIII", data, table + 20)
    result = []
    for index in range(count_names):
        name_rva = struct.unpack_from("<I", data, offset(names) + 4 * index)[0]
        ordinal = struct.unpack_from("<H", data, offset(ordinals) + 2 * index)[0]
        function_rva = struct.unpack_from("<I", data, offset(functions) + 4 * ordinal)[0]
        if export_rva <= function_rva < export_rva + export_size:
            continue  # forwarded to another DLL
        end = data.index(b"\x00", offset(name_rva))
        result.append((function_rva, data[offset(name_rva):end].decode("ascii", "replace")))
    return sorted(result)


def tool(name, toolchain):
    if toolchain:
        candidate = os.path.join(toolchain, "usr", "bin", name + ".exe")
        if os.path.exists(candidate):
            return candidate
    found = shutil.which(name)
    if not found:
        sys.exit(f"{name} not found: pass --toolchain, or put it on PATH")
    return found


def symbolize(stacks, modules, toolchain):
    """{address: (module, function)} for every address in `stacks`."""
    def module_of(address):
        for start, end, path in modules:
            if start <= address < end:
                return start, path
        return None, None

    by_module = defaultdict(set)
    for (_, frames), _ in stacks.items():
        for address in frames:
            start, path = module_of(address)
            if path:
                by_module[(start, path)].add(address)
    symbolizer = tool("llvm-symbolizer", toolchain)
    names = {}
    for (start, path), addresses in by_module.items():
        module = os.path.basename(path)
        ordered = sorted(addresses)
        try:
            base = image_base(path)
        except OSError:
            base = start
        query = "\n".join(hex(base + address - start) for address in ordered)
        result = subprocess.run(
            [symbolizer, "--obj=" + path, "--functions=linkage", "--no-inlines", "--no-demangle",
             "--output-style=GNU"], input=query, capture_output=True, text=True)
        lines = result.stdout.splitlines()
        table = None
        # Two lines an address in GNU style: the function, then its file and line.
        for index, address in enumerate(ordered):
            name = lines[2 * index] if 2 * index < len(lines) else "??"
            if name == "??":
                # No debug information: the export at or before it, which is
                # its function where the function is exported, and in a
                # system DLL usually is.
                if table is None:
                    try:
                        table = exports(path)
                    except (OSError, ValueError, struct.error):
                        table = []
                    starts = [entry[0] for entry in table]
                rva = address - start
                position = bisect.bisect_right(starts, rva) - 1
                name = f"{table[position][1]} ({module})" if position >= 0 else f"{module}+{hex(rva)}"
            names[address] = (module, name)
    mangled = sorted({name for _, name in names.values() if name.startswith(("$s", "_$s", "$S"))})
    if mangled:
        demangler = tool("swift-demangle", toolchain)
        result = subprocess.run([demangler, "--simplified"], input="\n".join(mangled), capture_output=True,
                                text=True)
        demangled = dict(zip(mangled, result.stdout.splitlines()))
        names = {address: (module, demangled.get(name, name)) for address, (module, name) in names.items()}
    return names


def report(stacks, names, rounds, taken, elapsed, top, within, full_stacks, spent_by_thread):
    def name_of(address):
        return names.get(address, ("?", hex(address)))

    selected = {key: count for key, count in stacks.items()
                if not within or any(within in name_of(a)[1] for a in key[1])}
    total = sum(selected.values())
    print(f"{rounds} rounds, {taken} samples of a thread that ran, {total} kept"
          f"{f' (within {within!r})' if within else ''}; a round every {1000 * elapsed / max(rounds, 1):.2f} ms")
    if not total:
        return
    self_time, inclusive, by_module, by_thread = Counter(), Counter(), Counter(), Counter()
    for (tid, frames), count in selected.items():
        module, leaf = name_of(frames[0])
        self_time[leaf] += count
        by_module[module] += count
        by_thread[tid] += count
        for name in {name_of(a)[1] for a in frames}:
            inclusive[name] += count

    def table(title, counter):
        print(f"\n{title}")
        for name, count in counter.most_common(top):
            print(f"  {100 * count / total:5.1f}%  {count:6d}  {name[:150]}")

    table("Self (where the CPU was)", self_time)
    table("Inclusive (on the stack)", inclusive)
    table("By module (self)", by_module)
    table("By thread", Counter({f"thread {tid}": count for tid, count in by_thread.items()}))
    # What each thread cost, by its own cycle count: the samples above say how
    # often a thread had run, these how much. Each thread is named by the
    # frame nearest its start that is not the system's or the dispatch pool's.
    cycles_total = sum(spent_by_thread.values())
    if cycles_total:
        print(f"\nCycles by thread: {cycles_total / elapsed / 1e6:.0f} million a second in all")
        roles = defaultdict(Counter)
        for (tid, frames), count in stacks.items():
            for address in reversed(frames):
                module, name = name_of(address)
                if module.lower() not in SYSTEM_MODULES:
                    roles[tid][name] += count
                    break
        for tid, spent in spent_by_thread.most_common(top):
            role = roles[tid].most_common(1)[0][0] if roles[tid] else "?"
            print(f"  {100 * spent / cycles_total:5.1f}%  {spent / elapsed / 1e6:7.1f} M/s  thread {tid}  {role[:110]}")
    if full_stacks:
        whole = Counter()
        for (tid, frames), count in selected.items():
            whole[tuple(name_of(a)[1] for a in frames)] += count
        for stack, count in whole.most_common(full_stacks):
            print(f"\n{100 * count / total:5.1f}%  {count} samples, leaf first:")
            for name in stack:
                print(f"         {name[:150]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--seconds", type=float, default=10)
    parser.add_argument("--interval-ms", type=float, default=1)
    parser.add_argument("--toolchain", help="a Swift toolchain's directory, holding usr\\bin\\llvm-symbolizer.exe")
    parser.add_argument("--top", type=int, default=30)
    parser.add_argument("--within")
    parser.add_argument("--stacks", type=int, default=0, help="print this many of the commonest whole stacks")
    parser.add_argument("--min-cycles", type=int, default=100_000,
                        help="the cycles a thread must spend between samples to count as running")
    args = parser.parse_args()
    if os.name != "nt":
        sys.exit("sample_windows.py samples a Windows process; on macOS, use record.sh")
    stacks, modules, rounds, taken, elapsed, spent_by_thread = sample(args.pid, args.seconds, args.interval_ms, args.min_cycles)
    names = symbolize(stacks, modules, args.toolchain)
    report(stacks, names, rounds, taken, elapsed, args.top, args.within, args.stacks, spent_by_thread)


if __name__ == "__main__":
    main()
