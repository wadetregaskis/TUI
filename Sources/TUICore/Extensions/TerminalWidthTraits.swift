//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalWidthTraits.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Terminal Width Traits

/// How many cells the host terminal gives a composed emoji cluster — the
/// **claim**, as opposed to the cursor advance the per-host models describe.
///
/// ## Why the claim is not host-independent any more
///
/// It used to be, on the reasoning that a claim must cover the widest painter
/// so that content is never overwritten, with the narrower painters taking a
/// blank cell instead of a shear. That works when the spread is one cell — an
/// SF Symbol painted 2 by Apple Terminal and 1 by Ghostty — and it breaks down
/// completely when the spread is nine, which is what a four-person family
/// costs on a terminal that does not compose ZWJ sequences.
///
/// The alternative TUI used was **substitution**: strip the Fitzpatrick
/// modifier, or drop a sequence to its first component, so the cluster fits the
/// two cells claimed for it. That keeps every row aligned and changes what the
/// user said. 👍🏽 becomes 👍, which is a loss; 🏳️‍🌈 becomes 🏳️, which is a
/// white flag, and that is not a rendering compromise but a different message.
///
/// So the claim follows the host instead, and the layout accommodates whatever
/// the cluster really occupies. A ZWJ sequence that Warp draws across eleven
/// cells is *allocated* eleven cells: the enclosing border lands where it
/// should, text wraps around the true width, and every scalar the user wrote
/// still reaches the screen.
///
/// ## What this does not cover
///
/// The two classes where TUI was **substituting** — the ones that can
/// change a message — plus, since 2026-09-04, ``ChromeOverhang``. Classes that
/// merely shear (Warp's keycaps and 〰️ at 3 cells against a claim of 2, its
/// tag-sequence flags at 3) are unchanged and still documented as limitations:
/// they misalign, which is a visual defect, not a semantic one. Each would
/// need its own measured rule.
///
/// Chrome overhang is the first class to get one. It is here rather than in a
/// table of its own for three reasons that are all this type's doing: it is a
/// CLAIM, so it must move with the rest of the claim; ``generation`` is what
/// tells the measurement caches a claim has changed, and a second host-keyed
/// global would either bump this counter or serve measurements taken under
/// another host's claim; and ``withTraits(_:operation:)`` is the scoped pin
/// its tests need, which a second global would have to reimplement task-local
/// and all. The codepoints themselves stay in `ChromeOverhang.swift` — this
/// type selects among measured sets, it does not enumerate them.
///
/// Text clusters are the second (``textClusters``, 2026-10-19): a Devanagari
/// conjunct is one cluster that three of the four hosts advance per code
/// point, so the claim follows each host's measured advance there too. That
/// is a shear, not a substitution — the kind of defect the paragraph above
/// leaves documented — but a shear of up to two cells per cluster, repeated
/// for every conjunct on a line of Hindi, and only the claim can remove it.
///
/// ## Reading and setting
///
/// Detected once at startup from the identified host and read from the render
/// path, exactly as ``ColorDepth`` is. Use
/// ``withTraits(_:operation:)`` for a scoped pin — a test, or a diagnostic
/// rendering as another client — because a plain global mutate-and-restore
/// bleeds across Swift Testing's parallel runner.
public struct TerminalWidthTraits: Sendable, Equatable {

