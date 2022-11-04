.PHONY: \
	all clean debug debug-forth hex \
	inspect inspectall install-deps \
	objdump objdumpall pdf readelf \
	simulate simulate-forth size \
	test test-core

all: hex pdf

hex: build/jf.hex

pdf: build/jf.pdf

test: test-core

clean:
	-rm -r build

install-deps:
	tlmgr install changepage csquotes fancyhdr geometry hyperref \
		natbib paralist placeins ragged2e sauerj setspace \
		textcase titlesec xcolor xifthen

build/%.hex: build/%.elf build
	riscv32-objcopy $< -O ihex $@

build/%.elf: build/%.o build/fe310-g002.lds build
	riscv32-ld --build-id=none -T build/fe310-g002.lds -o $@ $<

build/%.o: build/%.s build
	riscv32-as --march=rv32imac -mabi=ilp32 -gdwarf-5 -o $@ $<

build/fe310-g002.lds: jf.nw build
	notangle -R$(shell basename $@) $< > $@

build/jf.s: jf.nw build
	notangle -R$(shell basename $@) $< > $@

build/tests/test_core.py: jf.nw build/tests 
	notangle -Rtests/test_core.py $< > $@

build/%.tex: %.nw build
	# This filter escapes underscores so TeX is happy. This may break subscripting.
	noweave \
		-delay \
		-index \
		-filter 'sed "/^@use /s/_/\\\\_/g;/^@defn /s/_/\\\\_/g;/^@xref /s/_/\\\\_/g"' \
		$< > $@

build/%.pdf: build/%.tex build
	xelatex -halt-on-error -output-directory=build $<
	xelatex -output-directory=build $<

build:
	mkdir -p build

build/tests: 
	mkdir -p build/tests

objdump: build/jf.elf
	riscv32-objdump --source $<

objdumpall: build/jf.elf
	riscv32-objdump --source -j .text -j .rodata -j .bss -j .data $<

readelf: build/jf.elf
	riscv32-readelf -a $<

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
