"""The checks, run on an assignment (node -> module). Each returns Findings; see README.md for what each means and
what to do about one."""
import collections
import os
import re

import indexstore as IX
import swiftsource as SS
from assigner import module_of


class Finding:
    def __init__(self, check, key, message, file=None, line=None):
        self.check, self.key, self.message, self.file, self.line = check, key, message, file, line
        self.scheduled = None           # the `scheduled` rule id that covers it (a refactor that has not landed)
        self.rules = set()              # those entries' indices in rules.json (several entries may share an id)
        self.unscheduled = 0            # public-above: public members of the block that no `scheduled` entry names
        self.accepted = None            # the `accepted` entry's reason
        self.weight = 1                 # the references it stands for (upward: the edge's count)

    @property
    def new(self):
        return not self.accepted and (not self.scheduled or self.unscheduled > 0)


def upward(M, R, asg):
    """A reference from a declaration to one in a module its own module cannot see: a cycle once split."""
    out = []
    for a in M.nodes:
        for b, (k, (f, ln)) in M.edges.get(a, {}).items():
            ma, mb = asg[a], asg[b]
            if R.sees(ma, mb): continue
            x = Finding('upward', f'{M.label(a)} -> {M.label(b)}',
                        f'{ma} -> {mb}: {M.label(a)} uses {M.label(b)} ({k} reference{"s" if k > 1 else ""})', f, ln)
            x.weight = k
            s = next(filter(None, (R.scheduled_for('upward', la, lb) for la, lb in zip(M.rule_labels(a), M.rule_labels(b)))), None)
            if s: x.scheduled = s['id']; x.rules.add(s['index'])
            out.append(x)
    return out


def _owned(R, m):
    return m in R.sees_set


def owns_neither(M, R, asg):
    """A conformance declared in a module that owns neither the type nor the protocol (the debug-runtime crash
    class: Package.swift's `Color: View` note, M3's "failed to demangle witness"). Conformances whose type and
    protocol are both outside the split module are owned by neither today too, and are skipped."""
    out = []
    for ty, pr, decl, f, ln in M.conformances:
        tm, pm = module_of(M, asg, ty), module_of(M, asg, pr)
        if not _owned(R, tm) and not _owned(R, pm): continue
        dm = asg[decl]
        if dm in (tm, pm): continue
        tn, pn = M.symbols.get(ty, ('?',))[0], M.symbols.get(pr, ('?',))[0]
        out.append(Finding('owns-neither', f'{tn}: {pn} @ {M.label(decl)}',
                           f'{tn}: {pn} is declared in {dm} ({M.label(decl)}); the type is in {tm or "the SDK"}, '
                           f'the protocol in {pm or "the SDK"}', f, ln))
    return out


_CONSTRAINED = re.compile(r'^\s*(?:@[\w.]+(?:\([^)]*\))?\s+)*(?:(?:public|package|internal|fileprivate|private)\s+)?'
                          r'extension\s+([\w.]+)\s+where\s+([^{]*)')


def derived_witness_pairs(root):
    """(P, Q) for every `extension P where Self: Q` in the package's sources, any module."""
    pairs = collections.defaultdict(set)
    src = os.path.join(root, 'Sources')
    for d, _, fs in os.walk(src):
        for f in fs:
            if not f.endswith('.swift'): continue
            with open(os.path.join(d, f), encoding='utf-8', errors='replace') as fh:
                for line in fh:
                    m = _CONSTRAINED.match(line)
                    if not m: continue
                    p = m.group(1).split('.')[-1]
                    for q in re.findall(r'\bSelf\s*:\s*([\w.]+(?:\s*&\s*[\w.]+)*)', m.group(2)):
                        for part in q.split('&'):
                            pairs[p].add(part.strip().split('.')[-1])
    return pairs