    /// How much room a Fitzpatrick cluster (👍🏽 ✊🏻 ☝🏽) occupies.
    public enum SkinTone: String, Sendable, Equatable, CaseIterable {
        /// The base and the modifier merge into one glyph occupying the base's
        /// own width. Ghostty, and every host for an SMP base under
        /// ``detachedOnBMPBases``.
        case merged
        /// The base is drawn, then the modifier as a separate colour swatch
        /// beside it, so the cluster owns the base's width **plus two**.
        /// Warp, for every base.
        case detached
        /// Merged for an SMP base (👍🏽), detached for a BMP one (✊🏻 ☝🏽).
        /// iTerm2. (tmux was ONCE believed to fit here too; its split turned
        /// out to be per base codepoint, not per plane — see
        /// `Character.tmuxMergedToneBases` — so tmux keeps
        /// ``merged``-shaped traits and strips the detaching bases instead.)
        case detachedOnBMPBases
        /// The output walk rewrites every Fitzpatrick cluster as base + ZWNJ +
        /// modifier, and on the one host measured to need it the ZWNJ costs a
        /// column, so the cluster claims the base's promoted width **plus
        /// three**. Where the extra column LANDS differs by base: after an
        /// emoji-presentation base the ZWNJ paints its own blank column
        /// mid-pair (base, gap, swatch); after a VS-16-promoted one the pair
        /// renders adjacent and the spare column trails the swatch.
        ///
        /// An emoji-presentation base (🤙🏽 ✊🏿 👍🏽) is emitted as written. A
        /// text-presentation base (☝🏻 ✍🏿 ⛹🏾) is **promoted with VS-16**
        /// first — the bare rewrite was measured to misalign, and the shipped
        /// pull-back re-rendered it as the bare narrow monochrome glyph with a
        /// blank cell beside it (user-reported 2026-08-28). The promoted
        /// cluster is a VS-16 under-advancer on this host, so the whole
        /// rewritten cluster takes the standalone VS-16 class's erase-and-
        /// push: `ECH(5)` ☝️‌🏻 `CUF(1)` — the erase covering all five claimed
        /// cells (2 + 1 + 2), the push closing the one-column shortfall —
        /// card-measured aligned with the tone kept. Apple Terminal.
        case separated
    }

    /// What the host does with an emoji ZWJ sequence (👩‍🚀 👨‍👩‍👧‍👦).
    public enum ZWJSequences: String, Sendable, Equatable, CaseIterable {
        /// Composed into one glyph at the natural claim. Ghostty, iTerm2,
        /// Apple Terminal's *paint* (but not its column accounting — see
        /// ``decomposedDroppingJoiners``), and the assumption for any
        /// unmeasured host.
        case composed
        /// Each segment drawn separately, with the joiner itself taking a
        /// column: the claim is the sum of the segments **plus one per
        /// joiner**. Measured on Warp, where this predicts every RAW cluster
        /// exactly — 👩‍🚀 = 2+1+2 = 5, 👨‍👩‍👧‍👦 = 11, 👩🏽‍🚀 = 4+1+2 = 7 (the
        /// skin-toned segment resolving through ``skinTone``, which is why the
        /// two rules compose instead of duplicating each other). Warp's
        /// SHIPPED walk drops the joiners instead since 2026-08-28 (the kept
        /// joiner's column was just a gap between the components); this case
        /// remains the raw-cluster truth and the explorer's option.
        case decomposedKeepingJoiners
        /// The output walk REMOVES the joiners and emits the segments as
        /// independent clusters, so the claim is the sum of the segments and
        /// nothing else: 👨‍👩‍👧‍👦 = 8, ❤️‍🔥 = 4, 👩🏽‍🚀 = 5+2 = 7 (the
        /// toned segment resolving through ``skinTone``). Apple Terminal —
        /// its column accounting decomposes every ZWJ sequence whatever we do,
        /// and every cursor-move repair that let the composed glyph stand was
        /// measured to leave later absolute positioning on the row displaced,
        /// so the walk decomposes in software instead. Also Warp since
        /// 2026-08-28: it draws components either way, and dropping the
        /// joiners removes the blank column each one cost.
        case decomposedDroppingJoiners
    }

    /// How the host advances a grapheme cluster of TEXT — one that is not an
    /// emoji sequence — carrying more than one scalar that adds width: a
    /// Devanagari conjunct (स्त्र), a spacing vowel sign (कि), Thai sara am
    /// (กำ), conjoining Hangul jamo.
    ///
    /// Swift segments these as one `Character` (Unicode 15.1's GB9c fuses a
    /// conjunct however many consonants it stacks), and the cluster rule
    /// answers a flat 2 for any of them. Measured (DSR, 2026-10-19, both
    /// screens), only a host that clusters graphemes advances that: Ghostty
    /// 1.3.1 with DEC mode 2027 set — which TUI sets on Ghostty — moves
    /// स्त्र, ष्ट्र and स्त्री 2 cells. Apple Terminal 455.1, iTerm2 3.7.6 and
    /// Warp v0.2026.09.30 move them 3, 3 and 4: each consonant and spacing
    /// mark its own cell, the virama none. A claim of 2 there puts every cell
    /// after the cluster one or two columns left of where the host draws it,
    /// so the row shears and a truncation clips late.
    ///
    /// Only the ADVANCE is measured. Where the glyph is painted inside the
    /// cells it advances (`landing_probe.py`) is not, on any host, so the
    /// claim decides layout from the advance alone — see
    /// `Documentation/Terminals/Terminal compatibility survey.md`, "Complex
    /// scripts".
    public enum TextClusters: String, Sendable, Equatable, CaseIterable {
        /// One advance per cluster, the cluster rule's: स्त्र is 2. Ghostty
        /// with mode 2027 set, and the assumption for any unmeasured host.
        case clustered
        /// Each code point advances its own width, so the cluster claims its
        /// scalars' sum (`Unicode.Scalar.loneTerminalWidth`): स्त्र is
        /// 1 + 0 + 1 + 0 + 1 = 3, स्त्री 4. The conjoining vowel and trailing
        /// jamo of a Hangul syllable spelled as jamo add nothing — `wcwidth`'s
        /// zero, and what every current host advances (한 as U+1112 U+1161
        /// U+11AB is 2) — although a LONE one is still priced a cell, which
        /// no host has been asked about. Apple Terminal, iTerm2, Warp.
        case perCodePoint
    }

