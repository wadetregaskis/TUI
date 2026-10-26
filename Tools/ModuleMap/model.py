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
# `public` or `open` as an access modifier: followed on its line by another modifier, a declaration keyword or an
# attribute. Not `open` the identifier (`func open()`, `private var open: Bool`, `case open`).
_PUBLIC = re.compile(r'(?:^|[\s)])(?:public|open)\s+(?=(?:' + SS.MOD + '|' + SS.KW + r'|prefix|postfix|infix)\b|@)')
# Any other access modifier, in the same position. Not `private(set)`, which leaves the getter's access alone.
_ACCESS = re.compile(r'(?:^|[\s)])(?:package|internal|fileprivate|private)\s+(?=(?:' + SS.MOD + '|' + SS.KW +
                     r'|prefix|postfix|infix)\b|@)')


def visible_modules(top, me, lexed):
    """The modules beside `me` under `top` that `me`'s sources (lexed, comments stripped) import, and what those
    re-export (`@_exported import`), transitively: everything `me` can use of them. The package's other modules
    (Example, Stress, the ones that import `me`) are left out, so the `lower` check does not read their index.
    `me` is a directory name, or a set of them: the map's own modules, each in a directory of its own."""
    mine = {me} if isinstance(me, str) else set(me)
    here = {d for d in os.listdir(top) if d not in mine and os.path.isdir(os.path.join(top, d))}
    seen, todo = set(), set()
    for lx in lexed:
        for s in lx.stripped:
            x = SS.import_of(s)
            if x and x[0] in here: todo.add(x[0])
    while todo:
        d = todo.pop()
        if d in seen: continue
        seen.add(d)
        for dp, _, fs in os.walk(os.path.join(top, d)):
            for f in fs:
                if not f.endswith('.swift'): continue
                with open(os.path.join(dp, f), encoding='utf-8', errors='replace') as fh:
                    for s in fh:
                        x = SS.import_of(s)
                        if x and x[1] and x[0] in here: todo.add(x[0])
    return seen


def reexports_of(dirs):
    """{module: the modules its sources `@_exported import`} for {module: source directory}: what `import module`
    makes visible besides the module itself (the `imports` check follows it transitively)."""
    out = {}
    for mod, d in dirs.items():
        xs = set()
        for dp, _, fs in os.walk(d):
            for f in fs:
                if not f.endswith('.swift'): continue
                with open(os.path.join(dp, f), encoding='utf-8', errors='replace') as fh:
                    for s in fh:
                        x = SS.import_of(s.strip())
                        if x and x[1]: xs.add(x[0])
        out[mod] = xs
    return out


def lower_owners(files, dirs, symbols):
    """({usr: module}, {usr: qualified name}) for every symbol the lower modules define, from their occurrences
    ({path: [(usr, roles, line, container)]}) and symbols ({usr: (name, kind, subkind)}), as indexstore.read gives
    them, and {module: source prefix}. A symbol two of them define (none should) goes to the first by name.

    The qualified name prefixes the name with the types (or extended types) it is nested in, `AppState.shared`, and an
    accessor with its property's type, `AppState.getter:shared`: a bare name would merge every `shared` and every
    `init(_:)` of a module into one finding, and one `scheduled` pattern would cover them all."""
    owner, parent = {}, {}
    for mod, pre in sorted(dirs.items()):
        for p, occs in files.items():
            if not p.startswith(pre): continue
            for usr, roles, _, cont in occs:
                if roles & DEF and not roles & REF:
                    owner.setdefault(usr, mod)
                    if cont: parent.setdefault(usr, cont)
    holders = IX.TYPE_KINDS + (IX.K_EXTENSION,)

    def qualified(u):
        parts, p, k = [symbols.get(u, ('?',))[0]], parent.get(u), 0
        while p and k < 50:
            if symbols.get(p, ('', 0))[1] in holders: parts.append(symbols[p][0])
            p, k = parent.get(p), k + 1
        return '.'.join(reversed(parts))
    return owner, {u: qualified(u) for u in owner}


