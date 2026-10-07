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
        self.sees_set = {m: self._closure(m) | {m} for m in self.order}
        for m in self.order:
            if m in self._closure(m): raise SystemExit(f'rules.json: {m} depends on itself')
        self.files = [(r['module'], bool(r.get('pin')), re.compile(r['match'])) for r in data['files']]
        self.decls = [(r['module'], re.compile(r['match'])) for r in data.get('declarations', [])]
        self.unpin = [re.compile(r['match']) for r in data.get('unpin', [])]
        self.scheduled = [dict(r, from_rx=re.compile(r['from']), to_rx=re.compile(r['to']))
                          for r in data.get('scheduled', [])]
        self.accepted = {(r['check'], r['key']): r for r in data.get('accepted', [])}
        for m, _, _ in self.files: self._known(m, 'files')
        for m, _ in self.decls: self._known(m, 'declarations')
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
        """(module, pinned) the contents rules give a file: the first rule that matches, else the default."""
        for m, pin, rx in self.files:
            if rx.search(rel): return m, pin
        return self.default, False

    def scheduled_for(self, check, src_label, dst_label):
        for r in self.scheduled:
            if r['check'] == check and r['from_rx'].search(src_label) and r['to_rx'].search(dst_label):
                return r
        return None
