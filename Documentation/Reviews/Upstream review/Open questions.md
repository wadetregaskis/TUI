# Open questions

Items from the upstream review that need the owner's decision. Each carries
enough description to decide from without reading the upstream patch.

When one is decided, it moves out of here: the reasoning goes into the relevant
`notes/PR-NN.md`, and the ledger rows change from `queued` to the real verdict.

Empty is the healthy state.

---

## Upstream branches not on `main`

**Reviewed 2026-08-07** — see `notes/Unmerged upstream branches.md`. 21 commits across four
branches; nothing needs a decision. The one item it called worth acting on,
`GeometryReader`, has since landed (`222d5a2dd`, 2026-08-07), as have the other
deferred gaps it names: `AlignmentID` (`fde6d6a0f`, 2026-08-07), the `Layout`
protocol and `AnyLayout` (`74844bd96`, 2026-08-08), and an `AsyncImage` that
fetches over the network (`2719467ca`, 2026-10-03).

Not part of the numbered ledger: an unmerged branch is a proposal, so these are
not counted in the 205 and carry no ledger rows.
