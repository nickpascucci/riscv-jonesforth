# Try: make inspect

# Override this on the command line to run other assembly files.
PROGRAM ?= jonesforth

.PHONY: inspect inspectall simulate simulate-forth debug debug-forth size clean

build/%.elf: build/%.o build/fe310-g002.lds
	mkdir -p build
	riscv32-ld --build-id=none -T build/fe310-g002.lds -o $@ $<

build/%.o: build/%.s
	mkdir -p build
	riscv32-as --march=rv32imac -mabi=ilp32 -gdwarf-5 -o $@ $<

build/%.hex: build/%.elf
	mkdir -p build
	riscv32-objcopy $< -O ihex $@

build/fe310-g002.lds: jf.nw
	mkdir -p build
	notangle -R$(shell basename $@) $< > $@

build/jf.s: jf.nw
	mkdir -p build
	notangle -R$(shell basename $@) $< > $@

build/tests/test_core.py: jf.nw
	mkdir -p build/tests
	notangle -Rtests/test_core.py $< > $@

build/%.tex: %.nw
	mkdir -p build
	# This filter escapes underscores in chunk names so TeX is happy.
	noweave \
		-delay \
		-index \
		-filter 'sed "/^@use /s/_/\\\\_/g;/^@defn /s/_/\\\\_/g"' \
		$< > $@

build/%.pdf: build/%.tex
	mkdir -p build
	xelatex -halt-on-error -output-directory=build $<
	xelatex -output-directory=build $<

objdump: build/jf.elf
	riscv32-objdump --source $<

objdumpall: build/jf.elf
	riscv32-objdump --source -j .text -j .rodata -j .bss -j .data $<

readelf: build/jf.elf
	riscv32-readelf -a $<

render: build/jf.pdf

simulate-core: build/jf.elf
	@echo "Running core in QEMU"
	qemu-system-riscv32 -machine sifive_e -nographic -kernel $<

simulate-forth: build/jf.elf
	@echo "Running core with Forth words in QEMU"
	cat jonesforth.f - | qemu-system-riscv32 -machine sifive_e -nographic -kernel $<

debug-core: build/jf.elf
	@echo "Running jf in QEMU, for debugging"
	@echo "Starting the emulator. Use 'gdb' to debug."
	qemu-system-riscv32 -machine sifive_e -nographic -kernel ${PROGRAM}.elf -S -s

debug-forth: build/jf.elf
	@echo "Running in QEMU debug mode. Use 'gdb' to debug."
	cat jonesforth.f - | qemu-system-riscv32 -machine sifive_e -nographic -kernel $< -S -s

test-core: build/tests/test_core.py build/jf.elf 
	cd build && pipenv install && pipenv run pytest

size: build/jf.elf
	riscv32-size $<

clean:
	-rm -r build

install-deps:
	tlmgr install changepage csquotes fancyhdr geometry hyperref \
		natbib paralist placeins ragged2e sauerj setspace \
		textcase titlesec xcolor xifthen
