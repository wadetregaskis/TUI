#!/usr/bin/env python3
"""Fails on a relative Markdown link, or an anchor, that resolves to nothing in the repository.

GitHub renders a link to a moved or renamed document as an ordinary link; the reader finds the
breakage only by following it. The documentation is cross-linked heavily, its file names carry
spaces and parentheses, and agents move and rename files with scripts, so this is the check.

    python3 Tools/validate-markdown-links.py              # every tracked .md file; exit 1 on a finding
    python3 Tools/validate-markdown-links.py FILE ...     # these files only
    python3 Tools/validate-markdown-links.py --self-test  # prove the check bites, on samples below

What it reads: inline links and images, `[text](destination "title")`, and reference definitions,
`[label]: destination`. A destination with a space is written `<like this.md>` (CommonMark's
pointy-bracket form, which GitHub renders); a `%20`-escaped one is decoded too. Fenced code blocks
and code spans are not links and are skipped. A destination with a scheme (`https:`, `mailto:`,
DocC's `doc:`) is not checked, and nor is any file inside a DocC catalogue (`*.docc/`): DocC
resolves those links itself, by name, and `docc convert --warnings-as-errors` checks them.

What resolves: a path, relative to the linking file (or, with a leading `/`, to the repository's
root, as GitHub reads it), naming a TRACKED file or a directory holding one. Tracked, so a link
into the git-ignored `Documentation/Working notes/` fails: nobody else has those files. An anchor,
`#like-this`, must name a heading of the target Markdown file by GitHub's rule (lower-cased; every
character but a letter, a digit, a space, a hyphen or an underscore dropped; spaces to hyphens; a
repeated heading's second slug gains `-1`), or an HTML `id`/`name` in it. An anchor into a file
that is not Markdown (`Package.swift#L10`), and GitHub's line anchor (`#L10`, `#L10-L12`) into any
file, are not checked.
"""
import os
import re
import subprocess
import sys
import unicodedata
from urllib.parse import unquote

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FENCE = re.compile(r'^ {0,3}(`{3,}|~{3,})')
HEADING = re.compile(r'^ {0,3}(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$')
SETEXT = re.compile(r'^ {0,3}(=+|-+)[ \t]*$')
REFERENCE = re.compile(r'^ {0,3}\[(?:[^\]\\]|\\.)+\]:[ \t]*(<[^>\n]*>|\S+)', re.M)
HTML_ID = re.compile(r'<[a-zA-Z][^>]*?\s(?:id|name)\s*=\s*["\']([^"\']+)["\']')
SCHEME = re.compile(r'^[a-zA-Z][a-zA-Z0-9+.-]*:')
LINE_ANCHOR = re.compile(r'^L\d+(-L\d+)?$')


def blank_code(text, spans=True):
    """The text with fenced code blocks (and code spans) blanked to spaces, so offsets and lines still match."""
    out, fence = [], None
    for line in text.split('\n'):
        opened = FENCE.match(line)
        if opened:
            marker = opened.group(1)
            if fence is None:
                fence = marker[0] * 3
            elif marker.startswith(fence):
                fence = None
            out.append(' ' * len(line))
            continue
        out.append(' ' * len(line) if fence else line)
    text = '\n'.join(out)
    if not spans:
        return text
    # A code span: a run of backticks, closed by a run of the same length (CommonMark 6.1).
    return re.sub(r'(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)',
                  lambda m: ' ' * len(m.group(0)), text, flags=re.S)


def destinations(text):
    """(start, end) of every link destination, the pointy brackets included when present."""
    code_free = blank_code(text)
    spans = []
    i = code_free.find('](')
    while i != -1:
        if i == 0 or code_free[i - 1] != '\\':
            j = i + 2
            while j < len(code_free) and code_free[j] in ' \t':
                j += 1
            if j < len(code_free) and code_free[j] == '<':
                end = code_free.find('>', j)
                if end != -1 and '\n' not in code_free[j:end]:
                    spans.append((j, end + 1))
            else:
                depth, k = 0, j
                while k < len(code_free) and not code_free[k].isspace():
                    c = code_free[k]
                    if c == '\\':
                        k += 2
                        continue
                    if c == '(':
                        depth += 1
                    elif c == ')':
                        if depth == 0:
                            break
                        depth -= 1
                    k += 1
                if k > j:
                    spans.append((j, k))
        i = code_free.find('](', i + 2)
    for match in REFERENCE.finditer(code_free):
        spans.append(match.span(1))
    return sorted(spans)


