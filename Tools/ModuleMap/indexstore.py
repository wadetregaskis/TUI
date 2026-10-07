"""Reads a Swift index store (the one `swift build` writes in debug on macOS) through libIndexStore and ctypes.

Python's standard library only: libIndexStore ships with every Swift toolchain (`usr/lib/libIndexStore.dylib`
beside `usr/bin/swift`; `.so` on Linux), and the store is the one the debug build already wrote, so reading it
costs no build. 262k occurrences in 794 files read in about 3 s (2026-10-07, M-series VM).
"""
import ctypes
import glob
import os
import shutil
import subprocess

# indexstore_symbol_role_t
DECLARATION = 1 << 0
DEFINITION = 1 << 1
REFERENCE = 1 << 2
REL_CHILD_OF = 1 << 9
REL_BASE_OF = 1 << 10
REL_CALLED_BY = 1 << 13
REL_EXTENDED_BY = 1 << 14
REL_ACCESSOR_OF = 1 << 15
REL_CONTAINED_BY = 1 << 16
# indexstore_symbol_kind_t (the ones the map uses)
K_ENUM, K_STRUCT, K_CLASS, K_PROTOCOL, K_EXTENSION, K_TYPEALIAS = 5, 6, 7, 8, 9, 11
K_FUNCTION, K_VARIABLE = 12, 13
CALLABLE_KINDS = (12, 16, 17, 18, 19, 20, 21, 22)
TYPE_KINDS = (K_ENUM, K_STRUCT, K_CLASS, K_PROTOCOL)


class _SR(ctypes.Structure):
    _fields_ = [('data', ctypes.c_char_p), ('length', ctypes.c_size_t)]


def _s(r):
    return ctypes.string_at(r.data, r.length).decode('utf-8', 'replace') if r.data else ''


def find_libindexstore():
    """The toolchain's libIndexStore: $MODULEMAP_LIBINDEXSTORE, else beside the `swift` that `xcrun` (macOS) or
    PATH resolves to."""
    env = os.environ.get('MODULEMAP_LIBINDEXSTORE')
    if env: return env
    cands = []
    try:
        found = subprocess.run(['xcrun', '--find', 'swift'], capture_output=True, text=True, check=True)
        cands.append(found.stdout.strip())
    except (OSError, subprocess.CalledProcessError):
        pass
    w = shutil.which('swift')
    if w: cands.append(os.path.realpath(w))
    for sw in cands:
        lib = os.path.join(os.path.dirname(os.path.dirname(sw)), 'lib')
        for name in ('libIndexStore.dylib', 'libIndexStore.so'):
            if os.path.exists(os.path.join(lib, name)): return os.path.join(lib, name)
    raise SystemExit('modulemap: no libIndexStore found; set MODULEMAP_LIBINDEXSTORE')


def find_store(root):
    """The newest `.build/<triple>/debug/index/store` under the package root."""
    stores = glob.glob(os.path.join(root, '.build', '*', 'debug', 'index', 'store'))
    if not stores:
        raise SystemExit('modulemap: no index store under .build/*/debug/index/store — run `swift build` first '
                         '(SwiftPM indexes debug builds on macOS by default), or pass --store')
    return max(stores, key=os.path.getmtime)


