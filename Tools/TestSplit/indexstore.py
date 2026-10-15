"""A minimal reader of the compiler's index store (`.build/<triple>/debug/index/store`), over libIndexStore's C API.

The index store records, for every compiled file, every symbol occurrence in it: each declaration, and each
reference — a type named only in a signature, a call the optimiser would inline, a member found in an extension —
by USR. That is exactly what deciding which modules a test file needs takes, and what an object file's undefined
symbols miss.

Only the calls this needs are bound: units, their record dependencies, and the occurrences in a record.
"""
import ctypes, os, subprocess


class StringRef(ctypes.Structure):
    _fields_ = [("data", ctypes.c_void_p), ("length", ctypes.c_size_t)]

    def text(self):
        return ctypes.string_at(self.data, self.length).decode() if self.data else ""


UNIT_APPLIER = ctypes.CFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, StringRef)
DEPENDENCY_APPLIER = ctypes.CFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
OCCURRENCE_APPLIER = ctypes.CFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)

# indexstore_unit_dependency_kind_t
DEPENDENCY_UNIT, DEPENDENCY_RECORD, DEPENDENCY_FILE = 1, 2, 3
# indexstore_symbol_role_t
ROLE_DECLARATION, ROLE_DEFINITION, ROLE_REFERENCE = 1 << 0, 1 << 1, 1 << 2


def library_path():
    developer = os.environ.get("DEVELOPER_DIR") or subprocess.run(
        ["xcode-select", "-p"], capture_output=True, text=True).stdout.strip()
    return os.path.join(developer, "Toolchains/XcodeDefault.xctoolchain/usr/lib/libIndexStore.dylib")


class IndexStore:
    def __init__(self, path, library=None):
        lib = self.lib = ctypes.CDLL(library or library_path())
        for name, restype, argtypes in [
            ("indexstore_store_create", ctypes.c_void_p, [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]),
            ("indexstore_store_units_apply_f", ctypes.c_bool,
             [ctypes.c_void_p, ctypes.c_uint, ctypes.c_void_p, UNIT_APPLIER]),
            ("indexstore_unit_reader_create", ctypes.c_void_p,
             [ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]),
            ("indexstore_unit_reader_dispose", None, [ctypes.c_void_p]),
            ("indexstore_unit_reader_get_main_file", StringRef, [ctypes.c_void_p]),
            ("indexstore_unit_reader_get_module_name", StringRef, [ctypes.c_void_p]),
            ("indexstore_unit_reader_get_modification_time", ctypes.c_bool,
             [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int64), ctypes.POINTER(ctypes.c_int64)]),
            ("indexstore_unit_reader_dependencies_apply_f", ctypes.c_bool,
             [ctypes.c_void_p, ctypes.c_void_p, DEPENDENCY_APPLIER]),
            ("indexstore_unit_dependency_get_kind", ctypes.c_int, [ctypes.c_void_p]),
            ("indexstore_unit_dependency_get_name", StringRef, [ctypes.c_void_p]),
            ("indexstore_unit_dependency_get_filepath", StringRef, [ctypes.c_void_p]),
            ("indexstore_record_reader_create", ctypes.c_void_p,
             [ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]),
            ("indexstore_record_reader_dispose", None, [ctypes.c_void_p]),
            ("indexstore_record_reader_occurrences_apply_f", ctypes.c_bool,
             [ctypes.c_void_p, ctypes.c_void_p, OCCURRENCE_APPLIER]),
            ("indexstore_occurrence_get_symbol", ctypes.c_void_p, [ctypes.c_void_p]),
            ("indexstore_occurrence_get_roles", ctypes.c_uint64, [ctypes.c_void_p]),
            ("indexstore_symbol_get_usr", StringRef, [ctypes.c_void_p]),
            ("indexstore_symbol_get_name", StringRef, [ctypes.c_void_p]),
            ("indexstore_error_get_description", ctypes.c_char_p, [ctypes.c_void_p]),
        ]:
            function = getattr(lib, name)
            function.restype, function.argtypes = restype, argtypes
        error = ctypes.c_void_p()
        self.store = lib.indexstore_store_create(path.encode(), ctypes.byref(error))
        if not self.store:
            raise RuntimeError(lib.indexstore_error_get_description(error).decode())

    def units(self):
        names = []
        self.lib.indexstore_store_units_apply_f(self.store, 0, None, UNIT_APPLIER(
            lambda _, name: names.append(name.text()) or True))
        return names

    def unit(self, name):
        """(module, main file, modification time, [(record name, source path)]) of the unit `name`, or None."""
        error = ctypes.c_void_p()
        reader = self.lib.indexstore_unit_reader_create(self.store, name.encode(), ctypes.byref(error))
        if not reader:
            return None
        try:
            seconds, nanoseconds = ctypes.c_int64(), ctypes.c_int64()
            self.lib.indexstore_unit_reader_get_modification_time(reader, ctypes.byref(seconds),
                                                                  ctypes.byref(nanoseconds))
            records = []

            def dependency(_, dep):
                if self.lib.indexstore_unit_dependency_get_kind(dep) == DEPENDENCY_RECORD:
                    records.append((self.lib.indexstore_unit_dependency_get_name(dep).text(),
                                    self.lib.indexstore_unit_dependency_get_filepath(dep).text()))
                return True

            self.lib.indexstore_unit_reader_dependencies_apply_f(reader, None, DEPENDENCY_APPLIER(dependency))
            return (self.lib.indexstore_unit_reader_get_module_name(reader).text(),
                    self.lib.indexstore_unit_reader_get_main_file(reader).text(),
                    seconds.value + nanoseconds.value / 1e9, records)
        finally:
            self.lib.indexstore_unit_reader_dispose(reader)

    def occurrences(self, record):
        """[(usr, name, roles)] of every occurrence in the record `record`."""
        error = ctypes.c_void_p()
        reader = self.lib.indexstore_record_reader_create(self.store, record.encode(), ctypes.byref(error))
        if not reader:
            return []
        found = []
        try:
            def occurrence(_, occ):
                symbol = self.lib.indexstore_occurrence_get_symbol(occ)
                found.append((self.lib.indexstore_symbol_get_usr(symbol).text(),
                              self.lib.indexstore_symbol_get_name(symbol).text(),
                              self.lib.indexstore_occurrence_get_roles(occ)))
                return True

            self.lib.indexstore_record_reader_occurrences_apply_f(reader, None, OCCURRENCE_APPLIER(occurrence))
        finally:
            self.lib.indexstore_record_reader_dispose(reader)
        return found