def witnesses(M, R, asg, pairs):
    """A type's conformance to P declared where its conformance to Q cannot be seen, for a pair (P, Q) with a
    constrained default `extension P where Self: Q`: the conformance to P is checked without Q, and the constrained
    default silently loses to the unconstrained one (M3's blank render)."""
    sites = collections.defaultdict(lambda: collections.defaultdict(list))
    for ty, pr, decl, f, ln in M.conformances:
        sites[ty][M.symbols.get(pr, ('?',))[0]].append((asg[decl], decl, f, ln))
    out = []
    for ty, ps in sites.items():
        tn = M.symbols.get(ty, ('?',))[0]
        for p, qs in pairs.items():
            for mp, dp, f, ln in ps.get(p, ()):
                for q in sorted(qs):
                    for mq, dq, _, _ in ps.get(q, ()):
                        if R.sees(mp, mq): continue
                        out.append(Finding('witness', f'{tn}: {p} @ {M.label(dp)} / {q} @ {M.label(dq)}',
                                           f'{tn}: {p} is declared in {mp} ({M.label(dp)}), which cannot see '
                                           f'{tn}: {q} in {mq} ({M.label(dq)})', f, ln))
    return out


def _members(M, n):
    """Every public member of a block, for its finding: a block's label names only its first member, and four
    public members once moved module unseen inside lifted blocks (the refined plan's skeptic, split2/refine/challenge).
    The key stays the label, so an `accepted` entry keeps matching while the block changes."""
    ms = M.public_members.get(n)
    return f' (public: {", ".join(ms)})' if ms else ''


def _split(M, R, n, x):
    """A `scheduled` public-above entry names a public member that a refactor moves out of the block (refined plan S1
    and S2): the finding is scheduled while the block holds one. Members no entry names keep the finding new unless
    the block is accepted, so a split scheduled for one member cannot hide the rest of an unreviewed block."""
    members = M.public_members.get(n, ())
    hit = {m: [r for r in R.scheduled if r['check'] == 'public-above' and r['to_rx'].search(m)
               and any(r['from_rx'].search(la) for la in M.rule_labels(n))] for m in members}
    rs = sorted({r['index']: r for h in hit.values() for r in h}.values(), key=lambda r: r['index'])
    if not rs: return x
    x.scheduled = ', '.join(dict.fromkeys(r['id'] for r in rs))
    x.rules.update(r['index'] for r in rs)
    x.unscheduled = sum(1 for m in members if not hit[m])
    return x


def public_above(M, R, asg):
    """Public API of a type or protocol declared in a module above the type's own: an app that imports only the
    type's module does not get it. An extension whose header (conformance list or `where` clause) names a
    declaration of its own module is that module's API, usable only with its types, and is not reported: style
    sugar such as `extension PickerStyle where Self == MenuPickerStyle`, or `extension ForEach: TableRowContent`."""
    out = []
    for n in M.nodes:
        if M.kind[n] != IX.K_EXTENSION or n not in M.public: continue
        t = M.extended_node(n)
        if t is None:
            # A modifier on a type from below the map (`extension View`) sits where its file's rule puts it, beside
            # the feature it configures. One the ASSIGNER carried somewhere else, for its dependencies, is a
            # placement nobody chose (plan section 4: `.modal`, `.listStyle` and `.safeAreaInset` were reviewed).
            # One a `declarations` rule put there was chosen, for the members its rule had in mind: it is reported
            # accepted with the rule's reason, so `-v` lists all its public members (the refined plan found the layout
            # trio inside the block a rule pins to TUIkitBitmaps), and a `scheduled` split can name the others.
            mn, seed = asg[n], R.seed(M.file[n])[0]
            if mn == seed or not R.sees(mn, seed): continue
            rule = R.decl_rule(M.rule_labels(n))
            if rule is None:
                x = Finding('public-above', M.label(n),
                            f'public API on {M.name[n]} carried from {seed} up to {mn} by the assigner: '
                            f'{M.label(n)}{_members(M, n)}', M.file[n], M.line[n])
            else:
                x = Finding('public-above', M.label(n),
                            f'public API on {M.name[n]} placed in {mn} by a declarations rule, above its file\'s {seed}: '
                            f'{M.label(n)}{_members(M, n)}', M.file[n], M.line[n])
                x.accepted = f'declarations rule {rule["match"]}: {rule.get("why") or "no reason given"}'
            out.append(_split(M, R, n, x))
            continue
        mn, mt = asg[n], asg[t]
        if mn == mt or not R.sees(mn, mt): continue
        if any(asg.get(b) == mn for b in M.header.get(n, ())): continue
        out.append(_split(M, R, n, Finding('public-above', M.label(n),
                                           f'public API of {M.name[t]} ({mt}) is declared in {mn}: '
                                           f'{M.label(n)}{_members(M, n)}', M.file[n], M.line[n])))
    return out


