.PHONY: inspect simulate clean

%.elf: %.o fe310_g002.lds
	riscv32-ld --build-id=none -T fe310_g002.lds -o $@ $<

%.o: %.s
	riscv32-as --march=rv32imac -mabi=ilp32 -g -o $@ $<

inspect: ${PROGRAM}.o
	riscv32-objdump --source -j .text -j .rodata -j .bss $<

simulate: ${PROGRAM}.elf
	@echo "Running ${PROGRAM} in QEMU"
	qemu-system-riscv32 -machine sifive_e -nographic -kernel ${PROGRAM}.elf

debug: ${PROGRAM}.elf
	@echo "Running ${PROGRAM} in QEMU, for debugging"
	@echo "Starting the emulator. Use 'gdb' to debug."
	qemu-system-riscv32 -machine sifive_e -nographic -kernel ${PROGRAM}.elf -S -s

clean:
	-rm *.img *.elf *.o
