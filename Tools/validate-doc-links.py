#!/usr/bin/env python3
"""Fails on a DocC link that the strict documentation build would report, found from the source alone.

The only other check is CI's `Tools/BuildDocs/build-docs.sh --strict`: minutes, a fresh clone, and a
symbol-graph dump of every target. Nothing in the local gate saw a broken doc link, so they reached
main three times (659 warnings 2026-08-04, 435 on 2026-09-08, 9 on 2026-11-20). This catches the kinds
those were made of in a few seconds, without a build. The strict build stays the authority: what this
cannot decide with confidence it passes, so a clean run here is not a promise that build is clean.

    python3 Tools/validate-doc-links.py              # every documented module and the DocC catalogue
    python3 Tools/validate-doc-links.py FILE ...     # these files only (declarations come from the tree)
    python3 Tools/validate-doc-links.py --self-test  # prove the check bites, on samples below

What it reads: the `///` doc comments of PUBLIC declarations in the modules the archive documents
(`MODULES` in `Tools/BuildDocs/unify_symbol_graphs.py`), and every article in a DocC catalogue
(`Sources/**/*.docc/**/*.md`). An internal declaration's doc is not in the archive, so DocC never
reads its links, and neither does this; nor does it read the docs DocC reads without reporting
their links (`Index.diagnosed` says which, as measured). Fenced code is skipped.

Proven on the nine links 0873ff879 fixed (c66dfe72c's copies of those three files): it reports
those nine and not the tenth line that commit changed, a `package` property's doc the strict build
did not report either. On 0873ff879 itself it reports nothing, as the strict build does.

What it reports:

1. A symbol link (``…``) qualified by a module other than `TUI`: ``Foundation/AttributedString/x``,
   ``Swift/String/x``, ``SwiftUI/View/x``, ``TUIView/View/x``. The archive is one module, `TUI`
   (unify_symbol_graphs.py renames every graph into it, extension graphs of other modules' types
   included), so TUI's extension members of `AttributedString` live at ``AttributedString/x`` and
   there is no Foundation, Swift or TUIView page to resolve against.
2. A symbol link to a name the archive cannot have a page for: one the sources declare only
   `internal`, `private`, `fileprivate` or `package`, only under `@_spi` or
   `@_documentation(visibility:)`, only inside a non-public type, or only with a leading underscore
   (DocC leaves those out even when public). For ``A/b``, `b` is looked up among the members of `A`
   (and its extensions); a member not declared there (inherited, synthesised) is not judged.
3. A symbol link to a function, initialiser, subscript or enum case whose labels match no public
   declaration of that name anywhere: a signature that moved, or a defaulted parameter left out of the
   link (DocC's name counts every parameter).
4. A symbol link whose first name nothing in the documented modules declares or extends: a typo, a
   rename, or another module's type (``Int``, which TUI does not extend), none of which has a page.
5. A `<doc:Article>` link to no article of the catalogue and no declared name, and a
   `<doc:Article#Heading>` whose heading is not in that article; an `@Image(source:)` that names no
   file in the catalogue.

Conservative by design: a member the sources do not declare where the link looks for it (inherited
from a protocol, synthesised by the compiler) is not judged, a link with an operator is skipped, and
a hash disambiguator (`-5m1ib`) is not checked, only the name and labels before it.
"""
import os
import re
import subprocess
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'Tools', 'BuildDocs'))
from unify_symbol_graphs import MODULES, UMBRELLA  # noqa: E402  (the archive's own list, not a copy)

