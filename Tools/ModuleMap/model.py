"""The declaration graph of one module, from its index store and its sources.

A NODE is a top-level declaration: a type, an extension, a protocol, a top-level function, variable or typealias.
Members belong to their node (the index's child-of chain), because the split moves whole declarations: nothing is
cut inside one.

An EDGE src -> dst counts the references from src's text to declarations of dst. A reference the index gives a
container (the function, accessor, type or extension it sits in) is charged to that container's node. A reference
it gives none to — a typealias's right-hand side, an associated-type default, an inheritance or `where` clause, an
attribute argument — is charged BY SPAN: to the top-level declaration whose chunk (swiftsource.chunks) holds the
line. The research graph charged those to the next declaration within three lines, which hid plan §4's X1 and X2.
"""
import collections
import os
import re

import indexstore as IX
import swiftsource as SS

DEF = IX.DECLARATION | IX.DEFINITION
REF = IX.REFERENCE
_ACCESSOR = re.compile(r'^(getter|setter|_modify|modify|read|willSet|didSet):')
_PUBLIC = re.compile(r'\b(public|open)\b')


class Model:
    """Everything the assigner and the checks read. Built by `Model.load` from an index store, or directly from
    plain data (the unit tests do that)."""

    def __init__(self):
        self.files = []                 # rel paths of the module's sources on disk
        self.lexed = {}                 # rel -> swiftsource.Lexed
        self.nodes = []                 # node usrs, sorted by (file, line)
        self.file = {}                  # node -> rel path
        self.line = {}                  # node -> definition line
        self.name = {}                  # node -> name
        self.kind = {}                  # node -> indexstore kind
        self.lines = {}                 # node -> its share of its file's lines (the assigner's majority weight)
        self.public = set()             # nodes that are or hold public/open API
        self.members = {}               # node -> base names of its direct callable members
        self.ext_of = {}                # extension node -> usr of the type or protocol it extends
        self.edges = {}                 # src -> {dst: [count, (rel, line) of the first site]}
        self.header = {}                # node -> nodes its declaration header names (inheritance, where clause)
        self.conformances = []          # (type usr, protocol usr, declaring node, rel, line)
        self.symbols = {}               # usr -> (name, kind, subkind), for every symbol the module references
        self.foreign_refs = []          # (node, usr, rel, line): references to symbols defined outside the module
        self.stale = []                 # rel paths whose source is newer than its index unit, or have none
        self.top = lambda u: u          # usr -> the node holding it (set by build)
        self._labels = None

    # ── labels ────────────────────────────────────────────────────────────────────────────────────────────
    def base_label(self, n):
        return f'{self.file[n]}::{self.name[n]}' + ('(ext)' if self.kind[n] == IX.K_EXTENSION else '')

    def label(self, n):
        """`path::Name`, `(ext)` for an extension, `#k` for the k-th node of that label in its file (k >= 2)."""
        if self._labels is None:
            seen = collections.Counter(); self._labels = {}
            for m in self.nodes:
                b = self.base_label(m); seen[b] += 1
                self._labels[m] = b if seen[b] == 1 else f'{b}#{seen[b]}'
        return self._labels[n]

    def short_label(self, n):
        """The label inside its file: `Name`, `Name(ext)`, `Name(ext)#2`."""
        return self.label(n).split('::', 1)[1]

    # ── loading ───────────────────────────────────────────────────────────────────────────────────────────
    @classmethod
    def load(cls, root, source_dir, store, lib=None, module='TUIkit'):
        prefix = os.path.join(os.path.realpath(root), source_dir) + '/'
        files, symbols, mtimes = IX.read(store, module, prefix, lib)
        if not files:                    # the store may have recorded the unresolved path
            prefix = os.path.join(root, source_dir) + '/'
            files, symbols, mtimes = IX.read(store, module, prefix, lib)
        occ = {p[len(prefix):]: o for p, o in files.items()}
        m = cls()
        m.symbols = symbols
        src = os.path.join(root, source_dir)
        m.files = sorted(os.path.relpath(os.path.join(d, f), src) for d, _, fs in os.walk(src) for f in fs
                         if f.endswith('.swift'))
        for f in m.files:
            p = os.path.join(src, f)
            with open(p, encoding='utf-8', errors='replace') as fh:
                m.lexed[f] = SS.lex(fh.read())
            t = mtimes.get(prefix + f)
            if t is None or os.path.getmtime(p) > t + 1: m.stale.append(f)
        m.build({f: o for f, o in occ.items() if f in m.lexed})
        return m

    def build(self, occ):
        """Nodes, edges, conformances and the rest from {rel: [(usr, roles, line, container)]}."""
        parent, deffile, defline = {}, {}, {}
        for f, occs in occ.items():
            for usr, roles, line, cont in occs:
                if roles & DEF and not roles & REF:
                    if usr not in deffile: deffile[usr] = f; defline[usr] = line
                    if cont and usr not in parent: parent[usr] = cont
        self._parent = parent

        def top(u):
            k = 0
            while u in parent and k < 50: u = parent[u]; k += 1
            return u
        self.top = top
        nodes = {}
        for u in deffile:
            t = top(u)
            if t not in nodes and t in deffile: nodes[t] = deffile[t]
        self.nodes = sorted(nodes, key=lambda n: (deffile[n], defline[n], n))
        nodeset = set(self.nodes)
        for n in self.nodes:
            self.file[n] = deffile[n]; self.line[n] = defline[n]
            s = self.symbols.get(n, ('?', 0, 0))
            self.name[n] = s[0]; self.kind[n] = s[1]
        self.deffile = deffile
        # top-level definitions per file, and chunk spans for span attribution
        topdefs = collections.defaultdict(list)
        for n in self.nodes: topdefs[self.file[n]].append((self.line[n], n))
        for f in topdefs: topdefs[f].sort()
        chunks = {f: SS.chunks(self.lexed[f]) for f in topdefs if f in self.lexed}

        def by_span(f, line):
            for st, en, _ in chunks.get(f, ()):
                if st <= line <= en:
                    inside = [(ln, u) for ln, u in topdefs[f] if st <= ln <= en]
                    if not inside: return None
                    before = [x for x in inside if x[0] <= line]
                    return (before[-1] if before else inside[0])[1]
            return None
        self.by_span = by_span
        # line weights: a node's span up to the next top-level definition, normalised to its file's lines
        span = {}
        for f, L in topdefs.items():
            total = len(self.lexed[f].lines) if f in self.lexed else 0
            for i, (ln, u) in enumerate(L):
                end = L[i + 1][0] - 1 if i + 1 < len(L) else total
                span[u] = max(1, end - ln + 1)
        flines = collections.Counter()
        for n in self.nodes: flines[self.file[n]] += span[n]
        for n in self.nodes:
            f = self.file[n]
            total = len(self.lexed[f].lines) if f in self.lexed else span[n]
            self.lines[n] = span[n] * total / max(1, flines[f])
        # extended types
        for f, occs in occ.items():
            for usr, roles, line, cont in occs:
                if roles & IX.REL_EXTENDED_BY and cont.startswith('s:e:') and cont not in self.ext_of:
                    self.ext_of[cont] = usr
        # edges, conformances, members, public API, references out of the module
        members = collections.defaultdict(set)
        for f, occs in occ.items():
            lx = self.lexed.get(f)
            for usr, roles, line, cont in occs:
                if roles & DEF and not roles & REF:
                    if cont in nodeset and self.symbols.get(usr, ('', 0))[1] in IX.CALLABLE_KINDS:
                        members[cont].add(_ACCESSOR.sub('', self.symbols[usr][0]).split('(')[0])
                    holder = usr if not cont else top(cont)
                    if holder in nodeset and lx and 0 < line < len(lx.stripped) and \
                            _PUBLIC.search(lx.stripped[line].split('{')[0]):
                        self.public.add(holder)
                    continue
                # Everything else is a use: a reference, or an IMPLICIT occurrence (roles implicit + override-of) that
                # records a conformance taking its witness from a default implementation in an extension. That
                # makes the extension a dependency of the conforming type, which is what keeps a type and the
                # default witnesses it relies on visible to each other.
                src = top(cont) if cont else by_span(f, line)
                if src is None or src not in nodeset: continue
                if roles & IX.REL_BASE_OF and cont:
                    ty = self.ext_of.get(cont) if cont.startswith('s:e:') else cont
                    if ty: self.conformances.append((ty, usr, src, f, line))
                if usr not in deffile:
                    self.foreign_refs.append((src, usr, f, line)); continue
                dst = top(usr)
                if dst == src or dst not in nodeset: continue
                if not cont or cont == src: self.header.setdefault(src, set()).add(dst)
                e = self.edges.setdefault(src, {}).get(dst)
                if e is None: self.edges[src][dst] = [1, (f, line)]
                else:
                    e[0] += 1
                    if (f, line) < e[1]: e[1] = (f, line)      # the first site in path order, whatever the store's
        self.members = {n: members.get(n, set()) for n in self.nodes}
        self.conformances = sorted(set(self.conformances), key=lambda c: (c[3], c[4], c[1]))

    # ── helpers the assigner and the checks share ────────────────────────────────────────────────────────
    def extended_node(self, n):
        """The node of the module type or protocol an extension node extends, else None."""
        u = self.ext_of.get(n)
        if u is None: return None
        t = self.top(u)
        return t if t in self.file else None
