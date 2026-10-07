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
        self.accepted = None            # the `accepted` entry's reason
        self.weight = 1                 # the references it stands for (upward: the edge's count)

    @property
    def new(self):
        return not self.scheduled and not self.accepted


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
            s = R.scheduled_for('upward', M.base_label(a), M.base_label(b))
            if s: x.scheduled = s['id']
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
            mn, seed = asg[n], R.seed(M.file[n])[0]
            if mn != seed and R.sees(mn, seed) and not any(rx.search(M.base_label(n)) for _, rx in R.decls):
                out.append(Finding('public-above', M.label(n),
                                   f'public API on {M.name[n]} carried from {seed} up to {mn} by the assigner: '
                                   f'{M.label(n)}', M.file[n], M.line[n]))
            continue
        mn, mt = asg[n], asg[t]
        if mn == mt or not R.sees(mn, mt): continue
        if any(asg.get(b) == mn for b in M.header.get(n, ())): continue
        out.append(Finding('public-above', M.label(n),
                           f'public API of {M.name[t]} ({mt}) is declared in {mn}: {M.label(n)}', M.file[n], M.line[n]))
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
        s = R.scheduled_for('posix', M.base_label(src), what)
        if s: x.scheduled = s['id']
        out.append(x)
    imports = '|'.join(map(re.escape, cfg.get('imports', ())))
    if imports:
        rx = re.compile(r'^\s*(?:@[\w]+\s+)?import\s+(' + imports + r')\b')
        outside = {M.file[n] for n in M.nodes if asg[n] != R.app}
        for f in M.files:
            if f not in outside: continue
            lx = M.lexed[f]
            for i in range(1, len(lx.lines) + 1):
                m = rx.match(lx.stripped[i])
                if m and not SS.posix_guarded(lx.conds[i]):
                    out.append(Finding('posix', f'{f} imports {m.group(1)}',
                                       f'{f} imports {m.group(1)} outside a POSIX-only #if arm', f, i))
    # one finding per (declaration, API): the first site
    seen = set(); uniq = []
    for x in out:
        if x.key not in seen: seen.add(x.key); uniq.append(x)
    return uniq


def umbrella(M, R, asg):
    """The umbrella holds no code: no declaration is assigned to it, and its files hold only imports."""
    out = [Finding('umbrella', M.label(n), f'{M.label(n)} would sit in the umbrella {R.umbrella}', M.file[n], M.line[n])
           for n in M.nodes if asg[n] == R.umbrella]
    for f in M.files:
        if R.seed(f)[0] != R.umbrella: continue
        lx = M.lexed[f]
        for i in range(1, len(lx.lines) + 1):
            s = lx.stripped[i].strip()
            if s and not re.match(r'^(@_exported\s+)?import\s+\w+$', s) and not s.startswith('#'):
                out.append(Finding('umbrella', f'{f}:{s[:40]}', f'{f} holds code, not only imports: {s[:60]}', f, i))
                break
    return out


def stale_rules(R, findings):
    """A `scheduled` or `accepted` entry that no longer matches anything: the refactor landed, or the code moved.
    Delete it, so the rules stay a list of open items."""
    used_sched = {(x.check, x.scheduled) for x in findings if x.scheduled}
    used_acc = {(x.check, x.key) for x in findings if x.accepted}
    out = []
    for r in R.scheduled:
        if (r['check'], r['id']) not in used_sched:
            out.append(Finding('rules', f'scheduled {r["id"]} {r["check"]} {r["from"]}',
                               f'scheduled {r["id"]} ({r["check"]}) matches nothing now: if the refactor landed, '
                               f'delete the entry from rules.json'))
    for (check, key), r in R.accepted.items():
        if (check, key) not in used_acc:
            out.append(Finding('rules', f'accepted {check} {key}',
                               f'accepted {check} "{key}" matches nothing now: delete the entry from rules.json'))
    return out


def run_all(M, R, asg, root):
    pairs = collections.defaultdict(set)
    for p, qs in R.witness_pairs.items(): pairs[p] |= qs
    for p, qs in derived_witness_pairs(root).items(): pairs[p] |= qs
    findings = (upward(M, R, asg) + owns_neither(M, R, asg) + witnesses(M, R, asg, pairs) + public_above(M, R, asg)
                + posix(M, R, asg) + umbrella(M, R, asg))
    for x in findings:
        a = R.accepted.get((x.check, x.key))
        if a: x.accepted = a.get('why', 'accepted')
    return findings + stale_rules(R, findings)