def read(store_path, module, source_prefix, lib_path=None):
    """Occurrences of every file of `module` under `source_prefix`, from the newest unit for each file.

    Returns (files, symbols, unit_mtimes):
      files        {path: [(usr, roles, line, container_usr)]}; the container is the symbol the occurrence's
                   strongest relation names (contained-by / called-by / child-of / accessor-of, else base-of /
                   extended-by), or '' when it has none
      symbols      {usr: (name, kind, subkind)}
      unit_mtimes  {path: seconds} when each file's unit was written
    """
    L = ctypes.CDLL(lib_path or find_libindexstore())
    vp = ctypes.c_void_p
    L.indexstore_store_create.restype = vp
    L.indexstore_store_create.argtypes = [ctypes.c_char_p, ctypes.POINTER(vp)]
    UNITCB = ctypes.CFUNCTYPE(ctypes.c_bool, vp, _SR)
    L.indexstore_store_units_apply_f.argtypes = [vp, ctypes.c_uint, vp, UNITCB]
    L.indexstore_unit_reader_create.restype = vp
    L.indexstore_unit_reader_create.argtypes = [vp, ctypes.c_char_p, ctypes.POINTER(vp)]
    L.indexstore_unit_reader_dispose.argtypes = [vp]
    for fn in ('indexstore_unit_reader_get_main_file', 'indexstore_unit_reader_get_module_name'):
        getattr(L, fn).restype = _SR
        getattr(L, fn).argtypes = [vp]
    i64p = ctypes.POINTER(ctypes.c_int64)
    L.indexstore_unit_reader_get_modification_time.argtypes = [vp, i64p, i64p]
    DEPCB = ctypes.CFUNCTYPE(ctypes.c_bool, vp, vp)
    L.indexstore_unit_reader_dependencies_apply_f.argtypes = [vp, vp, DEPCB]
    L.indexstore_unit_dependency_get_kind.restype = ctypes.c_int
    L.indexstore_unit_dependency_get_kind.argtypes = [vp]
    for fn in ('indexstore_unit_dependency_get_name', 'indexstore_unit_dependency_get_filepath'):
        getattr(L, fn).restype = _SR
        getattr(L, fn).argtypes = [vp]
    L.indexstore_record_reader_create.restype = vp
    L.indexstore_record_reader_create.argtypes = [vp, ctypes.c_char_p, ctypes.POINTER(vp)]
    L.indexstore_record_reader_dispose.argtypes = [vp]
    OCCB = ctypes.CFUNCTYPE(ctypes.c_bool, vp, vp)
    L.indexstore_record_reader_occurrences_apply_f.argtypes = [vp, vp, OCCB]
    L.indexstore_occurrence_get_symbol.restype = vp
    L.indexstore_occurrence_get_symbol.argtypes = [vp]
    L.indexstore_occurrence_get_roles.restype = ctypes.c_uint64
    L.indexstore_occurrence_get_roles.argtypes = [vp]
    L.indexstore_occurrence_get_line_col.argtypes = [vp, ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint)]
    RELCB = ctypes.CFUNCTYPE(ctypes.c_bool, vp, vp)
    L.indexstore_occurrence_relations_apply_f.argtypes = [vp, vp, RELCB]
    L.indexstore_symbol_relation_get_roles.restype = ctypes.c_uint64
    L.indexstore_symbol_relation_get_roles.argtypes = [vp]
    L.indexstore_symbol_relation_get_symbol.restype = vp
    L.indexstore_symbol_relation_get_symbol.argtypes = [vp]
    for fn in ('indexstore_symbol_get_usr', 'indexstore_symbol_get_name'):
        getattr(L, fn).restype = _SR
        getattr(L, fn).argtypes = [vp]
    L.indexstore_symbol_get_kind.restype = ctypes.c_int
    L.indexstore_symbol_get_kind.argtypes = [vp]
    L.indexstore_symbol_get_subkind.restype = ctypes.c_int
    L.indexstore_symbol_get_subkind.argtypes = [vp]

    err = vp()
    store = L.indexstore_store_create(store_path.encode(), ctypes.byref(err))
    if not store: raise SystemExit(f'modulemap: cannot open the index store at {store_path}')
    units = []

    @UNITCB
    def unit_cb(ctx, name):
        units.append(_s(name)); return True
    L.indexstore_store_units_apply_f(store, 0, None, unit_cb)

    newest = {}          # main file -> (mtime, unit name)
    for u in units:
        ur = L.indexstore_unit_reader_create(store, u.encode(), ctypes.byref(err))
        if not ur: continue
        mod = _s(L.indexstore_unit_reader_get_module_name(ur))
        main = _s(L.indexstore_unit_reader_get_main_file(ur))
        if mod == module and main.startswith(source_prefix):
            sec = ctypes.c_int64(); nsec = ctypes.c_int64()
            L.indexstore_unit_reader_get_modification_time(ur, ctypes.byref(sec), ctypes.byref(nsec))
            t = sec.value + nsec.value / 1e9
            if main not in newest or t > newest[main][0]: newest[main] = (t, u)
        L.indexstore_unit_reader_dispose(ur)

    files, symbols = {}, {}
    for main, (t, u) in newest.items():
        ur = L.indexstore_unit_reader_create(store, u.encode(), ctypes.byref(err))
        records = []

        @DEPCB
        def dep_cb(ctx, dep):
            if L.indexstore_unit_dependency_get_kind(dep) == 2:          # a record
                if _s(L.indexstore_unit_dependency_get_filepath(dep)) == main:
                    records.append(_s(L.indexstore_unit_dependency_get_name(dep)))
            return True
        L.indexstore_unit_reader_dependencies_apply_f(ur, None, dep_cb)
        L.indexstore_unit_reader_dispose(ur)
        occs = []
        for rec in records[:1]:
            rr = L.indexstore_record_reader_create(store, rec.encode(), ctypes.byref(err))
            if not rr: continue

            @OCCB
            def occ_cb(ctx, occ):
                sym = L.indexstore_occurrence_get_symbol(occ)
                usr = _s(L.indexstore_symbol_get_usr(sym))
                if usr not in symbols:
                    symbols[usr] = (_s(L.indexstore_symbol_get_name(sym)), L.indexstore_symbol_get_kind(sym),
                                    L.indexstore_symbol_get_subkind(sym))
                roles = L.indexstore_occurrence_get_roles(occ)
                line = ctypes.c_uint(); col = ctypes.c_uint()
                L.indexstore_occurrence_get_line_col(occ, ctypes.byref(line), ctypes.byref(col))
                cont = []

                @RELCB
                def rel_cb(ctx2, rel):
                    r = L.indexstore_symbol_relation_get_roles(rel)
                    if r & (REL_CONTAINED_BY | REL_CALLED_BY | REL_CHILD_OF | REL_ACCESSOR_OF): pri = 0
                    elif r & (REL_BASE_OF | REL_EXTENDED_BY): pri = 1
                    else: return True
                    cont.append((pri, _s(L.indexstore_symbol_get_usr(L.indexstore_symbol_relation_get_symbol(rel)))))
                    return True
                L.indexstore_occurrence_relations_apply_f(occ, None, rel_cb)
                occs.append((usr, roles, line.value, min(cont)[1] if cont else ''))
                return True
            L.indexstore_record_reader_occurrences_apply_f(rr, None, occ_cb)
            L.indexstore_record_reader_dispose(rr)
        files[main] = occs
    return files, symbols, {m: t for m, (t, _) in newest.items()}