def decode(destination):
    """The path and the anchor a destination names, unescaped."""
    if destination.startswith('<') and destination.endswith('>'):
        destination = destination[1:-1]
    else:
        destination = unquote(destination)
    destination = re.sub(r'\\(.)', r'\1', destination)
    path, _, anchor = destination.partition('#')
    path = path.split('?', 1)[0]
    return path, unquote(anchor)


def slug(heading):
    """GitHub's anchor for a heading's text."""
    text = re.sub(r'!?\[([^\]]*)\]\([^)]*\)', r'\1', heading)  # a link reads as its text
    text = re.sub(r'<[^>]+>', '', text)                         # HTML tags go
    text = text.replace('`', '').strip().lower()
    kept = ''.join(c for c in text
                   if c in ' -_' or unicodedata.category(c)[0] in 'LMN')
    return kept.replace(' ', '-')


def without_emphasis(heading):
    """The heading with `_emphasis_` markers removed outside code spans: inside one, `_OpacityView` keeps its
    underscore, as GitHub's slug does."""
    parts = re.split(r'(`[^`]*`)', heading)
    return ''.join(part if part.startswith('`') and part.endswith('`') and len(part) > 1
                   else re.sub(r'(?<!\w)_{1,3}(?=\S)|(?<=\S)_{1,3}(?!\w)', '', part)
                   for part in parts)


def anchors(text):
    """Every anchor a Markdown file offers: its headings' slugs (repeats numbered) and HTML ids."""
    found, seen = set(), {}
    lines = blank_code(text, spans=False).split('\n')
    for n, line in enumerate(lines):
        match = HEADING.match(line)
        heading = match.group(2) if match else None
        if heading is None and n + 1 < len(lines) and SETEXT.match(lines[n + 1]) and line.strip() \
                and not line.lstrip().startswith(('|', '-', '*', '>')):
            heading = line.strip()
        if heading is None:
            continue
        base = slug(without_emphasis(heading))
        count = seen.get(base, 0)
        seen[base] = count + 1
        found.add(base if count == 0 else f'{base}-{count}')
    found.update(a.lower() for a in HTML_ID.findall(text))
    return found


class Repository:
    def __init__(self, files):
        self.files = set(files)
        self.directories = {''}
        for path in files:
            parent = os.path.dirname(path)
            while parent not in self.directories:
                self.directories.add(parent)
                parent = os.path.dirname(parent)
        self.anchor_cache = {}

    def anchors(self, path):
        if path not in self.anchor_cache:
            with open(os.path.join(ROOT, path), encoding='utf-8') as fh:
                self.anchor_cache[path] = anchors(fh.read())
        return self.anchor_cache[path]


def problems(source, text, repository, read_target=None):
    """(line, destination, why) for every link in `source` (a repository path) that resolves to nothing."""
    found = []
    for start, end in destinations(text):
        raw = text[start:end]
        if SCHEME.match(raw.lstrip('<')):
            continue
        path, anchor = decode(raw)
        line = text.count('\n', 0, start) + 1
        if path:
            base = '' if path.startswith('/') else os.path.dirname(source)
            target = os.path.normpath(os.path.join(base, path.lstrip('/'))).replace(os.sep, '/')
            if target == '.':
                target = ''
            if target.startswith('../'):
                found.append((line, raw, 'leaves the repository'))
                continue
            if target not in repository.files and target not in repository.directories:
                found.append((line, raw, 'no tracked file or directory there'))
                continue
        else:
            target = source
        if anchor and target.endswith('.md') and target in repository.files and not LINE_ANCHOR.match(anchor):
            offered = read_target(target) if read_target else repository.anchors(target)
            if anchor.lower() not in offered:
                found.append((line, raw, f'no heading or id "{anchor}" in {target}'))
    return found


