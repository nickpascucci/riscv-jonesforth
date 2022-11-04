# Try: make inspect

# Override this on the command line to run other assembly files.
PROGRAM ?= jonesforth

.PHONY: inspect inspectall simulate simulate-forth debug debug-forth size clean

build/%.elf: build/%.o build/fe310_g002.lds
	riscv32-ld --build-id=none -T fe310_g002.lds -o $@ $<

build/%.o: build/%.s
	riscv32-as --march=rv32imac -mabi=ilp32 -gdwarf-5 -o $@ $<

build/%.hex: build/%.elf
	riscv32-objcopy $< -O ihex $@

build/fe310_g002.lds: jonesforth.md
	verso jonesforth.md | recto build/phase1 fe310_g002.lds
	cd build/phase1 && verso ../../jonesforth.md | recto ../ fe310_g002.lds

build/jf.s: jf.nw
	notangle $< > $@

build/jf.tex: jf.nw
	noweave -delay -index $< > $@

build/tests/test_core.py: jonesforth.md tests/test_core.py
	verso jonesforth.md | recto build/phase1 tests/test_core.py
	cd build/phase1 && verso ../../jonesforth.md | recto ../ tests/test_core.py
	cp Pipfile Pipfile.lock build

objdump: build/jf.elf
	riscv32-objdump --source $<

objdumpall: build/jf.elf
	riscv32-objdump --source -j .text -j .rodata -j .bss -j .data $<

readelf: build/jf.elf
	riscv32-readelf -a $<

render: build/jf.tex
	xelatex -halt-on-error -output-directory=build $<
	xelatex -output-directory=build $<

simulate-core: build/jf.elf
	@echo "Running jf in QEMU"
	qemu-system-riscv32 -machine sifive_e -nographic -kernel ${PROGRAM}.elf

simulate-forth: build/jf.elf
	@echo "Running jf with Forth words in QEMU"
	cat jonesforth.f - | qemu-system-riscv32 -machine sifive_e -nographic -kernel ${PROGRAM}.elf

debug-core: build/jf.elf
	@echo "Running jf in QEMU, for debugging"
	@echo "Starting the emulator. Use 'gdb' to debug."
	qemu-system-riscv32 -machine sifive_e -nographic -kernel ${PROGRAM}.elf -S -s

debug-forth: build/jf.elf
	@echo "Running jf. Use 'gdb' to debug."
	cat jonesforth.f - | qemu-system-riscv32 -machine sifive_e -nographic -kernel ${PROGRAM}.elf -S -s

test-core: build/tests/test_core.py build/jf.elf 
	cd build && pipenv install && pipenv run pytest --ignore phase1

size: build/jf.elf
	riscv32-size $<

clean:
	-rm build

install-deps:
	tlmgr install changepage fancyhdr geometry hyperref \
		natbib paralist placeins ragged2e sauerj setspace \
		textcase titlesec xcolor xifthen