def posix(M, R, asg):
    """A POSIX-only API used outside the app module, outside an `#if` arm only POSIX platforms compile; and an
    unguarded `import Darwin`/`Glibc`/`Musl` in a file with code outside the app module."""
    cfg = R.posix
    cnames = set(cfg.get('c_symbols', ())); snames = set(cfg.get('swift_symbols', ()))
    out = []
    for src, usr, f, ln in M.foreign_refs:
        if asg.get(src) == R.app: continue
        nm = M.symbols.get(usr, ('',))[0]
        base = nm.split('(')[0]
        if usr.startswith(('c:', 's:6Darwin', 's:5Glibc', 's:4Musl')) and base in cnames: what = base
        elif nm in snames and 'Dispatch' in usr: what = nm
        else: continue
        lx = M.lexed.get(f)
        if lx and SS.posix_guarded(lx.conds[ln]): continue
        x = Finding('posix', f'{M.label(src)} uses {what}',
                    f'{asg[src]}: {M.label(src)} uses {what}, which only POSIX platforms have', f, ln)
        s = next(filter(None, (R.scheduled_for('posix', l, what) for l in M.rule_labels(src))), None)
        if s: x.scheduled = s['id']; x.rules.add(s['index'])
        out.append(x)
    imports = set(cfg.get('imports', ()))
    if imports:
        outside = {M.file[n] for n in M.nodes if asg[n] != R.app}
        for f in M.files:
            if f not in outside: continue
            lx = M.lexed[f]
            for i in range(1, len(lx.lines) + 1):
                m = SS.import_of(lx.stripped[i])
                if m and m[0] in imports and not SS.posix_guarded(lx.conds[i]):
                    out.append(Finding('posix', f'{f} imports {m[0]}',
                                       f'{f} imports {m[0]} outside a POSIX-only #if arm', f, i))
    # one finding per (declaration, API): the first site
    seen = set(); uniq = []
    for x in out:
        if x.key not in seen: seen.add(x.key); uniq.append(x)
    # The owner relaxed the Windows rule (CLAUDE.md, 2026-10-07): POSIX-only code may live in any module, isolated, and
    # only the four lower modules (outside this map) must keep building on Windows. So with `informational` set, a
    # POSIX use outside the app module is reported but is not a new finding; a scheduled refactor stays scheduled.
    if cfg.get('informational'):
        for x in uniq:
            if not x.scheduled: x.accepted = cfg['informational']
    return uniq


def uncompiled(M, R, asg):
    """A source in a module's directory that no target compiles (model.unit_freshness): its declarations are missing
    from the build, public API included, and nothing else need notice."""
    return [Finding('uncompiled', f, f'{f} is compiled by no target, though the last build ran after it was written: '
                                     f'give its module a target of its own in Package.swift', f, 1)
            for f in M.uncompiled]


def umbrella(M, R, asg):
    """The umbrella holds no code: no declaration is assigned to it, and its files hold only imports. And it
    re-exports, by name, every module carved out above the default module (see `built_on_default`)."""
    out = [Finding('umbrella', M.label(n), f'{M.label(n)} would sit in the umbrella {R.umbrella}', M.file[n], M.line[n])
           for n in M.nodes if asg[n] == R.umbrella]
    mine = [f for f in M.files if R.seed(f)[0] == R.umbrella]
    for f in mine:
        lx = M.lexed[f]
        for i in range(1, len(lx.lines) + 1):
            s = lx.stripped[i].strip()
            imp = SS.import_of(s)
            if s and not (imp and not imp[2]) and not s.startswith('#'):
                out.append(Finding('umbrella', f'{f}:{s[:40]}', f'{f} holds code, not only imports: {s[:60]}', f, i))
                break
    reexports = re_exports(M, R)
    for m in sorted(built_on_default(R, reexports) - reexports[R.umbrella]):
        out.append(Finding('umbrella', f'{R.umbrella} does not re-export {m}',
                           f'{m} is built on {R.default}, so {R.default} cannot re-export it, and {R.umbrella} does '
                           f'not: `import {R.umbrella}` reaches it only through another module\'s re-export, if at '
                           f'all, and loses it when that module\'s dependencies change. Add `@_exported import {m}` '
                           f'to the umbrella\'s Exports.swift', mine[0] if mine else None, 1 if mine else None))
    return out


