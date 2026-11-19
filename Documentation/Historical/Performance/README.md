# Performance: how it came to be

One story per subject: the problem, what was measured and considered, what the owner and the
lanes decided and when, where it stands, and what a future reader should watch for, with the
record of each decision below it in the words of the day. The current tools are described in
[`Sources/Stress/README.md`](<../../../Sources/Stress/README.md>) and
[`Tools/Profiling/README.md`](<../../../Tools/Profiling/README.md>); dated performance passes are in
[Performance](<../../Performance/>).

| Story | What it covers |
|---|---|
| [Framework controls beside a live timeline](<Framework controls beside a live timeline.md>) | Why a `List` and a `Button` beside a running `TimelineView` drew themselves whole at every entry (profiled 2026-11-19: about a fifth of a launcher's frame), the memo at their own identity built for an unfocused control (B-TLCTRL-1), and the options for a focused one. **Open:** A-TLCTRL-1. |
| [A declarative perf-case table](<A declarative perf-case table.md>) | The design (2026-11-14) for stating hundreds of performance cases as rows (composition, container, size, count, script) run by `Stress`, every case counted in the gate against recorded counts and only marked cases timed, five lanes. **Open:** A-PERFCASE-1 to 3. |
