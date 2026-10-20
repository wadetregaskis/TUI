# Completing the SwiftUI API: lane BNDL's decisions for review

*A companion to [`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>),
written by the lane that made a TUIkit program run without its resource bundle
(2026-10-10): the binary-size follow-ups found that every TUIkit app stopped at
launch (`Fatal error: unable to find bundle named TUIkit_TUIkitStrings`) when
`TUIkit_TUIkitStrings.bundle` was not beside the binary. It holds only what
that work raised that was not already decided: the same three parts as the
main file.*

- **A. Needs your decision.** Nothing has shipped for these.
- **B. Shipped the safe option.** A basic, honest form is in; each entry says
  what the fuller version would be, and what it would cost.
- **C. Declined without asking.** Listed so they can be vetoed.

## B. Shipped the safe option

### B-BNDL-1. TUIkit's English is compiled in as well as bundled

*`LocalizationService`, `LocalizationService+BuiltInEnglish.swift`*

**Shipped:** a copy of `en.json`, as the file's text in a raw string literal,
parsed by the same parser the bundled files go through, and only where `en.json`
cannot be read. Without it a program shipped without the bundle would not run
"in English": TUIkit's words would read as their keys (`statusbar.quit`), the
quiet failure the first WebAssembly build showed. `BuiltInEnglishTests` fails,
naming the keys, until the copy matches the file, and the localization article's
"Adding New Keys" says to paste it.

**Price, measured** (`swiftc -O -c`, Xcode's 6.2.4, 2026-10-10): the string is
5,462 bytes of `__cstring`. A `[String: String]` literal of the same 144 pairs
measured 8,125 bytes (4,640 of 32-byte entries in `__DATA,__const`, 3,409 of
its longer strings), so the text is the smaller form as well as the one that
can be pasted. A program with the bundle carries the 5.5 KB unused.

**Fuller version:** one English. The compiled-in table becomes the only English
and `en.json` leaves the bundle (5.5 KB less in it), or a generator writes the
Swift file from `en.json` so there is nothing to paste. Either changes how a
translator adds a key, so it is yours to choose.

### B-BNDL-2. The version of a program without the bundle reads `unknown`

*`tuiKitVersion`*

**Shipped:** `"unknown"`, the value it already had for a `VERSION` file that
could not be read, and the one `VersionResourceTests` and the versioned-consumer
gate test against.

**Fuller version:** compile the version in, as the English is. The price is a
second place to change at every release (or a generator), for a string a
program without the bundle shows only where it prints the version.

### B-BNDL-3. TUIkit looks for its bundle itself, and never at the build directory

*`ModuleResources` (was `moduleResourceURL`, a function of `Bundle.module`)*

**What was measured** (the generated `resource_bundle_accessor.swift` of a
one-target probe package, 2026-10-10, under each toolchain this repository
builds with; and `Bundle.main` / `Bundle(for:)` printed from a tool, a symbolic
link to it, a copy of it, and both kinds of test run):

| Build | Where `Bundle.module` looks | Without the bundle |
|---|---|---|
| SwiftPM native (Xcode's 6.2.4; swiftly 6.4.0 with `--build-system native`; 6.3.3 static Linux SDK) | `Bundle.main.bundleURL` + `<name>.bundle` (`.resources` off Apple platforms), then the build directory's absolute path, compiled in | `Swift.fatalError("could not load resource bundle: …")` |
| Swift Build (6.4.0's default; 6.2.4 with `--build-system swiftbuild`) | `PACKAGE_RESOURCE_BUNDLE_PATH` (debug builds), `Bundle.main.resourceURL`, `Bundle(for:).resourceURL`, `Bundle.main.bundleURL` | `fatalError("unable to find bundle named …")` — the one the binary-size lane hit |
| SwiftPM native, WebAssembly (6.3.3) | two absolute paths, both compiled in: the host toolchain's `usr/bin` (a generator quirk) and the build directory | as native |

Under `swift test` the program is the toolchain's runner, so `Bundle.main` is
the runner's: the native build finds the bundle by its compiled-in path, which
is the directory holding the `.xctest`; Swift Build copies the bundle into the
`.xctest`'s `Contents/Resources`. Started through a symbolic link, a tool's
`Bundle.main.bundleURL` is the LINK's directory, and `Bundle(for:)` the real
one.

**Shipped:** no call to `Bundle.module` (but on WebAssembly, B-BNDL-4). A
check before calling it cannot be made safe: the two accessors look in
different places, and one at a path nothing else can read, so nothing checked
here proves the one compiled in will find the bundle. TUIkit looks in Swift
Build's three places (not the environment variable, which is Xcode's), and in
the directory holding the bundle its code was loaded from when that is not the
main bundle, which is the native build's compiled-in path in the one layout
that needs it (a test bundle). It answers none where none of those holds the
bundle.

**What changes where the bundle exists:**

- A program **copied out of its build directory** no longer reads the bundle
  left there. Under the native build it did, on the machine that built it and
  on no other, which is how a copied binary passes on its author's machine and
  stops on every user's; under Swift Build it stopped everywhere. It now reads
  English, everywhere, and `tuiKitVersion` reads `unknown`.
- A program **started through a symbolic link** to a directory holding it and
  its bundle (how a Homebrew formula installs into `bin`) used to stop under the
  native build, unless its build directory still existed. It now reads the
  bundle (measured: `Tools/Smoke/bundleless_smoke.py`, against a build from
  before this lane with its build directory's bundle moved aside: the linked
  run stopped by signal 5).

**Fuller version:** none found that keeps reading the compiled-in path: it is
readable only through the accessor that stops the program.

**Unmeasured:** Swift Build's accessor and bundle placement on Linux (6.4's
default there too). A layout this does not cover shows as English and
`tuiKitVersion == "unknown"`, which `VersionResourceTests` fails on; CI's 6.4
Linux lane is the check.
Still unmeasured on 2026-10-19: this machine has no container runtime, and
nothing has been pushed since 2026-10-01, so that lane has not run it. What
was checked that day: `Tools/verify-versioned-consumer.sh` passes (a package
depending on TUIkit 1.0.0 by version reads `tuiKitVersion` 0.6.0 and German's
`button.cancel`), and `ModuleResourcesTests` now fails if any library module
reads `Bundle.module` again outside `ModuleResources`' WebAssembly arm — the
revert that would bring the stop back.

### B-BNDL-4. On WebAssembly, a page that serves no bundle still stops the program

*`ModuleResources.current`*

**Shipped:** on WASI the lookup is still `Bundle.module`. SwiftPM compiles both
places it looks into the program as absolute paths there (B-BNDL-3's table), and
`Tools/Web/build.sh` serves the bundle at the build directory's, so there is
nothing to look for at run time, and the web demo reads its translations as
before.

**Fuller version:** the page serves the bundle beside the program's `argv[0]`
as well, and WASI searches as everywhere else. The price is a change to the web
build and a check in a browser, which this lane could not make.
