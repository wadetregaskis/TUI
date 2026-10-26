"""Just enough of a Swift lexer for the module map: top-level declaration chunks, `#if` branch conditions per line,
and code with comments and string contents blanked out.

It is not a parser. It tracks strings (normal, multi-line, raw, with interpolation), nested block comments and
bracket depth, which is all the module map needs to answer three questions about a line: which top-level
declaration's text holds it, which `#if` branches enclose it, and what its code says without its comments.
Regex literals are not lexed (TUI has none).
"""
import re

MOD = (r'(?:public|package|internal|fileprivate|private|open|final|nonisolated|indirect|static|override|convenience'
       r'|required|dynamic|lazy|mutating|nonmutating|weak|unowned|borrowing|consuming)')
KW = (r'(?:struct|class|enum|extension|protocol|func|var|let|typealias|actor|precedencegroup'
      r'|(?:infix|prefix|postfix)\s+operator|macro|init|subscript)')
ATTR = r'@[\w.]+(?:\((?:[^()]|\([^()]*\))*\))?'
DECL = re.compile(r'^\s*(?:' + ATTR + r'\s*)*(?:' + MOD + r'(?:\((?:set)\))?\s+)*' + KW + r'\b')
# An import declaration, in all its forms: attributes in any order and with arguments (`@_spi(Name)`, `@preconcurrency
# @_exported`), an access modifier (`internal import`), an import kind (`import struct M.T`).
_IMPORT = re.compile(r'^\s*((?:' + ATTR + r'\s*)*)(?:(?:public|package|internal|fileprivate|private)\s+)?import\s+'
                     r'(?:(?:struct|class|enum|protocol|func|var|let|typealias)\s+)?(\w+)(?:\.\w+)*')


def import_of(line):
    """(module, re-exported, what follows the declaration on its line) when the line is an import, else None. The
    one reading of an import line the module map has: the `lower` check's module list, `posix`'s `import Darwin`, and
    `umbrella`'s only-imports rule all take it."""
    m = _IMPORT.match(line)
    if not m: return None
    return m.group(2), re.search(r'@_exported\b', m.group(1)) is not None, line[m.end():].strip()


class Lexed:
    """Per-line facts about one file (1-based; index 0 unused).

    lines    the file's lines
    dstart   bracket depth ({[( in code) at the start of the line
    dend     bracket depth at its end
    code     the line starts in code (not inside a string or a block comment)
    conds    the `#if`/`#elseif`/`#else` branches enclosing the line, outermost first, as (directive, condition,
             the conditions of the branches before it in its chain); an `#else` has the condition ''
    stripped the line with comments and string contents replaced by spaces (interpolations kept as code)
    """