def _changed(path):
    """When `path` last changed, as far as an index unit can be stale against it: the later of its content's mtime and
    its inode's ctime. A rename (`git mv`) keeps mtime and updates ctime, so mtime alone took a just-moved file for one
    the last build had indexed, and `check` then called it compiled by no target until a rebuild (SPA5 review2, S3)."""
    st = os.stat(path)
    return max(st.st_mtime, st.st_ctime)


def unit_freshness(files, source_mtime, unit_mtime, newest):
    """(stale, uncompiled): the `files` (rel paths) the index does not describe as they are, from each one's source
    mtime, its index unit's mtime (absent: no unit) and the newest unit the store holds for the map's modules.

    STALE: the source is newer than its unit, or it has none and is newer than the last build. Rebuild, then check.
    UNCOMPILED: it has no unit although the last build wrote one after the source was written. That build compiled other
    files once this one existed and did not compile it, so no target does: Package.swift leaves it out. A coarse group's
    `directories:` named its members' directories until step C7 peeled the last member out, as the one target that
    compiled them (TUI's, `TUIFoundation` from step B1) named every module directory in its `sources:` from step
    A5 to step B7, so a new member's directory was compiled only once named there; since C7 every module is a target
    at its default path, so a new module's directory is compiled only once its target exists (and until step B2
    TUIStrings was listed below its directory, file by file,
    because its resources may not sit under a source path; its own target now takes every file in it). SwiftPM reports
    such a file as unhandled, but only as a warning, which does not fail CI: this finding does. (A build that failed
    before reaching a file also leaves it without a unit: build again, and the finding goes.)"""
    stale, uncompiled = [], []
    for f in files:
        s, t = source_mtime[f], unit_mtime.get(f)
        if t is None and newest is not None and s + 1 < newest: uncompiled.append(f)
        elif t is None or s > t + 1: stale.append(f)
    return stale, uncompiled