def tracked(pattern=None):
    command = ['git', '-C', ROOT, 'ls-files', '-z']
    if pattern:
        command += ['--', pattern]
    out = subprocess.run(command, check=True, capture_output=True, text=True).stdout
    return [path for path in out.split('\0') if path]


def checked(path):
    return path.endswith('.md') and not any(part.endswith('.docc') for part in path.split('/'))


def check(paths):
    repository = Repository(tracked())
    total = 0
    for path in paths:
        if not checked(path):
            continue
        with open(os.path.join(ROOT, path), encoding='utf-8') as fh:
            text = fh.read()
        for line, raw, why in problems(path, text, repository):
            total += 1
            print(f'{path}:{line}: ({raw}) {why}')
    if total:
        print(f'{total} Markdown link(s) resolve to nothing', file=sys.stderr)
    return 1 if total else 0


# (name, Markdown in `docs/a.md`, the destinations the check must report)
SAMPLES = [
    ('a sibling that exists', '[b](b.md) and [c](<c d.md>)', []),
    ('a sibling that does not', '[x](missing.md)', ['missing.md']),
    ('a space, escaped either way', '[c](c%20d.md) [c](<c d.md#a-heading>)', []),
    ('a space without pointy brackets is no destination GitHub reads', '[c](c d.md)', ['c']),
    ('a parent directory, and parentheses in a name', '[r](../README.md) [p](<../p (x).md>)', []),
    ('an anchor that names a heading', '[h](<c d.md#a-heading>) [t](#title-here)', []),
    ('an anchor that names nothing', '[h](<c d.md#no-such-heading>)', ['<c d.md#no-such-heading>']),
    ('a repeated heading numbers its second slug', '[r](<c d.md#repeat-1>)', []),
    ('a heading with code and punctuation', '[k](<c d.md#b-x1-1-update-writes-back>)', []),
    ('a line anchor is GitHub\'s, not a heading', '[l](<c d.md#L2-L3>) [m](b.md#L9)', []),
    ('a link in a code span or a fence is code',
     '`[x](missing.md)`\n```\n[y](missing.md)\n```', []),
    ('a URL and a DocC link are not checked', '[u](https://example.com/x.md) [d](doc:Thing)', []),
    ('a directory with tracked files resolves', '[d](sub/) [e](sub)', []),
    ('an untracked directory does not', '[w](<Working notes/x.md>)', ['<Working notes/x.md>']),
    ('a reference definition', '[ref]: missing.md\n[ok]: <c d.md>', ['missing.md']),
    ('out of the repository', '[o](../../outside.md)', ['../../outside.md']),
    ('a leading underscore inside code stays in the slug', '[o](<c d.md#c-1-_opacityview-stays>)', []),
    ('emphasis underscores outside code go', '[e](<c d.md#emphasised-word>)', []),
]
SAMPLE_FILES = {
    'docs/a.md': '# Title here\n',
    'docs/b.md': '',
    'docs/c d.md': '# A heading\n## Repeat\n## Repeat\n### B-X1-1. `update()` writes back\n'
                   '### C-1. `_OpacityView` stays\n## _Emphasised_ word\n',
    'docs/sub/x.md': '',
    'README.md': '',
    'p (x).md': '',
}


def self_test():
    repository = Repository(SAMPLE_FILES)

    def read(path):
        return anchors(SAMPLE_FILES[path])
    failures = 0
    for name, text, expected in SAMPLES:
        got = [raw for _, raw, _ in problems('docs/a.md', text, repository, read)]
        if got != expected:
            failures += 1
            print(f'FAIL {name}: reported {got}, expected {expected}')
    if failures:
        print(f'{failures} self-test failure(s)', file=sys.stderr)
        return 1
    print(f'self-test passed: {len(SAMPLES)} samples, each reported exactly where it should be')
    return 0


if __name__ == '__main__':
    args = sys.argv[1:]
    if args == ['--self-test']:
        sys.exit(self_test())
    if args:
        sys.exit(check([os.path.relpath(os.path.abspath(a), ROOT) for a in args]))
    sys.exit(check(tracked('*.md')))