# Modules whose names cannot root a link into the archive. TUI's own other modules are added from
# Sources/ at run time.
EXTERNAL_MODULES = {
    'Swift', 'Foundation', 'FoundationEssentials', 'FoundationInternationalization', 'SwiftUI',
    'SwiftUICore', 'AppKit', 'UIKit', 'Combine', 'Observation', 'Dispatch', 'Darwin', 'Glibc', 'Musl',
    'WinSDK', 'CoreGraphics', 'CoreText', 'CoreFoundation', 'CoreImage', 'ImageIO', 'os',
    'Synchronization', 'RegexBuilder', '_Concurrency', '_StringProcessing', 'XCTest', 'Testing',
    'UniformTypeIdentifiers', 'AVFoundation', 'Accelerate', 'simd', 'System', 'SystemPackage',
    'Charts', 'SwiftData', 'Cocoa',
}

# Members implementing a standard protocol's requirement, whose own doc DocC drops for the protocol's.
INHERITED_DOCS = {'description', 'debugDescription', 'hash'}

ACCESS = r'(?:public|open|private|fileprivate|internal|package)(?:\(set\))?'
MODIFIER = (r'(?:' + ACCESS + r'|static|class|final|override|mutating|nonmutating|lazy|weak|'
            r'unowned(?:\(\w+\))?|dynamic|optional|required|convenience|indirect|'
            r'nonisolated(?:\(unsafe\))?|isolated|consuming|borrowing|distributed|prefix|postfix|'
            r'infix|__consuming|sending)')
ATTRIBUTE = r'@[\w.]+(?:<[^<>]*(?:<[^<>]*>[^<>]*)*>)?(?:\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\))?'
DECL = re.compile(r'^(?P<attrs>(?:' + ATTRIBUTE + r'\s*)*)(?P<mods>(?:' + MODIFIER + r'\s+)*)'
                  r'(?P<kw>struct|class|enum|protocol|extension|actor|func|init|deinit|var|let|'
                  r'subscript|case|typealias|associatedtype|macro)(?![\w])(?P<rest>.*)$')
ATTRIBUTE_ONLY = re.compile(r'^(?:' + ATTRIBUTE + r'\s*)+$')
TYPE_KINDS = {'struct', 'class', 'enum', 'protocol', 'actor', 'extension'}
CALLABLE_KINDS = {'func', 'init', 'subscript', 'case', 'macro'}
STRING = re.compile(r'"(?:[^"\\]|\\.)*"')
IDENT = r'`?[A-Za-z_][A-Za-z0-9_]*`?'
FENCE = re.compile(r'^\s*(`{3,}|~{3,})')
SYMBOL_LINK = re.compile(r'(?<!`)``([^`\s][^`]*?)``(?!`)')
DOC_LINK = re.compile(r'<doc:([^>#\s]+)(?:#([^>\s]*))?>')
IMAGE = re.compile(r'@Image\(\s*source:\s*"([^"]+)"')
COMPONENT = re.compile(r'^(?P<name>[A-Za-z_][A-Za-z0-9_]*)[?!]?(?:\((?P<labels>(?:[A-Za-z0-9_]+:)*)\))?'
                       r'(?:-.*)?$')


class Decl:
    __slots__ = ('name', 'kind', 'labels', 'context', 'access', 'hidden', 'parent', 'path', 'line',
                 'public', 'has_public_member', 'extended')

    def __init__(self, name, kind, labels, access, hidden, parent, path, line):
        self.name, self.kind, self.labels = name, kind, labels
        self.access, self.hidden, self.parent = access, hidden, parent
        self.path, self.line = path, line
        self.public = None
        self.has_public_member = False
        # A type declaration's member scope: its own name, or for an extension the extended path.
        self.extended = None
        self.context = parent.scope() if parent else ()

    def scope(self):
        if self.kind == 'extension':
            return tuple(self.extended)
        if self.kind in TYPE_KINDS:
            return self.context + (self.name,)
        return ('<code>',)

    def where(self):
        return f'{self.path}:{self.line}'


def strip_backticks(name):
    return name.strip('`')


