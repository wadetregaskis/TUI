# SF Symbols table generator

Regenerates [`Sources/TUIkitStrings/SFSymbols/SFSymbolTable.generated.swift`](../../Sources/TUIkitStrings/SFSymbols/SFSymbolTable.generated.swift)
— the baked SF Symbol *name → Unicode codepoint* table that backs
[`SFSymbol`](../../Sources/TUIkitStrings/SFSymbols/SFSymbol.swift) and
`Label(_:systemImage:)`.

This is **developer tooling**, not part of the package build. End users never
run it; they consume the committed generated file. It is macOS-only and reads
the mapping from the **SF Symbols app** (mirroring `Tools/Profiling`, which
needs Instruments), or from a file of name/codepoint pairs.

## Run

From the repository root (or any directory: a relative app path or file is
taken from the directory the script runs in):

```sh
Tools/GenerateSFSymbols/generate.sh
```

Pass an explicit app path to override auto-detection (it tries
`SF Symbols Beta.app` then `SF Symbols.app`):

```sh
Tools/GenerateSFSymbols/generate.sh "/Applications/SF Symbols.app"
```

Or read the mapping from a file instead of the app:

```sh
Tools/GenerateSFSymbols/generate.sh --pairs symbols.tsv
```

The file holds one `name<TAB>codepoint` line per symbol, the codepoint in
hexadecimal as the app's own table spells it (`star.fill	1002C3`), in any
order (the generator sorts them). A line of any other shape stops the run.
This is for a machine without the app, and for changing what the generator
emits without changing the mapping: the pairs of the committed table, fed
back in, regenerate the same mapping in the new format, written by the same
emitter as an app run.

