# SF Symbols table generator

Regenerates [`Sources/TUIkit/SFSymbols/SFSymbolTable.generated.swift`](../../Sources/TUIkit/SFSymbols/SFSymbolTable.generated.swift)
— the baked SF Symbol *name → Unicode codepoint* table that backs
[`SFSymbol`](../../Sources/TUIkit/SFSymbols/SFSymbol.swift) and
`Label(_:systemImage:)`.

This is **developer tooling**, not part of the package build. End users never
run it; they consume the committed generated file. It is macOS-only and needs
the **SF Symbols app** installed (mirroring `Tools/Profiling`, which needs
Instruments).

## Run

From the repository root:

```sh
Tools/GenerateSFSymbols/generate.sh
```

Pass an explicit app path to override auto-detection (it tries
`SF Symbols Beta.app` then `SF Symbols.app`):

```sh
Tools/GenerateSFSymbols/generate.sh "/Applications/SF Symbols.app"
```

The script compiles and runs `GenerateSFSymbols.swift`, which writes the
generated Swift table into `Sources/` and prints a one-line summary
(symbol count + blob size). Commit the regenerated file.

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

- **`nameBlob: StaticString`** — every name, sorted ascending, newline-separated
  (no trailing newline). A `StaticString` is just static bytes in the binary
  (never a heap `String`), and it stays greppable line by line.
- **`nameStarts: [UInt32]`** — `n+1` byte offsets. Name `i` is
  `nameBlob[nameStarts[i] ..< nameStarts[i+1] - 1]` (the `-1` drops the
  separating newline; the sentinel `nameStarts[n]` = blob length + 1 makes the
  last name resolve the same way).
- **`packedCodepointOffsets: [UInt64]`** — each name's `codepoint - 0x100000`
  (reconstruct with `0x100000 + offset`), packed four to an element, the first
  in the high 16 bits, so the hex reads in table order; the last element's
  unused lanes are zero. `SFSymbol.codepointOffset(at:)` reads one: a shift,
  once per lookup, outside the binary search.

`SFSymbol` binary-searches `nameBlob` *directly* through `nameStarts`, comparing
raw UTF-8 bytes — which equals Swift `String` ordering because the names are
pure ASCII — so a lookup touches no `String` and (for a native-string query)
allocates nothing. The file is gated behind `#if canImport(AppKit)`, so non-Apple
builds carry none of it.

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
74 ms. `nameStarts` (8467 `UInt32`s) costs the same 0.3 s, and stays as it is:
it is read twice per step of the binary search, where packing would add a shift
and a mask — see `B-BT1-1` in
`Documentation/SwiftUI-API-completion-decisions-BT1.md`.

The generator asserts at emit time that every name is ASCII (the invariant the
byte-order binary search relies on) and that every codepoint fits the `UInt16`
PUA window.

## Fragility

This depends on the SF Symbols app's internal table format and the decryptor's
mangled symbol name. If a future SF Symbols release changes either, the
generator will fail loudly (nil decrypt, or missing `Name`/`PUAs` columns) — the
*baked* table keeps working until you regenerate. Re-derive the format/symbol
and update `GenerateSFSymbols.swift`, then re-run.
