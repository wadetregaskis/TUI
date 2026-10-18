# Optimisations that did not pay

Ideas that were built, measured with `ab_bench.py` against their parent, and
not landed, with why. Read this before trying one of them again: each entry
says what was tried, what the measurement said, and what the cause turned out
to be, which is usually more useful than the verdict.

Each A/B is release Stress, 15 reps or more, on a quiet box, against the
commit named. The profiles are Time Profiler traces read with
`Tools/Profiling/analyze_timeprofile.py`.

## The environment's storage as a shared table plus recent writes (2026-10-18)

**The idea.** `EnvironmentValues` stores its values in one
`[ObjectIdentifier: Any]`. Every environment modifier copies its parent's
environment and writes one value. The parent still holds the dictionary, so
that write copies the whole table to change one entry; a menu frame makes
dozens. The `menus` profile put the storage's writes at about 6% of a frame
(`EnvironmentValues.subscript.setter` plus `Dictionary.subscript.setter`),
with two button-style setters at another 5%. The proposal: keep a table
shared by every environment derived from it, plus the few values written
since (up to 8), folding them into a new table when the list overflows. A
write copies the short list; a read scans it, then makes one table lookup.

**Measured** against a5dd9d2e7:

| Version | menus | controls | scrolleager | churn | kitchensink |
|---|---|---|---|---|---|
| recent writes as one array of `(key, value: Any)` | +14.5% | +52.5% | +83.1% | +28.1% | +6.4% |
| keys and values in two arrays | +2.3% | +8.2% | +12.8% | +3.7% | +2.3% |

Slower everywhere it was distinguishable, in both versions.

**Why.** Reads outnumber writes about fifteen to one (687 against 46 on a
`menu` frame, measured 2026-09-06), and the dictionary's read is one hash and
one probe. In the first version, the scan copied each pair (the `Any`
existential, retained) just to compare its key; `storedValue` was 38% of a
`scrolleager` frame, mostly `tuple_initializeWithCopy` and existential copies.
Splitting the keys into their own array removed that. But even a scan of
eight plain keys and an optional table hop, in front of the same probe, cost
more on the reads than the cheaper writes saved.

**What would have to be true to try again.** A design whose read is still one
lookup. A persistent hash trie was weighed and not built: its read could be
as cheap as the dictionary's (a couple of array indexings by the key's own
hash bits, with no SipHash). But at the 30–50 keys a page's environment
holds, a write still copies a root node of up to 32 slots, retaining each
value, which is not clearly cheaper than copying the dictionary.

The remaining lever is fewer environment writes per row, site by site, as
`installedPrimitiveButtonStyle` already merged two writes into one. On
`menus` the hot write is `.buttonStyle(_:)`, one per button, three quarters of
it during measure passes. The scenario styles each button differently on
purpose, so there was nothing to merge there.

## A prehashed set for the render cache's active identities (2026-10-17)

**The idea.** `RenderCache.removeInactive()` asks a `Set<ViewIdentity>` about
every cache entry each frame, paying SipHash on the identity's structural
hash, which is already a hash. Replaced with a table placed by those hash bits
(`PrehashedTable`, as landed for the retained-subtree index in 73efff290),
confirming a hit with `==`.

**Measured** against 73efff290: dashboard **+9.2%**, kitchensink +2.4% (31
reps), even with the table `@inlinable`.

**Why.** Not the table's own cost, which was about 2%. The loop
`for (key, entry) in sizeEntries where !isLive(entry.identity)` began copying
every whole `SizeEntry` (its `Any` snapshot, `Date?` and lease: "outlined
init with copy of Date?" 5.0% of a frame) once `Set.contains`, which the
optimiser could see through, was replaced. That loop's projection of
`.identity` is fragile in code generation; any change near it needs an A/B.
What did land from the same profile: reading the set into a local once per
prune (b7d700cb9, dashboard −2.5%).

## Walking two identities' node chains without reference counting (2026-10-17)

**The idea.** `IdentityNode.structurallyEqual` walks both chains to the root
when two equal identities come from different passes (they share no node), and
`ViewIdentity ==` was 2.4% of a kitchensink frame. Walking with
`unowned(unsafe)` references would drop the retain and release per step.

**Measured** against b7d700cb9: deep **+12.2%**, modifiers +2.9%, fanout
+2.1%, kitchensink (the target) +0.7%.

**Why.** The retained loop was already well optimised, and
`guard let parent = node.parent` re-materialises a strong reference each step
anyway. The lever is fewer walks (identities that share nodes across passes),
not cheaper steps.