def lex(text):
    lines = text.split('\n')
    n = len(lines)
    L = Lexed()
    L.lines = lines
    L.dstart = [0] * (n + 2)
    L.dend = [0] * (n + 2)
    L.code = [True] * (n + 2)
    L.conds = [()] * (n + 2)
    L.stripped = [''] * (n + 2)
    depth = 0
    st = [('code',)]          # ('code',) | ('interp', parens) | ('str', hashes, multi) | ('block', nest)
    conds = []
    for li, line in enumerate(lines, start=1):
        L.dstart[li] = depth
        L.code[li] = len(st) == 1
        s = line.strip()
        if len(st) == 1 and s.startswith('#'):
            m = re.match(r'#(if|elseif|else|endif)\b\s*(.*?)\s*(?://.*)?$', s)
            if m:
                kind, cond = m.group(1), m.group(2)
                if kind == 'if': conds.append(('if', cond, ()))
                elif kind in ('elseif', 'else') and conds:
                    _, c0, p0 = conds[-1]
                    conds[-1] = (kind, cond if kind == 'elseif' else '', p0 + ((c0,) if c0 else ()))
                elif kind == 'endif' and conds: conds.pop()
        L.conds[li] = tuple(conds)
        out = []
        i = 0; n_ = len(line)
        while i < n_:
            top = st[-1]; c = line[i]
            if top[0] in ('code', 'interp'):
                if c == '/' and i + 1 < n_ and line[i + 1] == '/':
                    out.append(' ' * (n_ - i)); break
                if c == '/' and i + 1 < n_ and line[i + 1] == '*':
                    st.append(('block', 1)); out.append('  '); i += 2; continue
                if c == '#' or c == '"':
                    j = i; h = 0
                    while j < n_ and line[j] == '#': h += 1; j += 1
                    if j < n_ and line[j] == '"':
                        if line[j:j + 3] == '"""':
                            st.append(('str', h, True)); out.append(' ' * (j + 3 - i)); i = j + 3; continue
                        st.append(('str', h, False)); out.append(' ' * (j + 1 - i)); i = j + 1; continue
                    out.append(line[i:j] if h else c); i = j if h else i + 1
                    continue
                if top[0] == 'interp':
                    if c == '(':
                        st[-1] = ('interp', top[1] + 1)
                    elif c == ')':
                        if top[1] == 0:
                            st.pop(); out.append(' '); i += 1; continue
                        st[-1] = ('interp', top[1] - 1)
                    out.append(c); i += 1; continue
                if c in '{[(':
                    depth += 1
                elif c in '}])':
                    depth -= 1
                out.append(c); i += 1; continue
            if top[0] == 'block':
                if c == '/' and i + 1 < n_ and line[i + 1] == '*':
                    st[-1] = ('block', top[1] + 1); out.append('  '); i += 2; continue
                if c == '*' and i + 1 < n_ and line[i + 1] == '/':
                    if top[1] == 1: st.pop()
                    else: st[-1] = ('block', top[1] - 1)
                    out.append('  '); i += 2; continue
                out.append(' '); i += 1; continue
            # inside a string
            h, multi = top[1], top[2]
            if c == '\\':
                if line[i + 1:i + 1 + h] == '#' * h:
                    k = i + 1 + h
                    if k < n_ and line[k] == '(':
                        st.append(('interp', 0)); out.append(' ' * (k + 1 - i)); i = k + 1; continue
                    out.append(' ' * (k + 1 - i)); i = k + 1; continue
                out.append(' '); i += 1; continue
            if c == '"':
                if multi:
                    if line[i:i + 3] == '"""' and line[i + 3:i + 3 + h] == '#' * h:
                        st.pop(); out.append(' ' * (3 + h)); i += 3 + h; continue
                elif line[i + 1:i + 1 + h] == '#' * h:
                    st.pop(); out.append(' ' * (1 + h)); i += 1 + h; continue
            out.append(' '); i += 1
        while st[-1][0] == 'str' and not st[-1][2]:        # a single-line string cannot span lines
            st.pop()
        L.dend[li] = depth
        L.stripped[li] = ''.join(out)
    return L


def chunks(L):
    """Top-level declaration chunks: [(start, end, anchor_lines)], 1-based inclusive.

    A chunk runs from the first line of a top-level declaration's leading trivia (doc comment, attributes, an
    opening `#if`) to the line before the next chunk's trivia. A top-level `#if` region that holds several
    declarations stays one chunk, so every chunk starts and ends at bracket depth 0 outside any open `#if`.
    """
    n = len(L.lines)
    S = lambda i: L.lines[i - 1].strip()
    top0 = lambda i: L.code[i] and L.dstart[i] == 0
    anchors = [i for i in range(1, n + 1) if top0(i) and DECL.match(L.lines[i - 1])]

    def trivia_start(a):
        top = a; pending = []
        i = a - 1
        while i >= 1:
            s = S(i)
            if not L.code[i] or s == '' or s.startswith('//') or s.startswith('/*'):
                if pending: pending.append(i)
                else: top = i
                i -= 1; continue
            if top0(i) and s.startswith('@'):
                top = i; pending = []; i -= 1; continue
            if top0(i) and s.startswith('#if') and not pending:
                top = i; i -= 1; continue
            if L.dend[i] == 0 and re.sub(r'\s*//.*$', '', s).rstrip().endswith('}'):
                break
            if L.dstart[i] > 0 or not L.code[i]:
                pending.append(i); i -= 1; continue
            break
        return top

    pieces = []
    for a in anchors:
        t = trivia_start(a)
        if pieces and t <= pieces[-1][1][-1]:
            pieces[-1][1].append(a)
        else:
            pieces.append([t, [a]])
    out = []
    for k, (t, ans) in enumerate(pieces):
        end = pieces[k + 1][0] - 1 if k + 1 < len(pieces) else n
        out.append([t, end, ans])
    if not out: return []
    base = len(L.conds[out[0][0]])
    merged = []
    for ch in out:
        if merged and (len(L.conds[ch[0]]) != base or L.dstart[ch[0]] != 0):
            merged[-1][1] = ch[1]; merged[-1][2] += ch[2]
        else:
            merged.append(ch)
    return [tuple(c) for c in merged]