def balanced_from(lines, start, text, opener='(', closer=')'):
    """The text from the first `opener` in `text` to its matching `closer`, reading further lines if needed."""
    i = text.find(opener)
    if i < 0:
        return None
    buffer, depth, k, n = text[i:], 0, start, 0
    while True:
        for j, c in enumerate(buffer[n:], n):
            if c == opener:
                depth += 1
            elif c == closer:
                depth -= 1
                if depth == 0:
                    return buffer[1:j]
        n = len(buffer)
        k += 1
        if k >= len(lines) or k > start + 60:
            return None
        buffer += ' ' + STRING.sub('""', lines[k].split('//')[0])


def split_top(text):
    """`text` split at commas outside (), [], <> and string literals."""
    text = STRING.sub('""', text).replace('->', '→')
    parts, depth, current = [], 0, ''
    for c in text:
        if c in '([<{':
            depth += 1
        elif c in ')]>}':
            depth -= 1
        if c == ',' and depth == 0:
            parts.append(current)
            current = ''
        else:
            current += c
    if current.strip():
        parts.append(current)
    return parts


def parameter_labels(params, subscript=False):
    labels = []
    for param in split_top(params):
        param = re.sub(r'^\s*(?:' + ATTRIBUTE + r'\s*)*', '', param)
        colon = top_level_colon(param)
        if colon < 0:
            labels.append('_')   # an enum case's unlabelled associated value
            continue
        head = param[:colon].split()
        if not head:
            continue
        if subscript and len(head) == 1:
            labels.append('_')
        else:
            labels.append(strip_backticks(head[0]))
    return tuple(labels)


def top_level_colon(text):
    depth = 0
    for i, c in enumerate(text):
        if c in '([<{':
            depth += 1
        elif c in ')]>}':
            depth -= 1
        elif c == ':' and depth == 0:
            return i
    return -1


def skip_generics(rest):
    rest = rest.lstrip()
    if not rest.startswith('<'):
        return rest
    depth = 0
    for i, c in enumerate(rest.replace('->', '→')):
        if c == '<':
            depth += 1
        elif c == '>':
            depth -= 1
            if depth == 0:
                return rest[i + 1:]
    return ''


def code_lines(text):
    """(line index, indent, code) for each line of Swift code, and (line index, doc text) for each `///` line.

    Multi-line string literals and block comments are skipped; a line's trailing `//` comment is kept
    (the declaration pattern stops before it anyway)."""
    out = []
    in_string = in_comment = False
    for index, raw in enumerate(text.split('\n')):
        stripped = raw.strip()
        if in_comment:
            if '*/' in raw:
                in_comment = False
            continue
        if in_string:
            if raw.count('"""') % 2 == 1:
                in_string = False
            continue
        if stripped.startswith('///'):
            out.append((index, None, stripped[3:]))
            continue
        if stripped.startswith('//') or not stripped:
            out.append((index, -1, ''))
            continue
        code = STRING.sub('""', raw.replace('"""', '\x00'))
        if code.count('\x00') % 2 == 1:
            in_string = True
        if '/*' in code and '*/' not in code[code.index('/*'):]:
            in_comment = True
        indent = len(raw) - len(raw.lstrip(' \t'))
        out.append((index, indent, stripped))
    return out