# The lower modules' USR prefixes (`s:` + the mangled module name): which one defines a symbol when the index's own
# answer (`lower_owner`) is missing, as in a model built without reading them. A member a lower module adds to an SDK
# type (`s:Sa7TUIViewE…`) has no such prefix; only the index knows it.
LOWER_PREFIXES = [('s:7TUICore', 'TUICore'), ('s:7TUIView', 'TUIView'),
                  ('s:10TUIStyling', 'TUIStyling'), ('s:8TUIImage', 'TUIImage')]


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
        self.lower_owner = {}           # usr -> the lower module (beside the source directory) that defines it
        self.lower_name = {}            # usr -> its name qualified by its types in that module (`AppState.shared`)
        self.lower_visible = set()      # the lower modules this module's sources can see (visible_modules)
        self.lower_modules = set()      # the lower modules whose definitions were read
        self.lower_reexports = {}       # lower module -> the modules its sources `@_exported import`
        self.target = {}                # rel path -> the module its index unit names: the target that compiled it
        self.public_members = {}        # node -> names of the public API it declares, in source order
        self.stale = []                 # rel paths whose source is newer than its index unit, or than the build
        self.uncompiled = []            # rel paths no target compiles (unit_freshness)
        self.first_member = {}          # node -> name of its first member in source order (explicit ones only)
        self.conformed = {}             # node -> sorted names of the protocols it declares conformance to
        self.top = lambda u: u          # usr -> the node holding it (set by build)
        self._labels = None

    # ── labels ────────────────────────────────────────────────────────────────────────────────────────────
    def base_label(self, n):
        return f'{self.file[n]}::{self.name[n]}' + ('(ext)' if self.kind[n] == IX.K_EXTENSION else '')

    def rule_labels(self, n):
        """What a rule's pattern is matched against: the printed label (`path::Name(ext)#first`, as `explain` and the
        findings show it, so a copied label pins exactly that declaration) and the base label (`path::Name(ext)`, so a
        pattern written for the base pins every extension of the type in the file)."""
        return (self.label(n), self.base_label(n))

    def discriminator(self, n):
        """What tells an extension apart from the file's other extensions of its type, from its own text: the name
        of its first member (`listStyle(_:)`), else the protocols it conforms to (`Equatable&Sendable`). Not its
        position: an extension added above it must not take over its entry in map.json."""
        if self.kind[n] != IX.K_EXTENSION: return ''
        return self.first_member.get(n) or '&'.join(self.conformed.get(n, ()))

    def label(self, n):
        """`path::Name` for a type, function or variable; `path::Name(ext)#first` for an extension, with its
        discriminator (see `discriminator`). Labels that are still equal in one file (constrained extensions
        opening with the same initializer) get `#2`, `#3` … in source order."""
        if self._labels is None:
            seen = collections.Counter(); self._labels = {}
            for m in self.nodes:
                d = self.discriminator(m)
                b = self.base_label(m) + (f'#{d}' if d else '')
                seen[b] += 1
                self._labels[m] = b if seen[b] == 1 else f'{b}#{seen[b]}'
        return self._labels[n]

    def short_label(self, n):
        """The label inside its file: `Name`, `Name(ext)#listStyle(_:)`, `Name(ext)#init(_:)#2`."""
        return self.label(n).split('::', 1)[1]

    # ── loading ───────────────────────────────────────────────────────────────────────────────────────────
    @classmethod
    def load(cls, root, source_dir, store, lib=None, module='TUI', modules=None):
        """The model of `source_dir`'s sources. With `modules` (the map's module names), only its directories
        `source_dir/<module>` are read, and a file's label starts with its directory: `TUILists/Views/List.swift`.
        Their index units may name any of those modules (TUIFoundation's units cover all of them until each is
        carved out), or `module`."""
        mine = [d for d in modules if os.path.isdir(os.path.join(root, source_dir, d))] if modules else ['']
        names = {module} | set(modules or ())

        def prefixes(base):
            return tuple(os.path.join(base, source_dir, d).rstrip('/') + '/' for d in mine)
        prefix = os.path.join(os.path.realpath(root), source_dir) + '/'
        files, symbols, mtimes, units = IX.read(store, names, prefixes(os.path.realpath(root)), lib)
        if not files:                    # the store may have recorded the unresolved path
            prefix = os.path.join(root, source_dir) + '/'
            files, symbols, mtimes, units = IX.read(store, names, prefixes(root), lib)
        occ = {p[len(prefix):]: o for p, o in files.items()}
        m = cls()
        m.symbols = symbols
        src = os.path.join(root, source_dir)
        m.files = sorted(os.path.relpath(os.path.join(d, f), src) for top in mine
                         for d, _, fs in os.walk(os.path.join(src, top)) for f in fs if f.endswith('.swift'))
        for f in m.files:
            with open(os.path.join(src, f), encoding='utf-8', errors='replace') as fh:
                m.lexed[f] = SS.lex(fh.read())
        m.stale, m.uncompiled = unit_freshness(
            m.files, {f: _changed(os.path.join(src, f)) for f in m.files},
            {f: mtimes[prefix + f] for f in m.files if prefix + f in mtimes}, max(mtimes.values(), default=None))
        m.target = {f: units[prefix + f] for f in m.files if prefix + f in units}
        m.build({f: o for f, o in occ.items() if f in m.lexed})
        # The lower modules: the package's other modules whose sources sit beside this one's (Sources/TUICore …)
        # and that this module's sources can see, read in one more pass over the store's units. The `lower` check asks
        # which of them defines what a declaration uses. Beside the map's own directories, when it has several.
        if modules:
            top, me = prefix.rstrip('/'), set(modules)
        else:
            top, me = os.path.split(prefix.rstrip('/'))
        dirs = {d: os.path.join(top, d) + '/' for d in sorted(visible_modules(top, me, m.lexed.values()))}
        m.lower_visible = set(dirs)
        m.lower_reexports = reexports_of(dirs)
        if dirs:
            lower, lsyms, _, _ = IX.read(store, set(dirs), tuple(dirs.values()), lib)
            m.lower_owner, m.lower_name = lower_owners(lower, dirs, lsyms)
            m.lower_modules = set(m.lower_owner.values())
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
        first = {}
        public_header, public_defs, bare_defs = set(), collections.defaultdict(list), collections.defaultdict(list)
        for f, occs in occ.items():
            lx = self.lexed.get(f)
            for usr, roles, line, cont in occs:
                if roles & DEF and not roles & REF:
                    if cont in nodeset and parent.get(usr) == cont and not roles & IX.IMPLICIT:
                        k = (line, self.symbols.get(usr, ('?',))[0])
                        if cont not in first or k < first[cont]: first[cont] = k
                    if cont in nodeset and self.symbols.get(usr, ('', 0))[1] in IX.CALLABLE_KINDS:
                        members[cont].add(_ACCESSOR.sub('', self.symbols[usr][0]).split('(')[0])
                    holder = usr if not cont else top(cont)
                    if holder in nodeset and lx and 0 < line < len(lx.stripped):
                        head = lx.stripped[line].split('{')[0]
                        # A member worth naming: a member of the declaration or of a type nested in it. Not the
                        # declaration itself, an accessor, a compiler-made one, nor a parameter, generic parameter or
                        # local of a function, which the index also records on the function's line.
                        s = self.symbols.get(usr, ('', 0, 0))
                        named = usr != holder and not roles & IX.IMPLICIT and not _ACCESSOR.match(s[0]) and \
                            s[1] != IX.K_PARAMETER and s[1:] != (IX.K_TYPEALIAS, IX.SK_GENERIC_PARAMETER) and \
                            self.symbols.get(parent.get(usr), ('', 0))[1] in IX.TYPE_KINDS + (IX.K_EXTENSION,)
                        if _PUBLIC.search(head):
                            self.public.add(holder)
                            if usr == holder: public_header.add(holder)
                            elif named: public_defs[holder].append((line, usr))
                        elif named and parent.get(usr) == holder and not _ACCESS.search(head):
                            bare_defs[holder].append((line, usr))     # public when its extension is
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
        self.first_member = {n: nm for n, (_, nm) in first.items()}
        # The public API each declaration holds, member by member: what `public-above` lists for a block it flags,
        # since a block's label names only its first member. A member with no access modifier of its own is public
        # in a `public extension`.
        for n in public_header:
            if self.kind.get(n) == IX.K_EXTENSION: public_defs[n] += bare_defs.get(n, [])
        for n, defs in public_defs.items():
            listed, names = {u for _, u in defs}, []

            def reachable(u):
                """A public member of a nested type is public API only when every type it sits in is."""
                p, k = parent.get(u), 0
                while p is not None and p != n and k < 50:
                    if p not in listed: return False
                    p, k = parent.get(p), k + 1
                return True
            for _, u in sorted(set(defs)):
                if not reachable(u): continue
                nm = self.symbols.get(u, ('?',))[0]
                if parent.get(u) not in (n, None): nm = f'{self.symbols.get(parent[u], ("?",))[0]}.{nm}'
                if nm not in names: names.append(nm)
            self.public_members[n] = names
        self.conformances = sorted(set(self.conformances), key=lambda c: (c[3], c[4], c[1]))
        conformed = collections.defaultdict(set)
        for _, pr, decl, _, _ in self.conformances: conformed[decl].add(self.symbols.get(pr, ('?',))[0])
        self.conformed = {n: sorted(ps) for n, ps in conformed.items()}

    # ── helpers the assigner and the checks share ────────────────────────────────────────────────────────
    def lower_module(self, usr):
        """The lower module that defines a symbol (TUICore, TUIView …), else None: the index's answer, which
        sees members a lower module adds to SDK types, else the module named by the USR's prefix."""
        m = self.lower_owner.get(usr)
        if m is not None: return m
        for prefix, mod in LOWER_PREFIXES:
            if usr.startswith(prefix) or usr.startswith('s:e:' + prefix): return mod
        return None

    def extended_node(self, n):
        """The node of the module type or protocol an extension node extends, else None."""
        u = self.ext_of.get(n)
        if u is None: return None
        t = self.top(u)
        return t if t in self.file else None
