"""machofile.py: just enough of Mach-O 64 (arm64) to read sections, symbols and relocations. Standard library only.

    img = read(path)            # a thin arm64 Mach-O 64 file (object, executable or dylib); None if it is not one
    img.sections                # [Section]: segname, sectname, addr, size, reloff, nreloc, index (1-based)
    img.symbols                 # [Symbol]: name, type, sect (1-based, 0 = none), desc, value
    img.relocations(section)    # [(address, symbol name or None, type, pcrel, length, Symbol or None)]

A universal (fat) file, or a thin one for another CPU, is not read: the relocation types below are arm64's.
`lipo -thin arm64` makes a thin file of a universal one.
"""
import struct

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC, FAT_MAGIC_64 = 0xCAFEBABE, 0xCAFEBABF
CPU_TYPE_ARM64 = 0x0100000C
MH_OBJECT, MH_EXECUTE = 0x1, 0x2
LC_SEGMENT_64, LC_SYMTAB = 0x19, 0x2
N_STAB, N_TYPE, N_EXT, N_SECT, N_UNDF = 0xE0, 0x0E, 0x01, 0x0E, 0x0
# arm64 relocation types (mach-o/arm64/reloc.h)
ARM64_RELOC = {0: 'UNSIGNED', 1: 'SUBTRACTOR', 2: 'BRANCH26', 3: 'PAGE21', 4: 'PAGEOFF12', 5: 'GOT_LOAD_PAGE21',
               6: 'GOT_LOAD_PAGEOFF12', 7: 'POINTER_TO_GOT', 8: 'TLVP_LOAD_PAGE21', 9: 'TLVP_LOAD_PAGEOFF12',
               10: 'ADDEND', 11: 'AUTHENTICATED_POINTER'}


class NotReadable(Exception):
    """A Mach-O file this module will not read (universal, or not arm64), with the reason."""


class Section:
    __slots__ = ('segname', 'sectname', 'addr', 'size', 'offset', 'reloff', 'nreloc', 'flags', 'index')


class Symbol:
    __slots__ = ('name', 'type', 'sect', 'desc', 'value')

    @property
    def defined(self):
        return not (self.type & N_STAB) and (self.type & N_TYPE) == N_SECT

    @property
    def external(self):
        return bool(self.type & N_EXT)


class Image:
    def __init__(self, data, path):
        self.data, self.path = data, path
        self.sections, self.symbols = [], []
        _, self.cputype, _, self.filetype, ncmds, _, _, _ = struct.unpack_from('<IiiIIIII', data, 0)
        if self.cputype != CPU_TYPE_ARM64:
            raise NotReadable(f'{path}: CPU type {self.cputype:#x}, not arm64')
        off = 32
        for _ in range(ncmds):
            cmd, size = struct.unpack_from('<II', data, off)
            if cmd == LC_SEGMENT_64:
                nsects = struct.unpack_from('<I', data, off + 64)[0]
                s = off + 72
                for _ in range(nsects):
                    sec = Section()
                    sec.sectname = data[s:s + 16].split(b'\0')[0].decode()
                    sec.segname = data[s + 16:s + 32].split(b'\0')[0].decode()
                    sec.addr, sec.size, sec.offset, _, sec.reloff, sec.nreloc, sec.flags = \
                        struct.unpack_from('<QQIIIII', data, s + 32)
                    sec.index = len(self.sections) + 1
                    self.sections.append(sec)
                    s += 80
            elif cmd == LC_SYMTAB:
                symoff, nsyms, stroff, strsize = struct.unpack_from('<IIII', data, off + 8)
                strtab = data[stroff:stroff + strsize]
                for i in range(nsyms):
                    strx, typ, sect, desc, value = struct.unpack_from('<IBBHQ', data, symoff + 16 * i)
                    sym = Symbol()
                    end = strtab.find(b'\0', strx)
                    sym.name = strtab[strx:end].decode('utf-8', 'replace')
                    sym.type, sym.sect, sym.desc, sym.value = typ, sect, desc, value
                    self.symbols.append(sym)
            off += size

    def section(self, segname, sectname):
        for s in self.sections:
            if s.segname == segname and s.sectname == sectname:
                return s
        return None

    def relocations(self, sec):
        """An object file's relocations for `sec`: (address, target symbol name or None, type, pcrel, length,
        target Symbol or None). A non-extern relocation names a section, not a symbol: its target is None."""
        out = []
        for i in range(sec.nreloc):
            addr, info = struct.unpack_from('<iI', self.data, sec.reloff + 8 * i)
            symnum, pcrel, length = info & 0xFFFFFF, (info >> 24) & 1, (info >> 25) & 3
            extern, rtype = (info >> 27) & 1, (info >> 28) & 0xF
            sym = self.symbols[symnum] if extern and symnum < len(self.symbols) else None
            out.append((sec.addr + addr, sym.name if sym else None, ARM64_RELOC.get(rtype, str(rtype)), pcrel, length,
                        sym))
        return out


def read(path):
    """The file as an Image; None if it is not a Mach-O file at all. Raises NotReadable for a Mach-O file this module
    does not read (universal, or for another CPU), so that a caller cannot mistake it for an empty one."""
    with open(path, 'rb') as f:
        data = f.read()
    if len(data) < 32:
        return None
    magic = struct.unpack_from('<I', data, 0)[0]
    if struct.unpack_from('>I', data, 0)[0] in (FAT_MAGIC, FAT_MAGIC_64):
        raise NotReadable(f'{path}: a universal binary; make a thin one first (lipo -thin arm64)')
    if magic != MH_MAGIC_64:
        return None
    return Image(data, path)