class Source:
    """One Swift file's declarations and the doc blocks attached to them."""

    def __init__(self, path, text):
        self.path = path
        self.decls = []
        self.docs = []           # (Decl, [(line number, text)])
        lines = text.split('\n')
        stack = []               # (indent, Decl)
        doc, attrs, pending_attr = [], '', None
        for index, indent, code in code_lines(text):
            if indent is None:
                doc.append((index + 1, code))
                continue
            if indent == -1:
                if code == '':
                    doc, attrs = [], ''   # a blank or `//` line detaches a doc comment
                continue
            if pending_attr is not None:
                pending_attr += ' ' + code
                if pending_attr.count('(') <= pending_attr.count(')'):
                    attrs += ' ' + pending_attr
                    pending_attr = None
                continue
            if ATTRIBUTE_ONLY.match(code):
                attrs += ' ' + code
                continue
            if code.startswith('@') and code.count('(') > code.count(')') and not DECL.match(code):
                pending_attr = code
                continue
            match = DECL.match(code)
            if not match:
                doc, attrs = [], ''
                continue
            while stack and stack[-1][0] >= indent:
                stack.pop()
            parent = stack[-1][1] if stack else None
            for decl in self.declare(match, attrs, parent, lines, index):
                self.decls.append(decl)
                if doc:
                    self.docs.append((decl, doc))
                    doc = []
                stack.append((indent, decl))
            doc, attrs = [], ''

    def declare(self, match, attrs, parent, lines, index):
        kw, rest = match.group('kw'), match.group('rest')
        mods = match.group('mods').split()
        attrs = attrs + ' ' + match.group('attrs')
        access = None
        for m in mods:
            word = m.split('(')[0]
            if word in ('public', 'open') and '(set)' not in m:
                access = 'public'
            elif word in ('private', 'fileprivate', 'internal', 'package') and '(set)' not in m:
                access = word
        hidden = bool(re.search(r'@_spi\b|@_documentation\s*\(\s*visibility', attrs))
        local = parent is not None and parent.scope() == ('<code>',)
        if local:
            return []

        def make(name, labels=None):
            return Decl(name, kw, labels, access, hidden, parent, self.path, index + 1)

        if kw == 'case':
            if parent is None or parent.kind not in ('enum', 'extension'):
                return []
            names = []
            for item in split_top(rest):
                found = re.match(r'\s*(' + IDENT + r')\s*(\(.*\))?', item)
                if found:
                    labels = parameter_labels(found.group(2)[1:-1]) if found.group(2) else None
                    names.append(make(strip_backticks(found.group(1)), labels))
            return names
        if kw in ('init', 'subscript'):
            after = skip_generics(rest.lstrip('?!'))
            params = balanced_from(lines, index, after) if after.lstrip().startswith('(') else None
            return [make(kw, parameter_labels(params, kw == 'subscript') if params is not None else None)]
        if kw == 'deinit':
            return [make('deinit')]
        if kw == 'extension':
            found = re.match(r'\s+([\w.`]+)', rest)
            if not found:
                return []
            decl = make(strip_backticks(found.group(1).split('.')[-1]))
            decl.extended = tuple(strip_backticks(p) for p in found.group(1).split('.'))
            return [decl]
        if kw == 'func':
            found = re.match(r'\s+(' + IDENT + r'|[^\s(<\w]+)', rest)
            if not found:
                return []
            name = strip_backticks(found.group(1))
            after = skip_generics(rest[found.end():])
            params = balanced_from(lines, index, after) if after.lstrip().startswith('(') else None
            return [make(name, parameter_labels(params) if params is not None else None)]
        found = re.match(r'\s+(' + IDENT + r')', rest)
        if not found:
            return []
        name = strip_backticks(found.group(1))
        labels = None
        if kw == 'macro':
            params = balanced_from(lines, index, skip_generics(rest[found.end():]))
            labels = parameter_labels(params) if params is not None else None
        return [make(name, labels)]