def re_exports(M, R):
    """{module: the modules its files `@_exported import`}, a file's module being the one its directory seeds."""
    out = collections.defaultdict(set)
    for f in M.files:
        for s in M.lexed[f].stripped:
            imp = SS.import_of(s.strip())
            if imp and imp[1]: out[R.seed(f)[0]].add(imp[0])
    return out


def built_on_default(R, reexports):
    """The modules carved out ABOVE the default module (TUIkitApp, TUIkitColorPicker, TUIkitNavigation …): those whose
    files re-export it, or re-export a module that does. A carved module re-exports the modules it is built on (plan
    §4); a coarse group's other members had no Exports.swift until their peels (the last at step C7),
    so no re-exports, as a module TUIkitFoundation compiled had none until step B7; nor does a module below it
    (TUIkitStrings), which TUIkitFoundation re-exports. TUIkitFoundation cannot re-export a module built on it, so the
    umbrella must, by name: reaching one only through a sibling's re-export (TUIkitPresentation through
    TUIkitColorPicker's; TUIkitNavigation through it from step B5 until step C1) compiles the same, and silently stops
    compiling when that sibling's dependencies change."""
    above = set()
    while True:
        more = {m for m, xs in reexports.items()
                if m not in above and m not in (R.default, R.umbrella) and xs & (above | {R.default})}
        if not more: return above
        above |= more


def _import_graph(M, R):
    """What the import checks share: the modules carved out above the default module (`built_on_default`), and
    `reach(modules)`, the modules those imports make visible, each with what it re-exports, transitively, as the
    compiler's ValueDecl::findImport follows them. A module re-exports what its files `@_exported import`, a module
    being the target that compiled the file, as its index unit names it; a lower module, what its sources do."""
    rex = collections.defaultdict(set)
    for f in M.files:
        t = M.target.get(f)
        if t is None: continue
        for s in M.lexed[f].stripped:
            imp = SS.import_of(s.strip())
            if imp and imp[1]: rex[t].add(imp[0])
    for m, xs in M.lower_reexports.items(): rex[m] |= xs

    def reach(modules):
        todo, vis = set(modules), set()
        while todo:
            m = todo.pop()
            if m in vis: continue
            vis.add(m); todo |= rex.get(m, set())
        return vis
    return built_on_default(R, rex), reach


def _file_uses(M, above):
    """(file, module, name, references, line) for each module that a declaration of a file of a module in `above`
    names outside the file's own target: another target (by the declaration it names), or a lower module (by the
    symbol). A target is as the index unit names it; a reference to the SDK is none of these."""
    for a in M.nodes:
        f = M.file[a]
        t = M.target.get(f)
        if t not in above: continue
        # The edge's first site is in `f`, the node's own file: a node is one top-level declaration, and `top()`
        # follows lexical containers, so every reference a node makes is in the file that declares it.
        for b, (k, (_, ln)) in M.edges.get(a, {}).items():
            tb = M.target.get(M.file[b])
            if tb is not None and tb != t: yield f, tb, M.name[b], k, ln
    for src, usr, f, ln in M.foreign_refs:
        if M.target.get(f) not in above: continue
        lm = M.lower_module(usr)
        if lm is not None: yield f, lm, M.lower_name.get(usr) or M.symbols.get(usr, ('?',))[0], 1, ln