    /// What this host does with a ZWJ sequence.
    public var zwjSequences: ZWJSequences

    /// How this host lays out a skin-tone cluster.
    public var skinTone: SkinTone

    /// Which of the framework's own chrome glyphs this host paints across two
    /// cells while advancing one — see ``ChromeOverhang``, whose measured sets
    /// are DISJOINT between two of the four hosts, which is why this is a
    /// trait and not one table.
    public var chromeOverhang: ChromeOverhang

    /// How this host advances a multi-scalar cluster of text.
    public var textClusters: TextClusters

    public init(
        zwjSequences: ZWJSequences = .composed,
        skinTone: SkinTone = .merged,
        chromeOverhang: ChromeOverhang = .contained,
        textClusters: TextClusters = .clustered
    ) {
        self.zwjSequences = zwjSequences
        self.skinTone = skinTone
        self.chromeOverhang = chromeOverhang
        self.textClusters = textClusters
    }

    /// A host that composes everything into the two cells the layout would
    /// naturally claim, advances a cluster of text as one, and whose chrome
    /// stays inside its cells — the correct answer for a terminal TUI has
    /// not measured, and the behaviour every terminal got before this
    /// existed.
    public static let composing = Self()
}

// MARK: - The process-wide value

extension TerminalWidthTraits {

    /// The process-wide traits, before any task-local pin.
    ///
    /// `nonisolated(unsafe)` is intentional and matches
    /// ``ColorDepth``: the value is set once at startup, from a
    /// host identification that cannot change for the life of the process, and
    /// is then read from the render path with no further writes.
    nonisolated(unsafe) private static var processCurrent: Self = .composing

    /// A task-scoped pin, bound by ``withTraits(_:operation:)``.
    ///
    /// Task-local rather than a plain global for the reason `ColorDepth` gives:
    /// Swift Testing runs suites in parallel, and a global mutate-and-restore
    /// would bleed one test's pinned host into another's rendering.
    @TaskLocal private static var taskCurrent: Self?

    /// Bumped every time the process-wide traits change.
    ///
    /// Measurements are memoized by content, and the claim is part of what a
    /// measurement means — so a cache populated under one host's traits is
    /// wrong under another's. Rather than reach for a shared cache the
    /// architecture deliberately does not have, the caches compare this counter
    /// and drop themselves when it moves — `RenderCache` once per render pass,
    /// `TextWrapping`'s wrap and fit memos on every lookup, since nothing gives
    /// those a pass boundary.
    ///
    /// Only the process value bumps it. A task-local pin is scoped to work that
    /// opts into it, and the render path is not that work.
    nonisolated(unsafe) public private(set) static var generation: Int = 0

    /// The traits in force. Assign to override process-wide — expected before
    /// rendering starts — or use ``withTraits(_:operation:)`` for a scoped pin.
    public static var current: Self {
        get { taskCurrent ?? processCurrent }
        set {
            guard newValue != processCurrent else { return }
            processCurrent = newValue
            generation &+= 1
        }
    }

    /// Runs `operation` with `traits` in force on this task only.
    public static func withTraits<R>(
        _ traits: Self, operation: () throws -> R
    ) rethrows -> R {
        try $taskCurrent.withValue(traits, operation: operation)
    }
}