class Index:
    """Every declaration of the documented modules, by name, with whether the archive has a page for it."""

    def __init__(self, sources):
        self.by_name = defaultdict(list)
        self.members = defaultdict(list)     # (scope's last name, member name) → decls
        decls = [d for s in sources for d in s.decls]
        for d in decls:
            self.by_name[d.name].append(d)
            if d.kind == 'extension':
                for outer in d.extended[:-1]:      # `extension Unicode.Scalar` names `Unicode` too
                    self.by_name[outer].append(d)
        types = defaultdict(list)
        for d in decls:
            if d.kind in TYPE_KINDS - {'extension'} or d.kind == 'typealias':
                types[d.name].append(d)
        self.types = types
        self.requirements = {(d.parent.name, d.name, d.labels) for d in decls
                             if d.parent is not None and d.parent.kind == 'protocol'}
        for d in decls:
            self.resolve(d)
        for d in decls:
            if d.public and d.parent is not None and d.parent.kind == 'extension':
                d.parent.has_public_member = True
            if d.context:
                self.members[(d.context[-1], d.name)].append(d)

    def resolve(self, d):
        if d.public is not None:
            return d.public
        d.public = False          # guards a cycle while resolving
        parent = d.parent
        if d.hidden or d.name.startswith('_') or d.access in ('private', 'fileprivate', 'internal', 'package'):
            result = False
        elif parent is None:
            result = d.access == 'public' or (d.kind == 'extension' and d.access is None)
        else:
            parent_public = self.resolve(parent)
            if not parent_public:
                result = False
            elif d.access == 'public':
                result = True
            elif parent.kind == 'protocol':
                result = d.kind not in TYPE_KINDS
            elif d.kind == 'case' and parent.kind == 'enum':
                result = True
            elif parent.kind == 'extension' and parent.access == 'public':
                result = True
            elif d.kind == 'extension':
                result = d.access is None
            else:
                result = False
        if result and d.kind == 'extension':
            # An extension of a type the sources declare only non-public is no public context.
            declared = self.types.get(d.extended[-1], [])
            if declared and not any(self.resolve(t) for t in declared):
                result = False
        d.public = result
        return result

    def diagnosed(self, d):
        """Whether DocC reports a bad link in this public declaration's doc. Measured 2026-11-20 by planting a
        bad link in one symbol of each shape (Xcode 26's docc): it does not for a member of an extension of a
        type the documented modules do not declare (`Character`, `String`, `Optional`), for a protocol
        extension's default implementation of that protocol's requirement, or for an operator or a standard
        protocol's `description` (its page says "Inherited from CustomStringConvertible.description" and drops
        the doc). It does for everything else tried: a type's members, initialisers, extensions of TUI's own
        types from another module, and `View`'s modifiers."""
        if d.parent is not None and (not re.match(r'[A-Za-z_]', d.name) or d.name in INHERITED_DOCS):
            return False
        ancestor = d.parent
        while ancestor is not None:
            if ancestor.kind == 'extension':
                if ancestor.extended[0] not in self.types:
                    return False
                if ancestor is d.parent and (ancestor.extended[-1], d.name, d.labels) in self.requirements:
                    return False
            ancestor = ancestor.parent
        return True

    def page_exists(self, decls):
        return any(d.public and (d.kind != 'extension' or d.has_public_member) for d in decls)


def doc_lines(block):
    """The doc block's lines outside fenced code."""
    fence = None
    for number, text in block:
        opened = FENCE.match(text)
        if opened:
            marker = opened.group(1)[0] * 3
            if fence is None:
                fence = marker
            elif opened.group(1).startswith(fence):
                fence = None
            continue
        if fence is None:
            yield number, text