The script compiles and runs `GenerateSFSymbols.swift`, which writes the
generated Swift table into `Sources/` and prints a summary (symbol count, file
size, and the mapping's digest — see "Output format"). Commit the regenerated
file.

## How it works

Apple ships the authoritative name → codepoint mapping inside the SF Symbols
app, in an **AES-encrypted** custom OpenType table named `symp` inside
`SFSymbolsFallback.otf`. The app decrypts it at runtime with a private Swift
routine:

```
CoreGlyphsLib.Crypton.decryptObfuscatedFontTable(tableTag: UInt32, from: CTFont) -> Data?
```

Rather than re-implement Apple's cipher, the generator **calls that routine
directly**: it binds the mangled symbol via `@_silgen_name`, `dlopen`s the
app's `CoreGlyphsLib`/`SFSymbolsShared` frameworks, builds a `CTFont` from the
app's own fallback font, and asks it to decrypt the `symp` table. The result is
a CSV whose `Name` and `PUAs` columns give the mapping. The data we bake is
therefore exactly what the app itself uses — deterministic, no guesswork, no
visual glyph matching.

The mapping is plain functional data (a symbol name paired with the Unicode
codepoint that renders it) and carries no creative expression.

## Output format

The generated file bakes three native, compile-time literals — no runtime
parsing, and no `String` in the stored table:

- **`nameBlocks: StaticString`** — every name, sorted ascending, **front-coded
  in blocks of `nameBlockSize` (16)**, each name ended by a newline (the last
  one too). A block's first name, its *head*, is stored in full; every other
  name as one byte saying how many leading bytes it shares with the name before
  it, then the rest of it:

  ```
  0.circle            ← head of block 0, in full
  \u{8}.ar            ← "0.circle" shares 8 bytes: 0.circle.ar
  \u{9}fill           ← "0.circle.ar" shares 9:     0.circle.fill
  ```

  The shared-length byte is always written as a `\u{…}` escape (it is below
  0x80, so one byte in the `StaticString`), which keeps the literal one name to
  a line: a head reads as itself, and a regenerated table diffs name by name.
  A `StaticString` is just static bytes in the binary (never a heap `String`).
- **`blockStarts: [UInt32]`** — blocks + 1 byte offsets: where each block's head
  starts, then the blob's length, so block `b` is
  `nameBlocks[blockStarts[b] ..< blockStarts[b + 1]]`.
- **`packedCodepointOffsets: [UInt64]`** — each name's `codepoint - 0x100000`
  (reconstruct with `0x100000 + offset`), packed four to an element, the first
  in the high 16 bits, so the hex reads in table order; the last element's
  unused lanes are zero. `SFSymbol.codepointOffset(at:)` reads one: a shift,
  once per lookup, outside the binary search.

Beside them, one constant: **`fontProbeScalar`**, the codepoint of `star.fill`,
which `SFSymbol.isFontAvailable` asks CoreText to draw. Being a constant, the
font probe searches no names, so on a Mac without the SF Symbols font nothing
that asks `SFSymbol.canRender(named:)` first reads the table. The generator
stops if `star.fill` ever leaves the table.

`SFSymbol` binary-searches the block heads through `blockStarts` for the last
head at or below the query, then walks that one block (at most 15 names),
comparing raw UTF-8 bytes — which equals Swift `String` ordering because the
names are pure ASCII. The walk rebuilds no name: it keeps how many leading
bytes of the query the current name matches, and a name's shared-length byte
alone says whether it still sorts below the query (shares more), has passed it
(shares fewer), or needs its suffix compared (shares exactly as many). So a
lookup touches no `String` and (for a native-string query) allocates nothing.
`SFSymbol.all` rebuilds each name from the one before it, in one pass. The
file is gated behind `#if canImport(AppKit)`, so non-Apple builds carry none of
it.

The run prints a digest of the mapping (FNV-1a of the `--pairs` lines), which
`SFSymbolTableTests` pins: a regenerated table from a newer SF Symbols release
changes it (pin the new value), a change to the emitted format must not.

### Why this shape

The representation was chosen by benchmarking five candidates (compile time,
lookup ns/op, first-access cost, binary size, correctness) and adversarially
verifying the winner — the full record, methodology, and takeaways for baking any
large static Swift table are in
[Documentation/Baking a large static lookup table in Swift.md](../../Documentation/Baking%20a%20large%20static%20lookup%20table%20in%20Swift.md).
In brief:

- A literal `[(String, Character)]` array — the obvious form — takes **~114 s**
  under `-O` (the optimiser chokes on 8466 tuples); even parallel `[String]` /
  `[UInt16]` arrays are **~15 s**, dominated entirely by the `[String]` literal.
- The `StaticString`-blob form compiles in **~1.6 s**, has the **fastest lookup**
  (~125 ns/op) and **near-zero first-access** cost (~0.7 µs — nothing is lazily
  constructed; the blob and the two integer arrays are pure compile-time
  constants), and the **smallest** binary of the greppable options.
- `InlineArray` (Swift 6.2) for the numeric columns was rejected: it is gated to
  **macOS 26**, so it won't run on the macOS 15 + Linux deployment floor.

The codepoints were a `[UInt16]` of 8466 elements until 2026-10-07. The
optimiser folds an array literal element by element, and a clean release build
spent 314 ms of SIL optimisation on that one (Xcode 26.3's Swift 6.2.4, the
initialiser's pass time, min of 3); packed, the same 8466 offsets are 2117
elements (16,936 bytes, the last element's two unused lanes included) and take
74 ms. The name offsets, `nameStarts` (8467 `UInt32`s), cost the same 0.3 s
and were left as they were (`B-BT1-1` in
`Documentation/SwiftUI-API-completion-decisions-BT1.md`) until front-coding
replaced them with `blockStarts`, 531 elements.

**Front-coded since 2026-10-11.** Until then `nameBlob` held every name in full,
200,347 bytes, with an offset per name. Neighbouring names share long prefixes
(`0.circle`, `0.circle.ar`, `0.circle.fill`, …), so storing each against the
one before it, in blocks of 16 that each start with a name in full, takes the
blob to 87,240 bytes and the offsets to one per block. Measured in the SIZE3
research (session notes `SIZE3/q/sf-table/notes.md`, a 6.4.0 `-O` probe per
scheme, stripped and dead-stripped; lookups INDICATIVE, one VM): the table and
its lookup cost an executable 142,442 bytes less; a lookup took 114 ns over all
names in random order and 56 ns over 20 common names, against 122 and 41 ns
before; blocks of 32 would have saved 4,936 bytes more for 136 and 96 ns, and
64 more again for 204 and 154 ns. In TUIkit's own stripped release `Stress`
(Xcode 26.3's Swift 6.2.4, measured when the change landed) the sections
shrank by 144,076 bytes (`__cstring` −200,352, where the old blob lived;
`__TEXT,__const` +87,264, where the new one lands — it holds NUL bytes, likely
why it is not in `__cstring`, unverified; `__data` −31,744, the offsets;
`__text` +756) and the file by 132,096 (13,161,144 → 13,029,048; segments move
in whole 16-KiB pages). There is still nothing to initialise: the blob and
both arrays are compile-time data read by address, clean memory paged in where
a lookup reads (the whole table is 9 16-KiB pages instead of 18, each array
rounded up to whole pages as SIZE3's page model counts the old 13 + 3 + 2:
names 6, block index 1, codepoints 2). Through `Label`, `Image(systemName:)` and the controls, a lookup happens
only where the SF Symbols font is installed: they ask `canRender`, which asks
the font first, and the font probe itself reads no name (`fontProbeScalar`,
above).

The generator asserts at emit time that every name is printable ASCII without
a backslash or a quote (the byte-order search relies on ASCII, the newline ends
a name, and the names are written into the literal as they are), that the
names strictly ascend (each is stored against the one before it, so every
suffix is non-empty), that no name shares 128 bytes or more with the one before
it (one byte), and that every codepoint fits the `UInt16` PUA window.

## Fragility

This depends on the SF Symbols app's internal table format and the decryptor's
mangled symbol name. If a future SF Symbols release changes either, the
generator will fail loudly (nil decrypt, or missing `Name`/`PUAs` columns) — the
*baked* table keeps working until you regenerate. Re-derive the format/symbol
and update `GenerateSFSymbols.swift`, then re-run.
