"""
GDB plugin for debugging Jonesforth
"""

import gdb

INFERIOR = gdb.selected_inferior()
ARCHITECTURE = INFERIOR.architecture()
F_IMMED = 0x80
F_HIDDEN = 0x20
F_LENMASK = 0x1f
ALIGN_MASK = 0xFFFFFFFC

def align(addr):
    """Adjust the given address so it is aligned to a 4-byte boundary."""
    if isinstance(addr, gdb.Type):
        addr = addr.cast(ARCHITECTURE.integer_type(32, False))
    aligned_addr = (addr + 3) & ALIGN_MASK
    #  print(f"Aligned {addr.format_string(format='x')} to {aligned_addr.format_string(format='x')}")
    return aligned_addr


class DictEntryDumpCmd(gdb.Command):
    """Prints a dictionary entry given its CFA."""

    def __init__(self):
        super(DictEntryDumpCmd, self).__init__(
            "lookup", gdb.COMMAND_USER
        )

    def _to_dfa(self, addr):
        """Find the dictionary field address for a word."""
        addr = align(addr)
        #  print(f"Looking for DFA starting at aligned address {addr.format_string(format='x')}")
        for offset in range(64):
            # null padding should be address aligned so we will get a 0 when we hit it
            next_addr = addr - 4
            bs = INFERIOR.read_memory(next_addr, 4)
            val = int.from_bytes(bs, byteorder="little")
            #  print(f"Addr: {next_addr.format_string(format='x')} Size: {len(bs)} Val: {val}")
            if val == 0:
                #  print(f"Found DFA starting at address {addr.format_string(format='x')}")
                return addr
            addr = next_addr
        raise ValueError("Could not determine start of dictionary entry")

    def _to_cfa(self, dfa):
        """Convert a dictionary field address to a code field address"""
        name_size = self._dict_entry_size(dfa)
        cfa = align(dfa + name_size + 3)
        #  print(f"DFA {dfa.format_string(format='x')} + {name_size} = {cfa.format_string(format='x')}")
        return cfa

    def _dict_entry_flag_byte(self, dfa):
        b = INFERIOR.read_memory(dfa + 4, 1)[0]
        b = int.from_bytes(b, byteorder="little") 
        return b

    def _dict_entry_size(self, dfa):
        return self._dict_entry_flag_byte(dfa) & F_LENMASK

    def _dict_entry_name(self, dfa, size):
        name_mem = INFERIOR.read_memory(dfa + 5, size)
        return name_mem.tobytes().decode("ascii")

    def _dict_entry_flags(self, dfa):
        flag_byte = self._dict_entry_flag_byte(dfa)
        flags = []
        if flag_byte & F_IMMED:
            flags.append("IMMEDIATE")
        if flag_byte & F_HIDDEN:
            flags.append("HIDDEN")

        if flags:
            return ", ".join(flags)
        else:
            return "(None)"

    def _dict_entry_prev(self, dfa):
        link_field = INFERIOR.read_memory(dfa, 4).tobytes()
        link_addr = int.from_bytes(link_field, byteorder="little") 
        return self._resolve_symbol(link_addr)

    def _dict_entry_body(self, cfa):
        addr = cfa
        words = []
        for i in range(32):
            mem = INFERIOR.read_memory(addr, 4)
            addr += 4
            word = int.from_bytes(mem, byteorder="little") 
            if word:
                sym = self._resolve_symbol(word)
                words.append(f" - {sym}")
            else:
                break
        return "\n".join(words)

    def _resolve_symbol(self, addr):
        """Resolve the name of the symbol at ADDR"""
        sym = gdb.execute(f"info symbol 0x{addr:x}", False, True).strip()
        if "No symbol matches" in sym:
            try:
                dfa = self._to_dfa(addr)
                size = self._dict_entry_size(dfa)
                sym = self._dict_entry_name(dfa, size)
            except Exception as e:
                print(f"Error looking up symbol in dictionary: {e}")
                return f"<0x{addr:x}>"
        return sym

    def complete(self, text, word):
        # We expect the argument passed to be a symbol so fallback to the
        # internal tab-completion handler for symbols
        return gdb.COMPLETE_SYMBOL

    def invoke(self, args, from_tty):
        addr = gdb.parse_and_eval(args)

        types = {"int", "long", "unsigned int", "int *", "char *", "void *"}
        if str(addr.type) not in types:
            print(f"Expected address argument of type {types}, got", str(addr.type))
            return

        dfa = self._to_dfa(addr)
        print("Dictionary Field Address:", dfa.format_string(format="x"))

        cfa = self._to_cfa(dfa)
        print("Code Field Address:", cfa.format_string(format="x"))

        size = self._dict_entry_size(dfa)
        name = self._dict_entry_name(dfa, size)
        print(f"Name:  ({size}) {name}")

        flags = self._dict_entry_flags(dfa)
        print(f"Flags: {flags}")

        body = self._dict_entry_body(cfa)
        print(f"Body:\n{body}")

        prev = self._dict_entry_prev(dfa)
        print(f"Prev: {prev}")

DictEntryDumpCmd()

class LengthPrefixedStringDumpCmd(gdb.Command):
    """Prints length-prefixed strings."""

    def __init__(self):
        super(LengthPrefixedStringDumpCmd, self).__init__(
            "print_len", gdb.COMMAND_USER
        )

    def _len_and_addr_to_str(self, addr, size):
        str_mem = INFERIOR.read_memory(addr, size)
        return str_mem.tobytes().decode("ascii")

    def complete(self, text, word):
        # We expect the argument passed to be a symbol so fallback to the
        # internal tab-completion handler for symbols
        return gdb.COMPLETE_SYMBOL

    def invoke(self, args, from_tty):
        # We can pass args here and use Python CLI utilities like argparse
        # to do argument parsing
        args = gdb.string_to_argv(args)

        if len(args) != 2:
            print("Expected two arguments: <addr> <size>")

        addr = gdb.parse_and_eval(args[0])
        size = gdb.parse_and_eval(args[1])

        if str(addr.type) != "long" and str(addr.type) != "char *":
            print("Expected address argument of type (long) or (char *), got", str(addr.type))
            return

        if str(size.type) != "long":
            print("Expected size argument of type (long), got", str(size.type))
            return

        print(self._len_and_addr_to_str(addr, size))

LengthPrefixedStringDumpCmd()
