# Try: make inspect

# Override this on the command line to run other assembly files.
PROGRAM ?= jonesforth

.PHONY: inspect inspectall simulate simulate-forth debug debug-forth size clean

%.elf: %.o fe310_g002.lds
	riscv32-ld --build-id=none -T fe310_g002.lds -o $@ $<

%.o: %.s
	riscv32-as --march=rv32imac -mabi=ilp32 -gdwarf-5 -o $@ $<

%.hex: %.elf
	riscv32-objcopy $< -O ihex $@

inspect: ${PROGRAM}.elf
	riscv32-objdump --source $<

inspectall: ${PROGRAM}.elf
	riscv32-objdump --source -j .text -j .rodata -j .bss -j .data $<

simulate: ${PROGRAM}.elf
	@echo "Running ${PROGRAM} in QEMU"
	qemu-system-riscv32 -machine sifive_e -nographic -kernel ${PROGRAM}.elf

simulate-forth: ${PROGRAM}.elf
	@echo "Running ${PROGRAM} with Forth words in QEMU"
	cat jonesforth.f - | qemu-system-riscv32 -machine sifive_e -nographic -kernel ${PROGRAM}.elf

debug: ${PROGRAM}.elf
	@echo "Running ${PROGRAM} in QEMU, for debugging"
	@echo "Starting the emulator. Use 'gdb' to debug."
	qemu-system-riscv32 -machine sifive_e -nographic -kernel ${PROGRAM}.elf -S -s

debug-forth: ${PROGRAM}.elf
	@echo "Running ${PROGRAM} with Forth words in QEMU, for debugging"
	@echo "Starting the emulator. Use 'gdb' to debug."
	cat jonesforth.f - | qemu-system-riscv32 -machine sifive_e -nographic -kernel ${PROGRAM}.elf -S -s

test-core: jonesforth.elf
	pipenv run pytest

size: ${PROGRAM}.elf
	riscv32-size ${PROGRAM}.elf

clean:
	-rm *.img *.elf *.o *.hex
