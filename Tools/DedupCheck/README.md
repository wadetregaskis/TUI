# DedupCheck

Keeps TUIkit correct in an app linked with `-Xlinker -deduplicate`, which the README offers app developers as a
size option (README, "Shipping size"). With it, ld merges byte-identical functions, across the whole app, onto one
address. Swift code can observe a function's address in two ways, and either can change its answer:

- **Key paths.** A key path to a computed property is identified by its getter's address. Two key paths with one
  root and one value type whose getters compile alike, such as `var a: Int { x }` and `var b: Int { x }`, then
  compare and hash equal. (A key path to a stored property is an offset, and does not change.)
- **Function pointers.** Code that compares a closure or a C function pointer by its bits.

`dedup_check.py` reads the deduplicated binary (unstripped), the build's object files and `manifest.json` (the
reviewed facts), and fails on anything the manifest does not account for:

| part | what it reads | fails when |
|---|---|---|
| **K1** key paths TUIkit forms | every key-path pattern (`l_keypath*`) in TUIkit's objects, whose relocations name the getter that identifies each computed component; the binary's symbol table gives each getter's address | two of them share an address, a root and a value type, both are writable, and their setters differ (DIVERGENT: equal key paths that write different things), unless `key_path_aliases` lists the pair with a reason. Read-only and same-setter aliases are listed, not failed: they read the same thing |
| **K2** consumers | every function in TUIkit's objects that references the standard library's key-path `==`, `hashValue`, `hash(into:)` or its Equatable/Hashable conformances, or Foundation's `KeyPathComparator`/`SortDescriptor` ones | one is not in `key_path_consumers`. This catches what no source search sees: a synthesized `==` on a struct holding a key path, a `Dictionary` or `Set` specialisation |
| **F1** address-taken C functions | relocations that take the address of a Swift `@convention(c)` entry point | one is not in `c_function_addresses` |
| **F2** compared addresses | the symbols `address_identity` names | one shares its address with another function |
| **K3** (report only) | every getter in the binary that shares its address with another of one root and value type, stored properties left out | never: it lists the key paths an app *could* form that would compare equal |

TUIkit's objects are those of the modules `manifest.json`'s `modules` names; every other module is the app's,
reported and never failed. It reads arm64 Mach-O only (a universal binary: `lipo -thin arm64` first) and exits 2,
never 0, when it cannot check: no objects, none of TUIkit's, no key path in them, a stripped binary.

Not covered: key paths or functions that reach `==` through a dynamic cast (`x as? any Hashable`) or generic code
that never names them; an `unsafeBitCast` of a Swift closure; and K1 for a module the checked binary does not link
(Stress links every library module but TUIkitAppKit and TUIkitMacros).

## Running it

From the package root, after a release build:

```sh
swift build -c release --product Stress --disable-dead-strip -Xlinker -deduplicate
python3 Tools/DedupCheck/dedup_check.py --binary "$(swift build -c release --show-bin-path)/Stress" --objects .build
python3 -m unittest discover -s Tools/DedupCheck -p 'test_*.py'     # the tool's own tests: no build, under 1 s
```

- **`--disable-dead-strip`** keeps every key path TUIkit's objects form in the binary. TUIkit's default trait
  `DeadStripUnusedAPI` lets a link drop the TUIkit code an app does not reach, and a dead-stripped Stress kept 227
  (Swift 6.2.4) or 288 (6.4.0) of the 315 key-path getters; linked whole, 313 (measured 2026-10-11). Folding pairs
  identical functions, so the whole link shows every pair a smaller one could.
- **`--objects .build`** works with either build system: the check reads no debug build (its unspecialised code
  compares key paths in functions a release build does not have) and no host tool (swift-syntax, the macro
  plugin). Swift Build (6.4's default) keeps each module's per-file objects under
  `.build/out/Intermediates.noindex/…/<Module>-t.build/`, and a merged `<Module>.o` beside the products that lacks
  key-path patterns the per-file ones hold (207 of 315, measured); given only merged objects, the check refuses.
- `--plain <the same app linked without the flag>` marks which aliases ld made; `--json FILE` writes everything.

## For an app developer

`--report` fails on nothing and lists what `-deduplicate` did to your app: the equal key-path groups (K1, each
member labelled with the module that forms it), the functions in your code that compare or hash key paths (K2,
labelled `app`), and the computed properties anyone could form equal key paths to (K3). It needs the unstripped
binary and the release build's objects, so run it before `strip`:

```sh
swift build -c release -Xlinker -deduplicate
python3 <TUIkit checkout>/Tools/DedupCheck/dedup_check.py --report \
    --binary "$(swift build -c release --show-bin-path)/MyApp" --objects .build
```

## Changing the manifest

An entry is a review. For a new consumer (K2): say where its key paths come from, and why two that a fold made equal
cannot change its answer. For a DIVERGENT pair (K1): say which consumers its key paths reach and why none of them can
confuse the two. Folding differs by toolchain (Xcode's 6.2.4 folds `buttonStyle` with `installedButtonAppearance`;
6.4.0 does not), so a pair allowed for one toolchain stays listed while that toolchain is supported.