class Checker:
    def __init__(self, sources, catalogue):
        self.index = Index(sources)
        self.articles = {}       # name → set of normalised headings
        self.resources = set()
        for path, text in catalogue.items():
            name = os.path.basename(path)
            if path.endswith('.md'):
                headings = {normalise(h) for h in re.findall(r'^#{1,6}\s+(.*?)\s*#*\s*$', text, re.M)}
                self.articles[name[:-3]] = headings
            else:
                self.resources.add(name)
                self.resources.add(os.path.splitext(name)[0])
        self.modules = (EXTERNAL_MODULES | MODULE_NAMES) - {UMBRELLA}

    def symbol(self, link):
        """Why ``link`` cannot resolve in the archive, or None."""
        if re.search(r'[^\w/():\-?!.`]', link.split('-', 1)[0]) or link.startswith('/'):
            return None   # an operator, or a path DocC reads otherwise: not judged
        parts = link.split('/')
        if parts[0] in self.modules and not self.index.page_exists(self.index.by_name.get(parts[0], [])):
            return f'qualified by the module {parts[0]}, which the archive (one module, TUI) has no page for'
        if parts[0] == UMBRELLA:
            parts = parts[1:]
        if not parts or not parts[0]:
            return None
        previous = None
        for k, part in enumerate(parts):
            match = COMPONENT.match(part)
            if not match:
                return None
            name, labels = match.group('name'), match.group('labels')
            if k == 0:
                decls = self.index.by_name.get(name, [])
            else:
                decls = self.index.members.get((previous, name), [])
            if not decls:
                if k == 0:
                    return (f'{name} names nothing the documented modules declare or extend '
                            '(a typo, a rename, or a type of another module)')
                return None
            if not self.index.page_exists(decls):
                d = decls[0]
                return f'{name} is not public ({hidden_because(d)}, {d.where()}): no page exists; use a code span'
            if labels is not None:
                wanted = tuple(labels[:-1].split(':')) if labels else ()
                every = self.index.by_name.get(name, [])
                callables = [d for d in every if d.labels is not None]
                if callables and not any(d.public and d.labels == wanted for d in every) and \
                        not any(d.labels is None and d.kind in CALLABLE_KINDS for d in every):
                    offered = sorted({f'{name}(' + ''.join(f'{x}:' for x in d.labels) + ')'
                                      for d in callables if d.public})
                    if not offered:
                        return None
                    return f'no public {name} takes these labels; declared: {", ".join(offered[:4])}'
            previous = name
        return None

    def doc(self, target, fragment):
        if target.startswith('/') or '/' in target or '(' in target:
            return None   # a symbol path through doc:, judged by the symbol check's terms elsewhere
        if target in self.articles:
            if fragment and normalise(fragment) not in self.articles[target]:
                return f'no heading "{fragment}" in the article {target}'
            return None
        if self.index.by_name.get(target):
            return None
        return 'no article of that name in the catalogue, and no declaration'

    def text(self, lines):
        """(line, link, why) for each bad link in these (line number, text) pairs."""
        found = []
        for number, text in lines:
            for match in SYMBOL_LINK.finditer(text):
                why = self.symbol(match.group(1))
                if why:
                    found.append((number, f'``{match.group(1)}``', why))
            for match in DOC_LINK.finditer(text):
                why = self.doc(match.group(1), match.group(2))
                if why:
                    found.append((number, match.group(0), why))
            for match in IMAGE.finditer(text):
                if match.group(1) not in self.resources:
                    found.append((number, match.group(0) + ')', 'no such file in the catalogue'))
        return found

    def swift(self, source):
        found = []
        for decl, block in source.docs:
            if decl.public and decl.kind != 'extension' and self.index.diagnosed(decl):
                found += self.text(doc_lines(block))
        return found

    def article(self, text):
        lines = text.split('\n')
        return self.text(doc_lines(list(enumerate(lines, 1))))


def hidden_because(d):
    if d.name.startswith('_'):
        return 'underscored'
    if d.hidden:
        return '@_spi or @_documentation'
    if d.access in ('private', 'fileprivate', 'internal', 'package'):
        return d.access
    if d.parent is not None and not d.parent.public:
        return f'inside {d.parent.kind} {d.parent.name}, which is not public'
    return 'internal'


def normalise(heading):
    heading = re.sub(r'``?([^`]*)``?', r'\1', heading)
    return re.sub(r'[^0-9a-z]', '', heading.lower())


MODULE_NAMES = set()


def tracked():
    out = subprocess.run(['git', '-C', ROOT, 'ls-files', '-z', '--', 'Sources'],
                         check=True, capture_output=True, text=True).stdout
    return [p for p in out.split('\0') if p]


def in_catalogue(path):
    return any(part.endswith('.docc') for part in path.replace(os.sep, '/').split('/')[:-1])


