# SwiftUI's size beside TUIkit's (2026-10-10)

> **Status:** answered, for context; no decision rested on it. **Asked by:** the owner, 2026-10-10. **Working
> notes** (not in git): `SIZE3/q/swiftui/notes.md`, with the hello-world sources and build script beside it.

## Question

The owner, during the size review: "how does SwiftUI compare, in binary size? Make it as apples-to-apples as you can
(SwiftUI is several frameworks)."

## Answer

- **Per app, the comparison is meaningless:** a stripped SwiftUI hello world is 53,048 B, almost all of it 16 KB
  page padding, because SwiftUI lives in the OS's shared cache; a stripped TUIkit hello world was 11,502,960 B (217
  times as large), because TUIkit is linked into each app.
- **Framework for framework, SwiftUI is about 3.75 times TUIkit's size**: 39.0 MB of code and data for SwiftUI,
  SwiftUICore and AttributeGraph, against 10.4 MB for TUIkit's umbrella built as one dynamic library.
- **Per type they are equally dense**: about 4,600 against 4,500 bytes per nominal type (within 3%), and within 9% per
  conformance. SwiftUI is larger because it has about 3.6 times as many types and 4.1 times as many conformances.
- **And SwiftUI leans on the rest of the OS**, uncounted here: AppKit's controls (it imports 162 `NS*` classes),
  Core Animation, Core Text, ImageIO and more. TUIkit builds its own renderer, terminal I/O, image conversion and SF
  Symbols table into the app.

## Key measurements

macOS 15.8.1 (24H32) arm64 VM with Xcode 26.3 (SDK 26.2): so SwiftUI is the macOS 15 generation's; macOS 26's was not
measured. Every figure is the file bytes of `__TEXT` and `__DATA*`, on both sides: `__LINKEDIT` is merged across
the shared cache, so no per-image figure exists for it. SwiftUI's images were sized with `dyld_info -segments`, and
which images are SwiftUI's own was read from the reverse-dependency graph of all 3,255 readable cache images.
TUIkit's figures are SIZE3's 6.4.0 build at main 247de05f9.

| | SwiftUI-specific | TUIkit (umbrella dylib, 6.4.0) | ratio |
|---|--:|--:|--:|
| code and data | 39,013,347 | 10,410,692 | 3.75× |
| code | 32,707,284 | 8,337,624 | 3.92× |
| Swift runtime metadata | 1,929,044 | 606,615 | 3.18× |
| nominal types | 8,420 | 2,320 | 3.63× |
| conformances | 15,406 | 3,739 | 4.12× |
| bytes per type (estimate) | 4,633 | 4,487 | 1.03× |

The SwiftUI hello world (`WindowGroup` with `Text("Hello")`, `swiftc -O`, macOS 14.0 target, Xcode's 6.2.4) is
53,048 B stripped, of which 1,798 B are sections; an AppKit one is 51,352 B.

## What makes it unequal

- **Build settings:** SwiftUI is built with library evolution for arm64e (the SDK's interfaces say so; inferred for
  the binaries measured), TUIkit without it for arm64. Pointer authentication adds instructions; library evolution
  adds resilience code but moves inlinable code into clients. The net effect is unknown, and TUIkit cannot be
  measured with library evolution because the compiler crashes on TUIkitCore.
- **Where the line falls:** TUIkitFoundation holds `Button`, `ScrollView`, `Label` and others that SwiftUI keeps in
  `SwiftUI` rather than `SwiftUICore`, so a per-group comparison (engine against engine: 1.96×; controls against
  controls: 6.81×) is skewed.
- **Cost model:** SwiftUI's 39–40 MB is paid once by the OS and shared by every process; a TUIkit app pays its share
  of TUIkit on disk per app. That is why
  [shrinking what each app links](<Where the bytes of a TUIkit app go (2026-10-10).md>) matters for TUIkit.

No other Swift terminal-UI framework was available locally to compare, and nothing was downloaded.
