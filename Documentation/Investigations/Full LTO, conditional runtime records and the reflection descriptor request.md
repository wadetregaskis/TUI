# Full LTO, conditional runtime records, and the reflection descriptor request

> **Status:** deferred: TUIkit does not recommend the build mode; a Swift feature request is drafted for the owner
> to file. Investigated 2026-10-10 and 2026-10-11. **Decided by:** the owner, 2026-10-11 (draft the descriptor
> request, succinctly, with its alternatives). **Working notes** (not in git): `SIZE3/q/lto/notes.md`,
> `SIZE3/q/condrec-request.md` (the draft), `CONDREQ/notes.md` (its evidence, reproducer and source citations).

## Question

Every app kept all of TUIkit because public symbols and conformance records are dead-strip roots
([where the bytes go](<../Historical/Investigations/Binary size/Where the bytes of a TUIkit app go (2026-10-10).md>)).
`-internalize-at-link` removes the first kind of root. Can the second go too, so that an app keeps only the types it
uses, and is the build mode that does it ready to recommend? (The SIZE3 review's question 9, and the owner's
follow-up asking for the feature request.)

## Answer

- **The mechanism exists, but only under full LTO.** `-conditional-runtime-records` turns each record's "keep" into
  "keep if its type and protocol are otherwise live", which only LLVM's GlobalDCE can evaluate, and only within one
  LLVM module: so the whole program must be one module (full LTO), with internalize.
- **It shrinks a hello world by 36% on its own**, more than any flag TUIkit can apply, but **the compiler stops it
  short**: closure-capture and builtin reflection descriptors are still always kept, and so are multi-payload-enum
  descriptors in every released Swift 6 (Swift's main branch stopped emitting them on 2026-10-08). They name types
  such as `_TableCore`, which keeps those types' descriptors, whose conformance records keep their code. Made conditional too, a hello world would be
  3.73 MB, −67.6% (emulated).
- **Not recommended today.** The flags are hidden and experimental, and their known problems apply to TUIkit (below).
  For an app that uses few modules, per-module products already do better: a hello world on `TUIkitApp` with the
  internalize trait was 5,964,832 B (2026-10-11), against 7,081,880 B for the full-LTO build of the umbrella (an
  older tree, 2026-10-10).
- **The upstream fix is small and specific:** under `-conditional-runtime-records`, stop putting capture and box
  descriptors in `@llvm.used` (the heap metadata already points at the live ones), and condition builtin descriptors
  on their type, as field descriptors already are. No existing issue or PR asks for it (searched 2026-10-11).

## Key measurements

Swift 6.4.0 (no 6.2.4 LTO build), plain `swiftc -O -wmo`, no `-g`, every TUIkit module and the app compiled with
`-lto=llvm-full -Xfrontend -internalize-at-link -Xfrontend -conditional-runtime-records`, linked with
`-dead_strip -Xlinker -no_exported_symbols`; main 247de05f9, on the development machine (arm64 macOS 15.8.1 VM,
busy). Against the stripped hello world (11,502,960 B) and Stress (13,008,592 B) of the same tree:

| | Hello | Stress | how known |
|---|--:|--:|---|
| full LTO with internalize and conditional records | 7,081,880 (−38.4%) | 9,336,664 (−28.2%) | measured |
| full LTO alone | +235,728 | — | measured |
| the best stack without LTO (strip, `-no_exported_symbols`, internalize, prelink fix, `-deduplicate`) | 8,512,256 (−26.0%) | 9,965,696 (−23.4%) | emulated |
| with the three descriptor kinds dead-strippable | 3.73 MB (−67.6%) | — | emulated at link level |
| link time | 35–36 s (about 2 s without LTO) | — | measured, busy machine |

The emulation patches the objects' dead-strip flags; with all modules it came within 0.05% of the real LTO build. The
reproducer in `CONDREQ/repro` (no TUIkit) shows the effect on Swift 6.2.4, 6.3.3 and 6.4.0: a dead function and its
closure are removed, but the type the closure captured keeps 8 symbols, and an unused enum 15.

## Reasoning

The build mode's problems, each of which applies to TUIkit:

- the flags are hidden; a redesign was proposed upstream and abandoned;
- records stripped before the LTO merge have crashed an app (swiftlang/swift#65021, open);
- SwiftPM's final link passes no `-object_path_lto`, so the dSYM has no debug information for LTO code
  (swift-package-manager#6890);
- on Swift 6.4 with Swift Build, a plain `swift build` fails if the root package has a library product;
- on Linux nothing is stripped (measured);
- `_typeByName` cannot find a type nothing references, and a saved `NavigationPath` can name one;
- the witness-method-elimination flag that usually accompanies it has a miscompile whose fix is unmerged
  (swiftlang/swift#91053), in a shape TUIkit has;
- no run-time A/B has been run.

It is the app's build that would choose the mode, not TUIkit's, so it could only ever be README advice.

## What would reopen it

The descriptor fix upstream, then a run-time A/B. Until both exist TUIkit does not recommend the mode; the decision
is recorded in [Future options](<../Future options.md#full-lto-with-conditional-runtime-records>). The draft request
waits for the owner to file it at swiftlang/swift.