def imports(M, R):
    """A file of a module carved out above the default module (TUIkitApp, TUIkitColorPicker, TUIkitNavigation,
    TUIkitLists …) that uses another of the package's modules without importing it: neither directly nor through a
    module it imports that re-exports it. It compiles, because its module's Exports.swift re-exports TUIkitFoundation
    to every file of the module. But the compiler decides whether a closure passed to a function needs a run-time
    MainActor check by the calling FILE's imports (CSApply.cpp, closuresRequireDynamicIsolationChecking, through
    ValueDecl::findImport): a callee from a module the file does not import, directly or through that import's
    re-exports, gets one in every closure passed to it. One finding per file and module, weighed by its references.

    The modules are the targets that compiled the files, as their index units name them (a coarse group's target for
    each of its directories), and the lower modules (TUIkitCore, TUIkitView …). A reference inside the file's own
    target needs no import; one to the SDK is not this check's business. Not checked: TUIkitFoundation's own files and
    the side modules below it, whose references to the lower modules each module's own imports have always carried."""
    above, reach = _import_graph(M, R)
    seen_vis = {}

    def visible(f):
        if f not in seen_vis:
            seen_vis[f] = reach(x[0] for x in map(SS.import_of, (s.strip() for s in M.lexed[f].stripped)) if x)
        return seen_vis[f]
    found = {}

    def note(f, mod, name, k, ln):
        x = found.get((f, mod))
        if x is None:
            x = found[(f, mod)] = Finding('imports', f'{f} uses {mod}', None, f, ln)
            x.weight, x.names = 0, []
        x.weight += k
        x.line = min(x.line, ln)
        if name not in x.names: x.names.append(name)
    for f, mod, name, k, ln in _file_uses(M, above):
        if mod not in visible(f): note(f, mod, name, k, ln)
    out = sorted(found.values(), key=lambda x: x.key)
    for x in out:
        names = ', '.join(x.names[:4]) + (' …' if len(x.names) > 4 else '')
        x.message = (f'{x.file} uses {x.key.rsplit(" ", 1)[1]} ({names}; {x.weight} reference'
                     f'{"s" if x.weight != 1 else ""}) without importing it, so every closure it passes to that module '
                     f'gets a run-time MainActor check: add `import {x.key.rsplit(" ", 1)[1]}` to the file')
    return out


def lower(M, R, asg):
    """A reference to a lower module (TUIkitCore, TUIkitView …: a module outside the map) that its declaration's
    module may not use: one its `lower` list in rules.json does not name. A module with no list may use them all.
    Once split, the module would not import it, so this is a compile error; for a side module that compiles beside
    TUIkitView, a dependency on it would also put the side module back on the critical path. One finding per
    declaration and symbol, weighed by its references."""
    out, seen = [], {}
    for src, usr, f, ln in M.foreign_refs:
        allowed = R.lower.get(asg.get(src))
        if allowed is None: continue
        lm = M.lower_module(usr)
        if lm is None or lm in allowed: continue
        name = M.lower_name.get(usr) or M.symbols.get(usr, ('?',))[0]
        key = f'{M.label(src)} uses {lm}.{name}'
        if key in seen:
            seen[key].weight += 1; continue
        x = Finding('lower', key, f'{asg[src]}: {M.label(src)} uses {lm}.{name}, and {asg[src]}\'s lower list does '
                                  f'not name {lm}', f, ln)
        s = next(filter(None, (R.scheduled_for('lower', la, f'{lm}.{name}') for la in M.rule_labels(src))), None)
        if s: x.scheduled = s['id']; x.rules.add(s['index'])
        seen[key] = x; out.append(x)
    return out


def stale_rules(R, findings):
    """A `scheduled` or `accepted` entry that no longer matches anything: the refactor landed, or the code moved.
    Delete it, so the rules stay a list of open items."""
    used_sched = {i for x in findings for i in x.rules}          # per entry: K4 and K6 have several
    used_acc = {(x.check, x.key) for x in findings if x.accepted}
    out = []
    for r in R.scheduled:
        if r['index'] not in used_sched:
            out.append(Finding('rules', f'scheduled {r["id"]} {r["check"]} {r["from"]}',
                               f'scheduled {r["id"]} ({r["check"]}) matches nothing now: if the refactor landed, '
                               f'delete the entry from rules.json'))
    for (check, key), r in R.accepted.items():
        if (check, key) not in used_acc:
            out.append(Finding('rules', f'accepted {check} {key}',
                               f'accepted {check} "{key}" matches nothing now: if the declaration was renamed or now '
                               f'opens with another member, give the entry the key `check` prints for it; if the '
                               f'finding is gone, delete the entry from rules.json'))
    return out


def run_all(M, R, asg, root):
    pairs = collections.defaultdict(set)
    for p, qs in R.witness_pairs.items(): pairs[p] |= qs
    for p, qs in derived_witness_pairs(root).items(): pairs[p] |= qs
    findings = (uncompiled(M, R, asg) + upward(M, R, asg) + owns_neither(M, R, asg) + witnesses(M, R, asg, pairs)
                + public_above(M, R, asg) + posix(M, R, asg) + umbrella(M, R, asg) + lower(M, R, asg) + imports(M, R))
    for x in findings:
        a = R.accepted.get((x.check, x.key))
        if a: x.accepted = a.get('why', 'accepted')
    return findings + stale_rules(R, findings)