# What a `#if` condition's atoms are on the two non-POSIX targets: True, False, or None when it cannot be told
# from the platform alone (`arch(arm64)` on Windows, `compiler(>=6.3)`, a build flag).
_LIBC = {'Darwin', 'Glibc', 'Musl', 'Android', 'Bionic', 'WASILibc', 'WinSDK', 'ucrt'}
_APPLE_ONLY = {'AppKit', 'UIKit', 'CoreText', 'CoreGraphics', 'ObjectiveC', 'Combine', 'SwiftUI', 'Symbols',
               'UniformTypeIdentifiers', 'Security', 'IOKit', 'CoreServices'}
_PLATFORMS = {'Windows': ({'WinSDK', 'ucrt'}, None), 'WASI': ({'WASILibc'}, 'wasm32')}


def _atom(platform, name, arg):
    libc, arch = _PLATFORMS[platform]
    if name == 'os': return arg == platform
    if name == 'canImport':
        if arg in libc: return True
        if arg in _LIBC or arg in _APPLE_ONLY: return False
        return None
    if name == 'arch' and arch: return arg == arch
    if name is None and arg in ('true', 'false'): return arg == 'true'
    return None


def evaluate(cond, platform):
    """A `#if` condition on `platform` ('Windows' or 'WASI'): True, False, or None when the platform alone does
    not decide it (or the condition does not parse)."""
    toks = re.findall(r'\|\||&&|!|\(|\)|[\w.]+\s*\([^()]*\)|[\w.]+', cond)
    if re.sub(r'\s+', '', ''.join(toks)) != re.sub(r'\s+', '', cond): return None
    pos = [0]

    def peek(): return toks[pos[0]] if pos[0] < len(toks) else None

    def take(): pos[0] += 1; return toks[pos[0] - 1]

    def orexp():
        v = andexp()
        while peek() == '||':
            take(); w = andexp()
            v = True if v is True or w is True else (False if v is False and w is False else None)
        return v

    def andexp():
        v = unary()
        while peek() == '&&':
            take(); w = unary()
            v = False if v is False or w is False else (True if v is True and w is True else None)
        return v

    def unary():
        t = take()
        if t == '!':
            v = unary(); return None if v is None else not v
        if t == '(':
            v = orexp()
            if take() != ')': raise ValueError
            return v
        if t is None or t in ('||', '&&', ')'): raise ValueError
        m = re.match(r'([\w.]+)\s*\(\s*([^()]*?)\s*\)$', t)
        return _atom(platform, m.group(1), m.group(2)) if m else _atom(platform, None, t)
    try:
        v = orexp()
        return v if pos[0] == len(toks) else None
    except (ValueError, IndexError):
        return None


def _reachable(level, platform):
    """Whether a branch can be compiled on `platform`: no earlier branch of its chain is surely taken there, and
    its own condition is not surely false."""
    kind, cond, priors = level
    if any(evaluate(c, platform) is True for c in priors): return False
    return kind == 'else' or evaluate(cond, platform) is not False


def posix_guarded(conds):
    """Whether only POSIX platforms compile a line: the `#if` branches enclosing it rule out both Windows and WASI.
    `#if canImport(Darwin)` and its `#elseif canImport(Glibc)` do; so does the `#else` of `#if canImport(WASILibc) ||
    os(Windows)`, and `#if !os(Windows) && !os(WASI)`. The `#else` of `#if canImport(WASILibc)` does not (Windows
    compiles it), and nor does a branch the platform alone cannot decide (`#if os(Windows) && arch(x86_64)`'s
    `#else`)."""
    return all(any(not _reachable(level, p) for level in conds) for p in _PLATFORMS)