def read(path):
    with open(os.path.join(ROOT, path), encoding='utf-8') as fh:
        return fh.read()


def check(arguments):
    files = tracked()
    MODULE_NAMES.update(p.split('/')[1] for p in files if p.count('/') >= 2)
    documented = [p for p in files if p.endswith('.swift') and p.split('/')[1] in MODULES]
    sources = {p: Source(p, read(p)) for p in documented}
    if arguments:
        targets = [os.path.relpath(os.path.abspath(a), ROOT) for a in arguments]
        # A given file outside the documented modules (an old copy, say) joins the declarations it is judged by.
        for path in targets:
            if path.endswith('.swift') and path not in sources:
                sources[path] = Source(path, read(path))
    else:
        targets = None
    catalogue = {p: (read(p) if p.endswith('.md') else '') for p in files if in_catalogue(p)}
    checker = Checker(sources.values(), catalogue)
    if targets is None:
        targets = documented + sorted(p for p in catalogue if p.endswith('.md'))
    total = 0
    for path in targets:
        if path.endswith('.swift'):
            found = checker.swift(sources[path])
        elif path.endswith('.md') and in_catalogue(path):
            found = checker.article(catalogue[path] if path in catalogue else read(path))
        else:
            continue
        for line, link, why in found:
            total += 1
            print(f'{path}:{line}: {link} {why}')
    if total:
        print(f'{total} doc link(s) the strict DocC build would report '
              '(Tools/BuildDocs/build-docs.sh --strict is the authority)', file=sys.stderr)
    return 1 if total else 0


# (name, Swift source, the links the check must report). Every sample is checked against SAMPLE_TREE too.
SAMPLE_TREE = '''
public struct Shown {
    public var visible: Int
    var hidden: Int
    public func act(on value: Int, with other: Int = 0) {}
    public init(_ value: Int) {}
}
struct Internal {
    public var looksPublic: Int
}
package func packaged(context: Int) {}
public struct _Underscored {}
@_spi(Testing) public func spied() {}
public enum Choice {
    case one, two(count: Int)
}
public extension AttributedString {
    func transform(updating selection: inout Int, body: () -> Void) {}
}
extension Shown {
    func internalMember() {}
}
public protocol Provider {
    func provide()
}
'''
SAMPLES = [
    ('links to public symbols resolve',
     '/// ``Shown``, ``Shown/visible``, ``Shown/act(on:with:)``, ``Shown/init(_:)``, ``Choice/two(count:)``\n'
     'public func a() {}', []),
    ('an external module qualifier fails; the bare path does not',
     '/// ``Foundation/AttributedString/transform(updating:body:)`` and\n'
     '/// ``AttributedString/transform(updating:body:)``, ``TUI/Shown``\npublic func b() {}',
     ['``Foundation/AttributedString/transform(updating:body:)``']),
    ('one of TUI\'s own modules qualifies nothing either', '/// ``TUIView/Shown``\npublic func c() {}',
     ['``TUIView/Shown``']),
    ('non-public names fail',
     '/// ``Internal``, ``packaged(context:)``, ``_Underscored``, ``spied()``, ``Internal/looksPublic``\n'
     'public func d() {}',
     ['``Internal``', '``packaged(context:)``', '``_Underscored``', '``spied()``', '``Internal/looksPublic``']),
    ('a non-public member of a public type fails', '/// ``Shown/hidden`` ``Shown/internalMember()``\npublic var e = 0',
     ['``Shown/hidden``', '``Shown/internalMember()``']),
    ('labels that match no declaration fail (a defaulted parameter counts)',
     '/// ``Shown/act(on:)`` ``Choice/two(_:)``\npublic func f() {}', ['``Shown/act(on:)``', '``Choice/two(_:)``']),
    ('a member the sources never declare is not judged; a name nothing declares or extends is',
     '/// ``AttributedString/count`` ``Int``\npublic func g() {}', ['``Int``']),
    ('an internal declaration\'s doc is not in the archive', '/// ``Internal`` ``Foundation/Data``\nfunc h() {}', []),
    ('nor is a public member of an internal type\'s',
     'struct Box {\n    /// ``Internal``\n    public var i = 0\n}', []),
    ('a public member of a public extension is checked',
     'public extension Shown {\n    /// ``Internal``\n    var j: Int { 0 }\n}', ['``Internal``']),
    ('a blank line detaches a doc comment', '/// ``Internal``\n\npublic func k() {}', []),
    ('fenced code in a doc is code', '/// ```\n/// ``Internal``\n/// ```\npublic func l() {}', []),
    ('attributes between the doc and the declaration keep it attached',
     '/// ``Internal``\n@MainActor\n@available(*, deprecated,\n    message: "x")\npublic func m() {}', ['``Internal``']),
    ('an @_spi declaration\'s doc is not in the archive', '/// ``Internal``\n@_spi(X) public func n() {}', []),
    ('DocC does not diagnose a member of an extension of another module\'s type',
     'extension Character {\n    /// ``Internal``\n    public var x: Int { 0 }\n}', []),
    ('nor a default implementation of a requirement; a protocol extension\'s other members it does',
     'extension Provider {\n    /// ``Internal``\n    public func provide() {}\n    /// ``Internal``\n'
     '    public func other() {}\n}', ['``Internal``']),
    ('nor an operator, nor a standard protocol\'s description',
     'extension Shown {\n    /// ``Internal``\n    public static func == (a: Shown, b: Shown) -> Bool { true }\n'
     '    /// ``Internal``\n    public var description: String { "" }\n}', []),
    ('doc links name articles and their headings',
     '/// <doc:Guide> <doc:Guide#Getting-Started> <doc:Missing> <doc:Guide#Nowhere> <doc:Shown>\npublic func o() {}',
     ['<doc:Missing>', '<doc:Guide#Nowhere>']),
]
SAMPLE_CATALOGUE = {'Sources/TUI/TUI.docc/Articles/Guide.md': '# Guide\n\n## Getting Started\n',
                    'Sources/TUI/TUI.docc/Resources/flow.svg': ''}
