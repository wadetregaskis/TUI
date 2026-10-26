# GNU ld RWX LOAD segment warning on Linux aarch64

> **Status:** documented: root cause identified; build workaround via `-Xlinker -z -Xlinker separate-code`.
> Investigated 2026-10-23; nothing in TUI changes, so moved here from `Investigations/` on 2026-10-26. **Asked by:** the user, 2026-10-23.

## Question

Why does GNU ld emit:
```
/usr/bin/ld: warning: ... has a LOAD segment with RWX permissions
```
when building or running Swift executables (such as `swift run Example`) on Linux aarch64 with Swift 6.2.4 (and newer toolchains), and how can it be resolved?

## Answer

- **GNU ld 2.39+ warns on RWX ELF segments by default.** Starting with GNU binutils 2.39, `--warn-rwx-segments` is enabled by default to alert developers to binaries with memory segments carrying both write and execute permissions (`RWE`), which violate the Write XOR Execute (W^X) security principle.
- **GNU ld on aarch64 defaults to `-z noseparate-code`.** Unlike x86_64 Linux where GNU ld defaults to `-z separate-code` (placing executable code and data on separate memory pages), aarch64 targets default to `-z noseparate-code` to minimise ELF padding overhead when targeting 64 KiB memory pages (`0x10000`).
- **Swift metadata descriptors in `.rodata` carry `SHF_WRITE`.** The Swift compiler emits type metadata records, reflection descriptors, and protocol conformance records into sections that GNU ld groups together with read-only and executable sections. Because these descriptors carry relocations and `SHF_WRITE` flags, and because code (`.text`, `AX`) and data share a 64 KiB page boundary, GNU ld coalesces them into a single monolithic `LOAD` segment with `RWE` permissions.
- **Passing `-Xlinker -z -Xlinker separate-code` resolves the warning cleanly.** Instructing the linker to separate code from data ensures that code sections are placed into an `R E` segment, while read-only data and writable data are placed into `R` and `RW` segments.
- **Why it is not set in `Package.swift`:** `Tools/validate-package-manifest.sh` strictly forbids unconditional `unsafeFlags` in `Package.swift` to ensure that TUI remains consumable as a package dependency across all platforms and toolchains without triggering SPM's refusal of unsafe flags in package dependencies. Thus, developers and CI runners building on Linux aarch64 can pass `-Xlinker -z -Xlinker separate-code` at the command line if they wish to suppress the warning.

## Key measurements

Tested on Debian GNU/Linux 13 (trixie) aarch64 (Linux 6.12 kernel, GNU ld / binutils 2.44) with Swift 6.2.4, Swift 6.3.3, and Swift 6.4.1.

### Segment inspection with `readelf -l`

Without `-z separate-code` (default build):
```
Program Headers:
  Type           Offset             VirtAddr           PhysAddr
                 FileSiz            MemSiz              Flags  Align
  LOAD           0x0000000000000000 0x0000000000000000 0x0000000000000000
                 0x0000000003747ee8 0x00000000037de3d0  RWE    0x10000
```
A single monolithic `LOAD` segment of size ~58 MB with `RWE` permissions spanning code and data. GNU ld emits:
`/usr/bin/ld: warning: ... has a LOAD segment with RWX permissions`.

With `-Xlinker -z -Xlinker separate-code`:
```
Program Headers:
  Type           Offset             VirtAddr           PhysAddr
                 FileSiz            MemSiz              Flags  Align
  LOAD           0x0000000000000000 0x0000000000000000 0x0000000000000000
                 0x00000000001a6898 0x00000000001a6898  R      0x10000
  LOAD           0x00000000001b0000 0x00000000001b0000 0x00000000001b0000
                 0x0000000001aa6140 0x0000000001aa6140  R E    0x10000
  LOAD           0x0000000001c60000 0x0000000001c60000 0x0000000001c60000
                 0x0000000001b07ee8 0x0000000001b9e3d0  RW     0x10000
```
Three clearly partitioned segments: `R`, `R E`, and `RW`. The linker warning is completely eliminated.

## Reasoning

1. **Safety vs. Memory Footprint:** On architectures using 64 KiB memory pages (common on aarch64 enterprise distributions), separating code and data segments incurs up to 64 KiB of file alignment padding per segment boundary. GNU ld opted for binary compactness by default (`-z noseparate-code`), whereas security-hardened linkers (such as LLVM `lld` or GNU ld on x86_64) default to separate code.
2. **The Swift Compiler and ELF metadata:** The Swift runtime needs type and protocol descriptor tables to be relocatable at load time. When dynamic or static relocations are applied to section metadata in debug or non-LTO builds, GNU ld treats the combined section as writable. If that section falls in the same page window as executable `.text`, GNU ld must mark the resulting `LOAD` segment as executable and writable, triggering `--warn-rwx-segments`.
3. **SPM Manifest Constraint:** Swift Package Manager prevents consumers from using a package whose manifest specifies `unsafeFlags` in its products without passing `--disable-sandbox` and explicit flags. Preserving zero-flag consumability on macOS and other platforms requires keeping `Package.swift` free of unconditional linker flags.

## Usage

### Option 1: User-level `ld` wrapper (recommended for developer machines)

Place an executable wrapper in `~/.local/bin/ld` (which precedes `/usr/bin` in `$PATH`):

```sh
#!/bin/sh
exec /usr/bin/ld.bfd -z separate-code --no-warn-rwx-segments "$@"
```

Ensure it is executable (`chmod +x ~/.local/bin/ld`). This transparently partitions code and data segments across all `swift run`, `swift build`, `swift test`, and package manifest evaluations without needing extra command-line flags.

### Option 2: Command-line linker flags

When building without the wrapper, pass the linker flags directly:

```sh
swift run -Xlinker -z -Xlinker separate-code Example
```
or
```sh
swift build -Xlinker -z -Xlinker separate-code
```
