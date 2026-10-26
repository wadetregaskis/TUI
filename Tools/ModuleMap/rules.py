"""rules.json, loaded: the module DAG, the contents rules, and the module-visibility questions everything asks."""
import json
import re


class Rules:
    def __init__(self, data):
        self.data = data
        self.source = data['source']
        self.default = data['default']
        self.app = data['app']
        self.umbrella = data['umbrella']
        self.order = [m['name'] for m in data['modules']]
        self.deps = {m['name']: list(m['deps']) for m in data['modules']}
        for m, ds in self.deps.items():
            for d in ds:
                if d not in self.deps: raise SystemExit(f'rules.json: {m} depends on unknown module {d}')
        # The lower modules (outside the map: TUICore, TUIView …) each module may use; None, when a module has no
        # `lower` list, is all of them. Which names are real modules is the index's to say (modulemap.py checks it).
        self.lower = {m['name']: (set(m['lower']) if 'lower' in m else None) for m in data['modules']}
        for m, ls in self.lower.items():
            for x in sorted(ls or ()):
                if x in self.deps: raise SystemExit(f'rules.json: {m}\'s lower list names {x}, a module of the map: '
                                                     f'name it in deps')
        self.sees_set = {m: self._closure(m) | {m} for m in self.order}
        for m in self.order:
            if m in self._closure(m): raise SystemExit(f'rules.json: {m} depends on itself')
        # Without a `files` list (rules.json since step A5), every module's files sit in a directory of their own,
        # Sources/<module>, and a file's directory is its module. With one (the research layout, and the unit tests'
        # small maps), the contents rules below seed each file of the one source directory.
        self.by_directory = 'files' not in data
        self.files = [(r['module'], bool(r.get('pin')), re.compile(r['match'])) for r in data.get('files', [])]
        self.decls = [dict(r, rx=re.compile(r['match'])) for r in data.get('declarations', [])]
        self.unpin = [re.compile(r['match']) for r in data.get('unpin', [])]
        self.scheduled = [dict(r, index=i, from_rx=re.compile(r['from']), to_rx=re.compile(r['to']))
                          for i, r in enumerate(data.get('scheduled', []))]
        self.accepted = {(r['check'], r['key']): r for r in data.get('accepted', [])}
        for m, _, _ in self.files: self._known(m, 'files')
        for r in self.decls: self._known(r['module'], 'declarations')
        self.posix = data.get('posix', {})
        self.witness_pairs = {p: set(qs) for p, qs in data.get('witness_pairs', {}).items() if p != 'why'}

    @classmethod
    def load(cls, path):
        with open(path, encoding='utf-8') as fh:
            return cls(json.load(fh))

    def _known(self, m, where):
        if m not in self.deps: raise SystemExit(f'rules.json: unknown module {m} in {where}')

    def _closure(self, m):
        out = set(); st = [m]
        while st:
            for d in self.deps[st.pop()]:
                if d not in out: out.add(d); st.append(d)
        return out

    def sees(self, a, b):
        """Can code in module a use declarations of module b? Modules outside the map (the lower four, the SDK)
        are visible from everywhere."""
        if b not in self.sees_set: return True
        return b in self.sees_set.get(a, {a})

    def rank(self, m):
        return (len(self.sees_set[m]), self.order.index(m))

    def join(self, ms):
        """The lowest module that sees every module in ms."""
        c = [m for m in self.order if all(self.sees(m, x) for x in ms)]
        return min(c, key=self.rank)

    def meet(self, a, b):
        """The highest module both a and b see."""
        return max(self.sees_set[a] & self.sees_set[b], key=self.rank)

    def seed(self, rel):
        """(module, pinned) the contents rules give a file: by directory, the module its path starts with, pinned
        (moving a file is a `git mv`); else the first rule that matches, else the default."""
        if self.by_directory:
            top = rel.split('/', 1)[0]
            return (top, True) if top in self.deps else (self.default, False)
        for m, pin, rx in self.files:
            if rx.search(rel): return m, pin
        return self.default, False

    def decl_rule(self, labels):
        """The `declarations` rule that places a declaration with these labels (`Model.rule_labels`), else None. The
        LAST that matches wins, so a narrower rule after a broader one is an exception to it: the r4 rules pin
        `Image.*Key` to TUIBitmaps, then three of those keys to TUIFoundation. The assigner, `map.json`'s reader and
        `public-above` all ask here, so they cannot disagree."""
        hit = None
        for r in self.decls:
            if any(r['rx'].search(l) for l in labels): hit = r
        return hit

    def scheduled_for(self, check, src_label, dst_label):
        for r in self.scheduled:
            if r['check'] == check and r['from_rx'].search(src_label) and r['to_rx'].search(dst_label):
                return r
        return None
