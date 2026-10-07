"""The assigner: rules.json + the declaration graph -> a module for every node.

The research assigner of buildtime/split2 (sassign.py + finalize.py), ported:

1. SEED. Every node starts in the module its file's first matching rule names (else the default). An extension in
   a default-module file goes where the type it extends is seeded. Pinned files and declaration rules are fixed.
2. ATOMIC GROUPS, which move together:
   - an overload set: the same member name on the same type, in files seeded to one module;
   - a protocol and the extensions that implement its requirements (its default witnesses);
   - a type and the extensions that add conformances its seed module can see.
     A View's default witnesses are chosen where the conformance is checked, so a Renderable conformance declared
     in another module would silently go unused (M3's blank render).
   An unpinned group's module is its members' majority by lines.
3. FIXPOINT, until nothing moves:
   - UP TO DEPENDENCIES: a group that cannot see what it uses goes up to the lowest module that sees all of it,
     when everything that uses the group still sees that module.
   - DOWN: a group used from a module that cannot see it goes down to where both meet.
   - UP: a group that is not public API, and whose every user sits in one module above it, goes up to that
     module, if it still sees its own dependencies.
4. POST-PASSES:
   - a group that went up only transiently returns to its seed when the seed works again;
   - a conformance declared in a module that owns neither the type nor the protocol moves to the type's module
     (else the protocol's), if that creates no upward reference.

References matched by a `scheduled` rule (the K refactors, which have not landed yet) are left out of the
fixpoint, so they do not drag declarations down. The check reports them as scheduled, not as findings.
"""
import collections

import indexstore as IX


