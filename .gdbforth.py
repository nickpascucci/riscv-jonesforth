"""
GDB plugin for debugging Jonesforth
"""

import gdb

INFERIOR = gdb.selected_inferior()
ARCHITECTURE = INFERIOR.architecture()
F_IMMED = 0x80
F_HIDDEN = 0x20
F_LENMASK = 0x1f

def align(addr, count):
    """Adjust the given address so it is aligned to the given number of bytes."""
    miss = addr % count
    return addr - miss


def resolve_symbol(addr):
    """Resolve the name of the symbol at ADDR"""
    return gdb.execute(f"info symbol 0x{addr:x}", False, True).strip()


class DictEntryDumpCmd(gdb.Command):
    """Prints a dictionary entry given its CFA."""

    def __init__(self):
        super(DictEntryDumpCmd, self).__init__(
            "lookup", gdb.COMMAND_USER
        )

    def _cfa_to_dfa(self, cfa_addr):
        """Convert a code field address to a dictionary field address."""
        addr = cfa_addr
        for offset in range(64):
            # null padding should be address aligned so we will get a 0 when we hit it
            next_addr = addr - 4
            bs = INFERIOR.read_memory(next_addr, 4)
            val = int.from_bytes(bs, byteorder="little")
            #  print(f"Addr: {next_addr.format_string(format='x')} Size: {len(bs)} Val: {val}")
            if val == 0:
                return addr
            addr = next_addr
        raise ValueError("Could not determine start of dictionary entry")

    def _dict_entry_flag_byte(self, addr):
        b = INFERIOR.read_memory(addr + 4, 1)[0]
        b = int.from_bytes(b, byteorder="little") 
        return b

    def _dict_entry_size(self, addr):
        return self._dict_entry_flag_byte(addr) & F_LENMASK

    def _dict_entry_name(self, addr, size):
        name_mem = INFERIOR.read_memory(addr + 5, size)
        return name_mem.tobytes().decode("ascii")

    def _dict_entry_flags(self, addr):
        flag_byte = self._dict_entry_flag_byte(addr)
        flags = []
        if flag_byte & F_IMMED:
            flags.append("IMMEDIATE")
        if flag_byte & F_HIDDEN:
            flags.append("HIDDEN")

        if flags:
            return ", ".join(flags)
        else:
            return "(None)"

    def _dict_entry_prev(self, addr):
        link_field = INFERIOR.read_memory(addr, 4).tobytes()
        link_addr = int.from_bytes(link_field, byteorder="little") 
        return resolve_symbol(link_addr)

    def _dict_entry_body(self, cfa):
        addr = cfa
        words = []
        for i in range(32):
            mem = INFERIOR.read_memory(addr, 4)
            addr += 4
            word = int.from_bytes(mem, byteorder="little") 
            if word:
                sym = resolve_symbol(word)
                words.append(f" - {sym}")
            else:
                break
        return "\n".join(words)

    def complete(self, text, word):
        # We expect the argument passed to be a symbol so fallback to the
        # internal tab-completion handler for symbols
        return gdb.COMPLETE_SYMBOL

    def invoke(self, args, from_tty):
        cfa = gdb.parse_and_eval(args)

        types = {"int", "long", "char *", "void *"}
        if str(cfa.type) not in types:
            print(f"Expected address argument of type {types}, got", str(cfa.type))
            return

        print("Code Field Address:", cfa.format_string(format="x"))

        addr = self._cfa_to_dfa(cfa)
        print("Dictionary Field Address:", addr.format_string(format="x"))

        size = self._dict_entry_size(addr)
        name = self._dict_entry_name(addr, size)
        print(f"Name:  ({size}) {name}")

        flags = self._dict_entry_flags(addr)
        print(f"Flags: {flags}")

        body = self._dict_entry_body(cfa)
        print(f"Body:\n{body}")

        prev = self._dict_entry_prev(addr)
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