SAMPLE_ARTICLE = ('# ``TUI``\n\n- ``Shown``\n- ``Internal``\n- <doc:Guide>\n\n```swift\n``Internal``\n```\n'
                  '@Image(source: "flow.svg", alt: "x")\n@Image(source: "gone.svg", alt: "x")\n')


def self_test():
    MODULE_NAMES.update({'TUIView', 'TUI'})
    failures = 0
    for name, text, expected in SAMPLES:
        tree = Source('Sources/TUIView/Tree.swift', SAMPLE_TREE)
        sample = Source('Sources/TUIView/Sample.swift', text)
        checker = Checker([tree, sample], SAMPLE_CATALOGUE)
        got = [link for _, link, _ in checker.swift(sample)]
        if got != expected:
            failures += 1
            print(f'FAIL {name}: reported {got}, expected {expected}')
    checker = Checker([Source('Sources/TUIView/Tree.swift', SAMPLE_TREE)], SAMPLE_CATALOGUE)
    got = [link for _, link, _ in checker.article(SAMPLE_ARTICLE)]
    expected = ['``Internal``', '@Image(source: "gone.svg")']
    if got != expected:
        failures += 1
        print(f'FAIL an article: reported {got}, expected {expected}')
    if failures:
        print(f'{failures} self-test failure(s)', file=sys.stderr)
        return 1
    print(f'self-test passed: {len(SAMPLES) + 1} samples, each reported exactly where it should be')
    return 0


if __name__ == '__main__':
    args = sys.argv[1:]
    if args == ['--self-test']:
        sys.exit(self_test())
    sys.exit(check(args))