def assign(model, rules):
    M, R = model, rules
    nodes = M.nodes
    nodeset = set(nodes)
    OUT = {a: {b: e[0] for b, e in M.edges.get(a, {}).items() if b in nodeset} for a in nodes}
    IN = collections.defaultdict(dict)
    for a, bs in OUT.items():
        for b, k in bs.items(): IN[b][a] = k

    def seed_node(n):
        m, pin = R.seed(M.file[n])
        if pin: return m, True
        if M.kind[n] == IX.K_EXTENSION and m == R.default:
            t = M.extended_node(n)
            if t is not None:
                mt, _ = R.seed(M.file[t])
                if mt != R.default: return mt, False
        return m, False

    asg, pinned = {}, set()
    for n in nodes:
        m, pin = seed_node(n)
        asg[n] = m
        if pin and not any(rx.search(l) for rx in R.unpin for l in M.rule_labels(n)): pinned.add(n)
    for m, rx in R.decls:
        for n in nodes:
            if any(rx.search(l) for l in M.rule_labels(n)): asg[n] = m; pinned.add(n)
    cut = set()
    for a in nodes:
        for b in OUT[a]:
            if any(R.scheduled_for('upward', la, lb) for la, lb in zip(M.rule_labels(a), M.rule_labels(b))): cut.add((a, b))

    # ── atomic groups ──────────────────────────────────────────────────────────────────────────────────
    par = {n: n for n in nodes}

    def find(x):
        while par[x] != x: par[x] = par[par[x]]; x = par[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb: par[ra] = rb
    by_member = collections.defaultdict(list)
    for n in nodes:
        if M.kind[n] in IX.TYPE_KINDS + (IX.K_EXTENSION,):
            owner = M.name[n]
            for b in sorted(M.members.get(n, ())):
                by_member[(owner, b, R.seed(M.file[n])[0])].append(n)
    overload_groups = 0
    for v in by_member.values():
        if len(v) > 1:
            overload_groups += 1
            for x in v[1:]: union(v[0], x)
    default_witnesses = 0
    for n in nodes:
        if M.kind[n] != IX.K_EXTENSION: continue
        p = M.extended_node(n)
        if p is not None and M.kind[p] == IX.K_PROTOCOL and M.members.get(n, set()) & M.members.get(p, set()):
            union(n, p); default_witnesses += 1
    conf = collections.defaultdict(set)
    for ty, pr, decl, _, _ in M.conformances:          # conformances an extension adds to the type it extends
        if decl in nodeset and M.kind[decl] == IX.K_EXTENSION and M.ext_of.get(decl) == ty: conf[decl].add(pr)
    conformance_ties = 0
    for n in nodes:
        if M.kind[n] != IX.K_EXTENSION or n not in conf: continue
        t = M.extended_node(n)
        if t is None or t == n: continue
        tm = R.seed(M.file[t])[0]
        if all(p not in nodeset or R.sees(tm, R.seed(M.file[p])[0]) for p in conf[n]):
            union(n, t); conformance_ties += 1
    GROUP = collections.defaultdict(list)
    for n in nodes: GROUP[find(n)].append(n)
    gpublic = {g for g, mem in GROUP.items() if any(x in M.public for x in mem)}

    for g, mem in GROUP.items():
        pins = {asg[x] for x in mem if x in pinned}
        if pins:
            m = min(pins, key=R.rank)
        else:
            c = collections.Counter()
            for x in mem: c[asg[x]] += M.lines[x]
            m = max(c, key=lambda k: (c[k], -R.order.index(k)))
        for x in mem:
            asg[x] = m
            if pins: pinned.add(x)

    # ── fixpoint ───────────────────────────────────────────────────────────────────────────────────────
    upper = [m for m in R.order if m not in (R.default, R.umbrella) and R.deps[m]]
    last = {}
    for _ in range(400):
        changed = 0
        for g, mem in GROUP.items():
            if mem[0] in pinned: continue
            m = asg[mem[0]]
            deps = {asg[b] for x in mem for b in OUT[x] if b not in mem and (x, b) not in cut}
            if not deps or all(R.sees(m, d) for d in deps): continue
            L = R.join(deps | {m})
            refs = {asg[a] for x in mem for a in IN.get(x, {}) if a not in mem and (a, x) not in cut}
            if all(R.sees(r, L) for r in refs):
                for x in mem: asg[x] = L
                last[g] = 'updep'; changed += 1
        for g, mem in GROUP.items():
            if mem[0] in pinned: continue
            m = asg[mem[0]]; tgt = m
            for x in mem:
                for a in IN.get(x, {}):
                    if (a, x) in cut: continue
                    if not R.sees(asg[a], tgt): tgt = R.meet(asg[a], tgt)
            if tgt != m:
                for x in mem: asg[x] = tgt
                last[g] = 'down'; changed += 1
        for g, mem in GROUP.items():
            if mem[0] in pinned or g in gpublic: continue
            m = asg[mem[0]]
            refs = {asg[a] for x in mem for a in IN.get(x, {}) if a not in mem and (a, x) not in cut}
            if not refs: continue
            cands = [u for u in upper if u != m and R.sees(u, m) and all(R.sees(r, u) for r in refs)]
            if not cands: continue
            u = max(cands, key=lambda u: (len(R.sees_set[u]), -R.order.index(u)))
            if any(r == u for r in refs) and all(R.sees(u, asg[b]) or (x, b) in cut
                                                 for x in mem for b in OUT[x] if b not in mem):
                for x in mem: asg[x] = u
                last[g] = 'up'; changed += 1
        if not changed: break

    # ── post-passes ────────────────────────────────────────────────────────────────────────────────────
    def fits(mem, m):
        for x in mem:
            for b in OUT[x]:
                if b not in mem and (x, b) not in cut and not R.sees(m, asg[b]): return False
            for a in IN.get(x, {}):
                if a not in mem and (a, x) not in cut and not R.sees(asg[a], m): return False
        return True
    for _ in range(20):
        ch = 0
        for g, mem in GROUP.items():
            if mem[0] in pinned or last.get(g) != 'updep': continue
            m = asg[mem[0]]
            seeds = collections.Counter()
            for x in mem: seeds[seed_node(x)[0]] += M.lines[x]
            sd = max(seeds, key=lambda k: (seeds[k], -R.order.index(k)))
            if sd != m and (R.sees(m, sd) or m == R.umbrella) and fits(mem, sd):
                for x in mem: asg[x] = sd
                ch += 1
        if not ch: break
    moved = []
    for ty, pr, decl, _, _ in M.conformances:
        if decl not in nodeset: continue
        dm = asg[decl]
        tm = module_of(M, asg, ty); pm = module_of(M, asg, pr)
        if tm not in R.sees_set and pm not in R.sees_set: continue   # owned by neither today: not the split's doing
        if dm in (tm, pm): continue
        tgt = tm if tm in R.sees_set else pm
        if tgt in R.sees_set and fits([decl], tgt):
            asg[decl] = tgt; moved.append(decl)
    info = dict(overload_groups=overload_groups, default_witnesses=default_witnesses,
                conformance_ties=conformance_ties, groups=len(GROUP), conformance_moves=len(moved))
    assign.groups = {n: GROUP[find(n)] for n in nodes}       # for `explain`
    assign.last = {n: last.get(find(n)) for n in nodes}
    return asg, info


def module_of(M, asg, usr):
    """The module a symbol is declared in under `asg`: the map's module for a node of this module, the module
    name in its USR for one of the lower four, None for anything else (the SDK, the standard library)."""
    t = M.top(usr)
    if t in asg: return asg[t]
    for prefix, mod in LOWER:
        if usr.startswith(prefix) or usr.startswith('s:e:' + prefix): return mod
    return None


LOWER = [('s:10TUIkitCore', 'TUIkitCore'), ('s:10TUIkitView', 'TUIkitView'), ('s:13TUIkitStyling', 'TUIkitStyling'),
         ('s:11TUIkitImage', 'TUIkitImage')]
