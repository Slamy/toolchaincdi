# Level 2 ABI tests: build the abirun harness (Musashi) and run the test
# images.  Run inside WSL/Linux.  See OS9-COMPAT-DESIGN.md, section 11.
#
#   make                 build everything and run the tests (-O2)
#   make check           run the tests at -O0, -O2, -Os and -O3, and with
#                        -m68020 -m68881 on an emulated 68040
#   make check-mw MWLIB=DIR  also link with Microware's C library (see below)
#   make check-ucc MWOS=... UCCWORK=...  -mos9call=ucc code calling, and
#                        called by, code Ultra C compiled (see below)
#   make check-mod       run the tests as OS-9 modules made by elf2mod (see below)
#   make check-newlib    run nltests/ with newlib, in both multilibs (see below)
#   make check-lsym      elf2mod's btext, bname and etext (see below)
#   make check-r68       tests with r68-syntax stubs, through r68togas (see below)
#   make check-gastor68  the tests' C side through gastor68 and back (see below)
#   make check-l68 L68=... [MWLIB=...]  run them as modules linked by
#                        Microware's l68, through elf2rof; with MWLIB also
#                        the Level 3 tests, with Microware's clib.l (see below)
#   make check-os9 MWLIB=DIR  run the Level 3 tests on OS-9 itself, in a
#                        CD-i player or CD-i Emulator, through cdirun (see below)
#   make check-os9mix MWLIB=DIR  the same with code compiled by Microware C on
#                        OS-9, linked both ways (see below)
#   make check-os9mod    run the check-mod modules on OS-9 itself (see below)
#   make check-os9newlib run nltests/ on OS-9 itself, with newlib's OS-9 runtime
#   make check-os9math   floating point on OS-9 itself, with -mos9math too
#   make GCC=...         compiler driver to test
#   make BUILD=...       build directory (default ~/build/abi-exec)

HERE    := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
BUILD   ?= $(HOME)/build/abi-exec
GB      ?= $(HOME)/build/gcc-build
GCC     ?= $(GB)/gcc/xgcc -B$(GB)/gcc/
TPREFIX ?= m68k-elfos9-
HOSTCC  ?= gcc
CFLAGS_T = -O2 -mpcrel -ma6rel -mos9call
# The compiler proper of the build tree, when that's the compiler tested:
# objects are rebuilt when it changes (also when libgcc or a test's
# .flags file change).
.SECONDEXPANSION:
CC1     := $(if $(filter $(GB)/gcc/xgcc,$(firstword $(GCC))),$(wildcard $(GB)/gcc/cc1))
ABIRUN_FLAGS =
MUSASHI  = $(HERE)musashi
TESTS    = $(basename $(notdir $(wildcard $(HERE)tests/*.c)))

all: run

# Musashi, with CR/LF line endings removed (its generator expects LF).
MSRC = m68kcpu.c m68kdasm.c m68k_in.c m68kmake.c m68k.h m68kconf.h \
       m68kcpu.h m68kfpu.c m68kmmu.h softfloat/softfloat.c \
       softfloat/softfloat.h softfloat/softfloat-macros \
       softfloat/softfloat-specialize softfloat/mamesf.h softfloat/milieu.h
$(BUILD)/m/.copied: $(addprefix $(MUSASHI)/,$(MSRC))
	mkdir -p $(BUILD)/m/softfloat
	for f in $(MSRC); do tr -d '\r' < $(MUSASHI)/$$f > $(BUILD)/m/$$f; done
	touch $@

$(BUILD)/m/m68kops.c: $(BUILD)/m/.copied
	cd $(BUILD)/m && $(HOSTCC) -o m68kmake m68kmake.c && ./m68kmake . m68k_in.c > /dev/null

$(BUILD)/abirun: $(HERE)harness.c $(BUILD)/m/m68kops.c
	$(HOSTCC) -O2 -w -I$(BUILD)/m -o $@ $(HERE)harness.c \
	  $(BUILD)/m/m68kcpu.c $(BUILD)/m/m68kops.c $(BUILD)/m/m68kdasm.c \
	  $(BUILD)/m/softfloat/softfloat.c -lm

# Test images: crt0, support (memcpy, memset), the test's C file and
# its assembly stubs (tests/NAME.S).
# tests/NAME.flags, if present, replaces the compiler flags.
$(BUILD)/%.elf: $(HERE)tests/%.c $(HERE)tests/%.S $(HERE)crt0.S $(HERE)support.S $(HERE)abi.lds $(CC1) \
	$$(wildcard $(HERE)tests/$$*.flags) $$(LIBGCC)
	mkdir -p $(BUILD)
	$(GCC) -c $(or $(file <$(HERE)tests/$*.flags),$(CFLAGS_T)) -o $(BUILD)/$*.o $(HERE)tests/$*.c
	$(TPREFIX)as -m68000 --pcrel -o $(BUILD)/$*-stubs.o $(HERE)tests/$*.S
	$(TPREFIX)as -m68000 --pcrel -o $(BUILD)/crt0.o $(HERE)crt0.S
	$(TPREFIX)as -m68000 --pcrel -o $(BUILD)/support.o $(HERE)support.S
	$(TPREFIX)ld --no-check-sections -T $(HERE)abi.lds -o $@ $(BUILD)/crt0.o $(BUILD)/$*.o \
	  $(BUILD)/$*-stubs.o $(BUILD)/support.o $(LIBGCC)

LIBGCC = $(shell $(GCC) -print-libgcc-file-name)

run: $(BUILD)/abirun $(TESTS:%=$(BUILD)/%.elf)
	@fail=0; for t in $(TESTS); do \
	  if $(BUILD)/abirun $(ABIRUN_FLAGS) $(BUILD)/$$t.elf; then echo "PASS: $$t"; \
	  else echo "FAIL: $$t"; fail=1; fi; done; exit $$fail

check:
	@for o in O0 O2 Os O3; do echo "== -$$o"; \
	  $(MAKE) --no-print-directory BUILD=$(BUILD)/$$o \
	    CFLAGS_T="-$$o -mpcrel -ma6rel -mos9call" run || exit 1; done
	@echo "== -O2 -m68020 -m68881 (68040)"; \
	  $(MAKE) --no-print-directory BUILD=$(BUILD)/fpu ABIRUN_FLAGS="-c 68040" \
	    CFLAGS_T="-O2 -m68020 -m68881 -mpcrel -ma6rel -mos9call -w" run

# Level 3 (partial): tests linked with Microware's C library (cstart.r,
# clib.l), converted with rof2elf from src/elf2mod.  Microware's files
# are proprietary and not included: point MWLIB at a directory holding
# cstart.r, clib.l and sys.l (lower or upper case).
#   make check-mw MWLIB=/path/to/LIB
MWLIB    ?=
CFLAGS_MW = -O2 -mpcrel -ma6rel -mos9call -mbuiltin=os9call -w
MWTESTS   = $(basename $(notdir $(wildcard $(HERE)mwtests/*.c)))
mwfile    = $(firstword $(wildcard $(MWLIB)/$(1) $(MWLIB)/$(shell echo $(1) | tr a-z A-Z)))

$(BUILD)/rof2elf: $(HERE)../../src/elf2mod/rof2elf.c $(HERE)../../src/elf2mod/r68x_note.c $(HERE)../../src/elf2mod/r68x_note.h
	mkdir -p $(BUILD)
	$(HOSTCC) -O2 -o $@ $< $(HERE)../../src/elf2mod/r68x_note.c

# sys.l too, as an archive: rof2elf leaves its equates (F$Exit, E$BMode)
# external where a relocation takes them, as r68 does, so a link needs
# it, as l68's does.
$(BUILD)/mw/cstart.o $(BUILD)/mw/clib.a $(BUILD)/mw/sys.a: $(BUILD)/rof2elf
	@[ -n "$(call mwfile,clib.l)" ] || { echo "check-mw: set MWLIB to the directory with cstart.r, clib.l and sys.l"; exit 2; }
	mkdir -p $(BUILD)/mw
	$(BUILD)/rof2elf -o $(BUILD)/mw/cstart.o $(call mwfile,cstart.r)
	$(BUILD)/rof2elf -o $(BUILD)/mw/clib.a $(call mwfile,clib.l)
	$(TPREFIX)ranlib $(BUILD)/mw/clib.a
	$(BUILD)/rof2elf -o $(BUILD)/mw/sys.a $(call mwfile,sys.l)
	$(TPREFIX)ranlib $(BUILD)/mw/sys.a

# The harness's crt0 is the entry point (abirun has no OS-9 system
# calls for cstart's startup), so cstart only provides its variables and
# functions: without its module header symbols (__os9_*), which crt0
# defines.
$(BUILD)/mw/cstart-sub.o: $(BUILD)/mw/cstart.o
	$(TPREFIX)objcopy -w --strip-symbol='__os9_*' $< $@

$(BUILD)/mw/%.elf: $(HERE)mwtests/%.c $(HERE)crt0.S $(HERE)abi.lds $(CC1) $(BUILD)/mw/cstart-sub.o $(BUILD)/mw/clib.a \
	$(BUILD)/mw/sys.a $$(wildcard $(HERE)mwtests/$$*.flags) $$(LIBGCC)
	$(GCC) -c $(or $(file <$(HERE)mwtests/$*.flags),$(CFLAGS_MW)) -o $(BUILD)/mw/$*.o $<
	$(TPREFIX)as -m68000 --pcrel -o $(BUILD)/mw/crt0.o $(HERE)crt0.S
	sh $(HERE)r68xld.sh $(TPREFIX)ld --no-check-sections -T $(HERE)abi.lds -o $@ $(BUILD)/mw/crt0.o $(BUILD)/mw/$*.o \
	  $(BUILD)/mw/cstart-sub.o $(BUILD)/mw/clib.a $(LIBGCC) $(BUILD)/mw/sys.a

check-mw: $(BUILD)/abirun $(MWTESTS:%=$(BUILD)/mw/%.elf)
	@fail=0; for t in $(MWTESTS); do \
	  if $(BUILD)/abirun $(BUILD)/mw/$$t.elf; then echo "PASS: mw/$$t"; \
	  else echo "FAIL: mw/$$t"; fail=1; fi; done; exit $$fail

# Ultra C's convention (-mos9call=ucc): ucctests/NAME.c, compiled by GCC,
# linked with ucctests/NAME-mw.c compiled by Microware Ultra C's own xcc
# (ANSI mode, -r: no stack checking, so no library), and run.  Ultra C is
# proprietary and not included: MWOS is its MWOS tree as a Windows path,
# UCCWORK a directory on a Windows drive (/mnt/c/...) where xcc runs,
# through cmd.exe (it can't be run from WSL directly); its output is
# converted with rof2elf and removed there.
#   make check-ucc MWOS='C:\path\to\mwos' UCCWORK=/mnt/c/path/to/dir
UCCWORK  ?=
CFLAGS_UCC = -O2 -mpcrel -ma6rel -mos9call=ucc -w
UCCTESTS  = $(filter-out %-mw,$(basename $(notdir $(wildcard $(HERE)ucctests/*.c))))

$(BUILD)/ucc/%-mw.o: $(HERE)ucctests/%-mw.c $(BUILD)/rof2elf
	@[ -n "$(MWOS)" ] && [ -n "$(UCCWORK)" ] || { echo "check-ucc: set MWOS (Ultra C's MWOS tree, a Windows path) and UCCWORK (a directory on a Windows drive)"; exit 2; }
	mkdir -p $(BUILD)/ucc $(UCCWORK)
	cp $< $(UCCWORK)/$*-mw.c
	cd $(UCCWORK) && cmd.exe /c 'set PATH=$(MWOS)\DOS\BIN;%PATH%&& set MWOS=$(MWOS)&& xcc -e=as -r -to=osk -tp=68k $*-mw.c' < /dev/null
	$(BUILD)/rof2elf -o $@ $(UCCWORK)/$*-mw.r
	rm -f $(UCCWORK)/$*-mw.c $(UCCWORK)/$*-mw.r

$(BUILD)/ucc/%.elf: $(HERE)ucctests/%.c $(BUILD)/ucc/%-mw.o $(HERE)crt0.S $(HERE)abi.lds $(CC1) $$(LIBGCC)
	$(GCC) -c $(CFLAGS_UCC) -o $(BUILD)/ucc/$*.o $<
	$(TPREFIX)as -m68000 --pcrel -o $(BUILD)/ucc/crt0.o $(HERE)crt0.S
	$(TPREFIX)ld --no-check-sections -T $(HERE)abi.lds -o $@ $(BUILD)/ucc/crt0.o $(BUILD)/ucc/$*.o \
	  $(BUILD)/ucc/$*-mw.o $(LIBGCC)

check-ucc: $(BUILD)/abirun $(UCCTESTS:%=$(BUILD)/ucc/%.elf)
	@fail=0; for t in $(UCCTESTS); do \
	  if $(BUILD)/abirun $(BUILD)/ucc/$$t.elf; then echo "PASS: ucc/$$t"; \
	  else echo "FAIL: ucc/$$t"; fail=1; fi; done; exit $$fail

# Modules: the tests linked with -q, converted by elf2mod (from
# src/elf2mod, with the BFD library under BFDPATH) and run as OS-9 modules
# (abirun -m, which checks the header parity and CRC like OS-9; the .stb
# symbol modules from elf2mod -g are checked with abirun -v); plus
# modtests/, whose far calls go through elf2mod's _jmptbl (linked with
# --noinhibit-exec, which keeps the output despite the truncated
# relocations).
#   make check-mod
BFDPATH  ?= $(HOME)/build/install/x86_64-pc-linux-gnu/m68k-elfos9
JMPTBL    = 60
MODTESTS  = $(basename $(notdir $(wildcard $(HERE)modtests/*.c)))

$(BUILD)/elf2mod: $(HERE)../../src/elf2mod/elf2mod.c $(HERE)../../src/elf2mod/r68x_note.c $(HERE)../../src/elf2mod/r68x_note.h
	mkdir -p $(BUILD)
	tr -d '\r' < $< > $(BUILD)/elf2mod.c
	$(HOSTCC) -O2 -w -I$(BFDPATH)/include -I$(HERE)../../src/elf2mod -o $@ $(BUILD)/elf2mod.c \
	  $(HERE)../../src/elf2mod/r68x_note.c $(BFDPATH)/lib/libbfd.a -liberty -lz -ldl

$(BUILD)/%.mod: $(BUILD)/%.elf $(BUILD)/elf2mod
	$(TPREFIX)ld -q --no-check-sections -T $(HERE)abi.lds -o $(BUILD)/$*.qelf \
	  $(BUILD)/crt0.o $(BUILD)/$*.o $(BUILD)/$*-stubs.o $(BUILD)/support.o $(LIBGCC)
	$(BUILD)/elf2mod -g -n $* $(BUILD)/$*.qelf $@ > /dev/null

$(BUILD)/far/%.mod: $(HERE)modtests/%.c $(HERE)modtests/%.S $(HERE)crt0.S $(HERE)support.S $(HERE)abi.lds $(CC1) $(BUILD)/elf2mod \
	$$(LIBGCC)
	mkdir -p $(BUILD)/far
	$(GCC) -c $(CFLAGS_T) $(FARFLAGS) -o $(BUILD)/far/$*.o $<
	$(TPREFIX)as -m68000 --pcrel -o $(BUILD)/far/$*-stubs.o $(HERE)modtests/$*.S
	$(TPREFIX)as -m68000 --pcrel -o $(BUILD)/far/crt0.o $(HERE)crt0.S
	$(TPREFIX)as -m68000 --pcrel -o $(BUILD)/far/support.o $(HERE)support.S
	$(TPREFIX)ld -q --noinhibit-exec --no-check-sections \
	  --defsym __jmptbl_size=$(JMPTBL) -T $(HERE)abi.lds -o $(BUILD)/far/$*.elf \
	  $(BUILD)/far/crt0.o $(BUILD)/far/$*.o $(BUILD)/far/$*-stubs.o \
	  $(BUILD)/far/support.o $(LIBGCC) 2> $(BUILD)/far/$*.ld.log
	$(BUILD)/elf2mod -n $* $(BUILD)/far/$*.elf $@

run-mod: $(BUILD)/abirun $(TESTS:%=$(BUILD)/%.mod) $(MODTESTS:%=$(BUILD)/far/%.mod)
	@fail=0; for t in $(TESTS:%=$(BUILD)/%.mod) $(MODTESTS:%=$(BUILD)/far/%.mod); do \
	  if $(BUILD)/abirun $(ABIRUN_FLAGS) -m $$t && \
	     { [ ! -f $$t.stb ] || $(BUILD)/abirun -v $$t.stb; }; then echo "PASS: $$(basename $$t)"; \
	  else echo "FAIL: $$(basename $$t)"; fail=1; fi; done; exit $$fail

check-mod:
	@for o in O2 O2bsrw; do echo "== modules, -$$o"; \
	  $(MAKE) --no-print-directory BUILD=$(BUILD)/mod-$$o \
	    CFLAGS_T="$$(echo -$$o | sed 's/bsrw/ -mbsrw/') -mpcrel -ma6rel -mos9call" run-mod || exit 1; done

# newlib, in each multilib: nltests/ compiled with GCC's stack convention
# and with -mos9call, and linked with the libc of that multilib (the
# installed newlib, built with --enable-multilib).  newlib's stdio makes
# the program larger than the 32 KB that calls reach, so it runs as an
# OS-9 module with elf2mod's jump table, as a real program would.
#   make check-newlib
NLTESTS  = $(basename $(notdir $(wildcard $(HERE)nltests/*.c)))
NLJMPTBL = 600
CONV     =
MATH     =
# The installed newlib (the build tree's xgcc doesn't search it); the
# compiler picks the multilib directory.
NEWLIB  ?= $(HOME)/build/install/m68k-elfos9

NLLIBC   = $(NEWLIB)/lib/$(shell $(GCC) $(CONV) -print-multi-directory)/libc.a

$(BUILD)/%.nlmod: $(HERE)nltests/%.c $(HERE)crt0.S $(HERE)abi.lds $(CC1) $(BUILD)/elf2mod \
	$$(NLLIBC) $$(LIBGCC)
	mkdir -p $(BUILD)
	$(GCC) -c -O2 -mpcrel -ma6rel $(CONV) -isystem $(NEWLIB)/include -o $(BUILD)/$*.o $<
	$(TPREFIX)as -m68000 --pcrel -o $(BUILD)/crt0.o $(HERE)crt0.S
	$(TPREFIX)ld -q --noinhibit-exec --no-check-sections --defsym __jmptbl_size=$(NLJMPTBL) \
	  -T $(HERE)abi.lds -o $(BUILD)/$*.nlelf $(BUILD)/crt0.o $(BUILD)/$*.o \
	  $(NLLIBC) \
	  $$($(GCC) $(CONV) -print-libgcc-file-name) 2> $(BUILD)/$*.ld.log
	$(BUILD)/elf2mod $(BUILD)/$*.nlelf $@

run-newlib: $(BUILD)/abirun $(NLTESTS:%=$(BUILD)/%.nlmod)
	@fail=0; for t in $(NLTESTS); do \
	  if $(BUILD)/abirun -m $(BUILD)/$$t.nlmod; then echo "PASS: $$t"; \
	  else echo "FAIL: $$t"; fail=1; fi; done; exit $$fail

check-newlib:
	@echo "== newlib, stack convention"; \
	  $(MAKE) --no-print-directory BUILD=$(BUILD)/nl-stack CONV= run-newlib || exit 1; \
	  echo "== newlib, -mos9call (multilib $$($(GCC) -mos9call -print-multi-directory))"; \
	  $(MAKE) --no-print-directory BUILD=$(BUILD)/nl-os9call CONV=-mos9call run-newlib

# Microware's linker: the same objects converted by elf2rof (from
# src/elf2mod), linked with l68 and run as OS-9 modules; modtests/ with
# l68 -a, which builds l68's own jump table.  l68 -a only redirects bsr.w
# and lea (unlike elf2mod, it doesn't redirect bra.w, which -mbsrw uses
# for tail calls), so modtests/ are compiled without tail calls here.  The
# whole of libgcc converts (its soft-float routines no longer use a GOT).
# l68 is proprietary and not included; Ultra C's Windows
# l68.exe runs from WSL:
#   make check-l68 L68=/mnt/c/path/to/DOS/BIN/l68.exe [MWLIB=/path/to/LIB]
L68 ?=

$(BUILD)/elf2rof: $(HERE)../../src/elf2mod/elf2rof.c $(HERE)../../src/elf2mod/r68x_note.c $(HERE)../../src/elf2mod/r68x_note.h
	mkdir -p $(BUILD)
	$(HOSTCC) -O2 -o $@ $< $(HERE)../../src/elf2mod/r68x_note.c

$(BUILD)/libgcc.l: $(BUILD)/elf2rof $$(LIBGCC)
	$(BUILD)/elf2rof -o $@ $(LIBGCC)

l68link = cd $(1) && for f in $(2); do ./$(3)elf2rof -o $$f.r $$f.o || exit 1; done && \
	  $(L68) $(4) -n=$(5) -o=$(5).lmod $(2:%=%.r) -l=$(3)libgcc.l > $(5).l68.log

$(BUILD)/%.lmod: $(BUILD)/%.elf $(BUILD)/elf2rof $(BUILD)/libgcc.l
	@[ -n "$(L68)" ] || { echo "check-l68: set L68 to Microware's l68"; exit 2; }
	$(call l68link,$(BUILD),crt0 $* $*-stubs support,,,$*)

$(BUILD)/far/%.lmod: $(BUILD)/far/%.mod $(BUILD)/elf2rof $(BUILD)/libgcc.l
	@[ -n "$(L68)" ] || { echo "check-l68: set L68 to Microware's l68"; exit 2; }
	$(call l68link,$(BUILD)/far,crt0 $* $*-stubs support,../,-a,$*)

# With MWLIB as well: the Level 3 tests (mwtests/) linked by l68 with
# Microware's own clib.l (the original, not converted) and cstart as a
# subroutine psect (rof2elf, without __os9_*, back through elf2rof).
$(BUILD)/mw/%.lmod: $(BUILD)/mw/%.elf $(BUILD)/elf2rof $(BUILD)/libgcc.l
	@[ -n "$(L68)" ] || { echo "check-l68: set L68 to Microware's l68"; exit 2; }
	cp $(call mwfile,clib.l) $(BUILD)/mw/clib.l
	cp $(call mwfile,sys.l) $(BUILD)/mw/sys.l
	cd $(BUILD)/mw && for f in crt0 $* cstart-sub; do ../elf2rof -o $$f.r $$f.o || exit 1; done && \
	  $(L68) -n=$* -o=$*.lmod crt0.r $*.r cstart-sub.r -l=clib.l -l=../libgcc.l -l=sys.l > $*.l68.log

run-mw-l68: $(BUILD)/abirun $(MWTESTS:%=$(BUILD)/mw/%.lmod)
	@fail=0; for t in $(MWTESTS); do \
	  if $(BUILD)/abirun -m $(BUILD)/mw/$$t.lmod; then echo "PASS: mw/$$t.lmod"; \
	  else echo "FAIL: mw/$$t.lmod"; fail=1; fi; done; exit $$fail

run-l68: $(BUILD)/abirun $(TESTS:%=$(BUILD)/%.lmod) $(MODTESTS:%=$(BUILD)/far/%.lmod)
	@fail=0; for t in $(TESTS:%=$(BUILD)/%.lmod) $(MODTESTS:%=$(BUILD)/far/%.lmod); do \
	  if $(BUILD)/abirun $(ABIRUN_FLAGS) -m $$t; then echo "PASS: $$(basename $$t)"; \
	  else echo "FAIL: $$(basename $$t)"; fail=1; fi; done; exit $$fail

check-l68:
	@for o in O2 O2bsrw; do echo "== l68, -$$o"; \
	  $(MAKE) --no-print-directory BUILD=$(BUILD)/l68-$$o \
	    FARFLAGS=-fno-optimize-sibling-calls \
	    CFLAGS_T="$$(echo -$$o | sed 's/bsrw/ -mbsrw/') -mpcrel -ma6rel -mos9call" run-l68 || exit 1; done
	@[ -z "$(MWLIB)" ] || { echo "== l68, Microware's clib.l"; \
	  $(MAKE) --no-print-directory BUILD=$(BUILD)/l68-mw run-mw-l68; }

# elf2mod's module symbols (btext, bname, etext, which Microware's libraries
# use): lsymtests/lsym.S refers to them near, far and from the data; linked
# with GNU ld (--noinhibit-exec: ld reports the far ones as truncated, and
# elf2mod puts them through the jump table), as is and with 40 KB of
# initialized data (lsymbig); lsymcheck checks every reference in the
# module.  Needs no Microware files.
#   make check-lsym
LSYMVARIANTS = lsym lsymbig

$(BUILD)/lsymcheck: $(HERE)lsymtests/lsymcheck.c
	mkdir -p $(BUILD)
	$(HOSTCC) -O2 -o $@ $<

$(BUILD)/lsym/%.mod: $(HERE)lsymtests/lsym.S $(HERE)lsymtests/lsym.ld $(BUILD)/elf2mod
	mkdir -p $(BUILD)/lsym
	$(TPREFIX)as -m68000 $(if $(filter lsymbig,$*),--defsym BIGDATA=1) -o $(BUILD)/lsym/$*.o $<
	$(TPREFIX)ld -q --no-check-sections --noinhibit-exec -T $(HERE)lsymtests/lsym.ld \
	  --defsym __jmptbl_size=60 -o $(BUILD)/lsym/$*.elf $(BUILD)/lsym/$*.o \
	  2> $(BUILD)/lsym/$*.ld.log || test -s $(BUILD)/lsym/$*.elf
	$(BUILD)/elf2mod -n $* $(BUILD)/lsym/$*.elf $@ > /dev/null

check-lsym: $(BUILD)/lsymcheck $(LSYMVARIANTS:%=$(BUILD)/lsym/%.mod)
	@fail=0; for t in $(LSYMVARIANTS); do \
	  if $(BUILD)/lsymcheck $(BUILD)/lsym/$$t.mod > $(BUILD)/lsym/$$t.log; \
	  then echo "PASS: lsym/$$t"; else echo "FAIL: lsym/$$t"; cat $(BUILD)/lsym/$$t.log; fail=1; fi; \
	done; exit $$fail

# r68togas: tests whose assembly side is written in Microware's r68
# syntax (r68tests/NAME.a, the same code as tests/NAME.S), translated by
# m68k-os9-r68 built from src/elf2mod (r68togas, GNU as, the object's
# names); linked and run as the tests are.  Needs no Microware files.
#   make check-r68
R68TESTS = $(basename $(notdir $(wildcard $(HERE)r68tests/*.a)))

$(BUILD)/r68togas: $(HERE)../../src/elf2mod/r68togas.c $(HERE)../../src/elf2mod/r68x_note.c $(HERE)../../src/elf2mod/r68x_note.h
	mkdir -p $(BUILD)
	$(HOSTCC) -O2 -o $@ $< $(HERE)../../src/elf2mod/r68x_note.c

# m68k-os9-r68, the front end that runs r68togas and gas and gives the
# object's symbols their names back (one named like a register is NAME__r68
# for gas), as it assembles r68 sources
OS9SRC  := $(HERE)../../src/elf2mod
FE_SRCS := $(addprefix $(OS9SRC)/,os9conv.c os9link.c hostsys.c r68x_note.c asmsyntax.c)
$(BUILD)/m68k-os9-r68: $(OS9SRC)/m68k-os9-r68.c $(FE_SRCS) $(wildcard $(OS9SRC)/*.h) $(BUILD)/r68togas
	mkdir -p $(BUILD)
	$(HOSTCC) -O2 -I/usr/include/libiberty -o $@ $< $(FE_SRCS) -liberty

$(BUILD)/r68/%.elf: $(HERE)tests/%.c $(HERE)r68tests/%.a $(BUILD)/m68k-os9-r68 $(HERE)crt0.S $(HERE)support.S \
	$(HERE)abi.lds $(CC1) $$(wildcard $(HERE)tests/$$*.flags) $$(LIBGCC)
	mkdir -p $(BUILD)/r68
	$(GCC) -c $(or $(file <$(HERE)tests/$*.flags),$(CFLAGS_T)) -o $(BUILD)/r68/$*.o $(HERE)tests/$*.c
	$(BUILD)/m68k-os9-r68 -q -m0 $(HERE)r68tests/$*.a -o=$(BUILD)/r68/$*-stubs.o
	$(TPREFIX)as -m68000 --pcrel -o $(BUILD)/r68/crt0.o $(HERE)crt0.S
	$(TPREFIX)as -m68000 --pcrel -o $(BUILD)/r68/support.o $(HERE)support.S
	$(TPREFIX)ld --no-check-sections -T $(HERE)abi.lds -o $@ $(BUILD)/r68/crt0.o $(BUILD)/r68/$*.o \
	  $(BUILD)/r68/$*-stubs.o $(BUILD)/r68/support.o $(LIBGCC)

check-r68: $(BUILD)/abirun $(R68TESTS:%=$(BUILD)/r68/%.elf)
	@fail=0; for t in $(R68TESTS); do \
	  if $(BUILD)/abirun $(BUILD)/r68/$$t.elf; then echo "PASS: r68/$$t"; \
	  else echo "FAIL: r68/$$t"; fail=1; fi; done; exit $$fail

# gastor68: the tests' C side compiled to assembler (-S), translated to
# r68 syntax by gastor68, assembled by m68k-os9-r68 (r68togas, GNU as), and run
# as the tests are; at -O0 and -O2.
#   make check-gastor68
$(BUILD)/gastor68: $(HERE)../../src/elf2mod/gastor68.c
	mkdir -p $(BUILD)
	$(HOSTCC) -O2 -o $@ $<

$(BUILD)/g68/%.elf: $(HERE)tests/%.c $(HERE)tests/%.S $(BUILD)/gastor68 $(BUILD)/m68k-os9-r68 $(HERE)crt0.S \
	$(HERE)support.S $(HERE)abi.lds $(CC1) $$(wildcard $(HERE)tests/$$*.flags) $$(LIBGCC)
	mkdir -p $(BUILD)/g68
	$(GCC) -S $(or $(file <$(HERE)tests/$*.flags),$(CFLAGS_T)) -o $(BUILD)/g68/$*.s $(HERE)tests/$*.c
	$(BUILD)/gastor68 -o $(BUILD)/g68/$*.a $(BUILD)/g68/$*.s
	$(BUILD)/m68k-os9-r68 -q -m$(if $(findstring 68020,$(CFLAGS_T)),2,0) $(BUILD)/g68/$*.a -o=$(BUILD)/g68/$*.o
	$(TPREFIX)as -m68000 --pcrel -o $(BUILD)/g68/$*-stubs.o $(HERE)tests/$*.S
	$(TPREFIX)as -m68000 --pcrel -o $(BUILD)/g68/crt0.o $(HERE)crt0.S
	$(TPREFIX)as -m68000 --pcrel -o $(BUILD)/g68/support.o $(HERE)support.S
	$(TPREFIX)ld --no-check-sections -T $(HERE)abi.lds -o $@ $(BUILD)/g68/crt0.o $(BUILD)/g68/$*.o \
	  $(BUILD)/g68/$*-stubs.o $(BUILD)/g68/support.o $(LIBGCC)

run-gastor68: $(BUILD)/abirun $(TESTS:%=$(BUILD)/g68/%.elf)
	@fail=0; for t in $(TESTS); do \
	  if $(BUILD)/abirun $(ABIRUN_FLAGS) $(BUILD)/g68/$$t.elf; then echo "PASS: g68/$$t"; \
	  else echo "FAIL: g68/$$t"; fail=1; fi; done; exit $$fail

check-gastor68:
	@for o in O0 O2; do echo "== gastor68, -$$o"; \
	  $(MAKE) --no-print-directory BUILD=$(BUILD)/g68-$$o \
	    CFLAGS_T="-$$o -mpcrel -ma6rel -mos9call" run-gastor68 || exit 1; done

# OS-9 itself: the Level 3 tests (mwtests/) built with -DREAL_OS9, which
# adds checks needing system calls (memory, files, the math trap), as real
# modules: Microware's cstart.r as the startup (rof2elf, with its __os9_*
# symbols for the module header), GNU ld with ../l68cmp/mod.lds, elf2mod.
# cdirun (CD-i Emulator's command runner, a Windows program, which runs
# from WSL) copies each one with Kermit to a CD-i player or CD-i Emulator,
# loads it and runs it; a test passes when it exits with status 0, its
# mask of failed checks (from bit 1 on, as the OS-9 shell doesn't report a
# status of 1), which cdirun -st writes as a Status line (its exit code may
# lose all but the low 8 bits on the way to make).  The OS-9 shell must be
# at its prompt, with kermit on its execution path and a writable current
# directory, where the tests are copied.  A test with mwtests/NAME.status
# must exit with the status given there instead (GGG:NNN, as cdirun writes
# it): stkover, -mos9stkchk's overflow path.  Like check-mw, this needs MWLIB:
#   make check-os9 MWLIB=DIR [CDIRUN=/mnt/c/path/to/cdirun.exe] [CDIRUN_FLAGS='-p term:duarta']
CDIRUN       ?= cdirun.exe
CDIRUN_FLAGS ?=
OS9TESTS      = $(MWTESTS)

$(BUILD)/os9/%: $(HERE)mwtests/%.c $(HERE)../l68cmp/mod.lds $(CC1) $(BUILD)/mw/cstart.o $(BUILD)/mw/clib.a \
	$(BUILD)/mw/sys.a $(BUILD)/elf2mod $$(wildcard $(HERE)mwtests/$$*.flags) $$(LIBGCC)
	mkdir -p $(BUILD)/os9
	$(GCC) -c -DREAL_OS9 $(or $(file <$(HERE)mwtests/$*.flags),$(CFLAGS_MW)) -o $@.o $<
	sh $(HERE)r68xld.sh $(TPREFIX)ld -q --no-check-sections -T $(HERE)../l68cmp/mod.lds -o $@.elf \
	  $(BUILD)/mw/cstart.o $@.o $(BUILD)/mw/clib.a $(LIBGCC) $(BUILD)/mw/sys.a
	$(BUILD)/elf2mod -n $* $@.elf $@ > /dev/null
	if [ -f $(HERE)mwtests/$*.status ]; then cp $(HERE)mwtests/$*.status $@.want; \
	  else rm -f $@.want; fi

# $(call os9-run,DIR,MODULES): runs the module files in DIR, each named
# as its module, on OS-9.  For each one: the old file and module go first
# (errors ignored), then copy, make it executable, load it from the
# current directory and run it; it must exit with status 0, or the one in
# DIR/MODULE.want.
os9-run = cd $(1) && fail=0; for t in $(2); do \
	  $(CDIRUN) $(CDIRUN_FLAGS) "unlink $$t" > /dev/null 2>&1; \
	  $(CDIRUN) $(CDIRUN_FLAGS) "del $$t" > /dev/null 2>&1; \
	  if $(CDIRUN) $(CDIRUN_FLAGS) -dc $$t > $$t.log 2>&1 \
	    && $(CDIRUN) $(CDIRUN_FLAGS) "attr $$t -e -pe; load -d $$t" >> $$t.log 2>&1 \
	    && { $(CDIRUN) $(CDIRUN_FLAGS) -t 60 -st $$t >> $$t.log 2>&1; \
	         grep -q "^Status $$(cat $$t.want 2> /dev/null || echo 000:000)" $$t.log; }; \
	  then echo "PASS: $$(basename $(1))/$$t"; else echo "FAIL: $$(basename $(1))/$$t"; \
	    cat $$t.log; fail=1; fi; done; exit $$fail

check-os9: $(OS9TESTS:%=$(BUILD)/os9/%)
	@$(call os9-run,$(BUILD)/os9,$(OS9TESTS))

# OS-9 itself, mixed: mixtests/mwside.c compiled by Microware C on OS-9,
# mixtests/gccside.c by GCC, linked both by Microware's cc on OS-9 (through
# elf2rof) and by GNU ld (through rof2elf), and run there; plus a build with
# one deliberate mismatch, which must fail just that check.  See
# mixtests/run.sh.  The same setup as check-os9; OS9_CCFLAGS goes to cc on
# OS-9, for instance -t=/r512 for its temporary files.
#   make check-os9mix MWLIB=DIR [CDIRUN=...] [CDIRUN_FLAGS=...] [OS9_CCFLAGS=...]
OS9_CCFLAGS ?=

check-os9mix: $(BUILD)/elf2rof $(BUILD)/rof2elf $(BUILD)/elf2mod $(BUILD)/mw/cstart.o $(BUILD)/mw/clib.a \
	$(BUILD)/mw/sys.a $(CC1)
	@HERE=$(HERE) BUILD=$(BUILD) GCC="$(GCC)" TPREFIX=$(TPREFIX) CFLAGS_MW="$(CFLAGS_MW)" \
	  CDIRUN="$(CDIRUN)" CDIRUN_FLAGS="$(CDIRUN_FLAGS)" OS9_CCFLAGS="$(OS9_CCFLAGS)" \
	  CSTART=$(BUILD)/mw/cstart.o CLIB=$(BUILD)/mw/clib.a SYSA=$(BUILD)/mw/sys.a \
	  MATHL=$(call mwfile,math.l) LIBGCC=$(LIBGCC) \
	  sh $(HERE)mixtests/run.sh

# OS-9 itself, Level 2: the check-mod modules (tests/ and modtests/, at
# -O2, linked with the harness's crt0, which exits with F$Exit; smoke
# writes with I$Write), run through cdirun like check-os9, but without
# Microware's files.  The modules are copied without their .mod suffix.
#   make check-os9mod [CDIRUN=...] [CDIRUN_FLAGS=...]
OS9MODS = $(TESTS) $(MODTESTS)

run-os9mod: $(TESTS:%=$(BUILD)/%.mod) $(MODTESTS:%=$(BUILD)/far/%.mod)
	@mkdir -p $(BUILD)/os9mod
	@for t in $(TESTS); do cp $(BUILD)/$$t.mod $(BUILD)/os9mod/$$t; done
	@for t in $(MODTESTS); do cp $(BUILD)/far/$$t.mod $(BUILD)/os9mod/$$t; done
	@$(call os9-run,$(BUILD)/os9mod,$(OS9MODS))

check-os9mod:
	@$(MAKE) --no-print-directory BUILD=$(BUILD)/mod-O2 \
	  CFLAGS_T="-O2 -mpcrel -ma6rel -mos9call" run-os9mod

# OS-9 itself, newlib: nltests/ built with -DREAL_OS9 as real programs,
# with newlib's OS-9 runtime (libgloss: -specs=os9.specs, which brings
# its startup, system calls and linker script), in both multilibs, and
# run through cdirun like check-os9.  Needs the installed newlib (NEWLIB).
#   make check-os9newlib [CDIRUN=...] [CDIRUN_FLAGS=...]
NLDIR = $(NEWLIB)/lib/$(shell $(GCC) $(CONV) -print-multi-directory)

$(BUILD)/os9nl/%: $(HERE)nltests/%.c $(CC1) $(BUILD)/elf2mod $$(NLLIBC) $$(LIBGCC)
	mkdir -p $(BUILD)/os9nl
	$(GCC) $(CONV) -specs=$(NEWLIB)/lib/os9.specs -B$(NLDIR)/ -L$(NLDIR) \
	  -L$$(dirname $$($(GCC) $(CONV) -print-libgcc-file-name)) -isystem $(NEWLIB)/include \
	  -O2 -DREAL_OS9 -Wl,--defsym,__jmptbl_size=$(NLJMPTBL) -Wl,--noinhibit-exec \
	  -o $@.elf $< 2> $@.ld.log
	$(BUILD)/elf2mod -n $* $@.elf $@

run-os9newlib: $(NLTESTS:%=$(BUILD)/os9nl/%)
	@$(call os9-run,$(BUILD)/os9nl,$(NLTESTS))

$(BUILD)/os9m/%: $(HERE)os9tests/%.c $(CC1) $(BUILD)/elf2mod $$(NLLIBC) $$(LIBGCC)
	mkdir -p $(BUILD)/os9m
	$(GCC) $(CONV) $(MATH) -specs=$(NEWLIB)/lib/os9.specs -B$(NLDIR)/ -L$(NLDIR) \
	  -L$$(dirname $$($(GCC) $(CONV) -print-libgcc-file-name)) -isystem $(NEWLIB)/include \
	  -O2 -Wl,--defsym,__jmptbl_size=$(NLJMPTBL) -Wl,--noinhibit-exec \
	  -o $@.elf $< -lm 2> $@.ld.log
	$(BUILD)/elf2mod -n $* $@.elf $@

run-os9math: $(BUILD)/os9m/fpmath $(BUILD)/os9m/fnmath
	@$(call os9-run,$(BUILD)/os9m,fpmath fnmath)

# OS-9 itself, -mos9math: os9tests/fpmath.c (not "math", the name of the
# math module itself), the arithmetic, and fnmath.c, the math functions
# (inline traps with -mos9math), with libgcc's soft-float routines and
# libm, and with -mos9math (OS-9's math module, inline, and libos9math,
# newlib's libgloss, for the rest) in both multilibs, and with
# -ffinite-math-only, which makes the compares inline too; run like
# check-os9newlib.
#   make check-os9math [CDIRUN=...] [CDIRUN_FLAGS=...]
check-os9math:
	@echo "== floating point on OS-9, libgcc"; \
	  $(MAKE) --no-print-directory BUILD=$(BUILD)/m-soft CONV= MATH= run-os9math || exit 1; \
	  echo "== floating point on OS-9, -mos9math"; \
	  $(MAKE) --no-print-directory BUILD=$(BUILD)/m-trap CONV= MATH=-mos9math run-os9math || exit 1; \
	  echo "== floating point on OS-9, -mos9math -mos9call"; \
	  $(MAKE) --no-print-directory BUILD=$(BUILD)/m-trap-os9call CONV=-mos9call MATH=-mos9math run-os9math || exit 1; \
	  echo "== floating point on OS-9, -mos9math -ffinite-math-only"; \
	  $(MAKE) --no-print-directory BUILD=$(BUILD)/m-trap-finite CONV= \
	    MATH="-mos9math -ffinite-math-only" run-os9math

check-os9newlib:
	@echo "== newlib on OS-9, stack convention"; \
	  $(MAKE) --no-print-directory BUILD=$(BUILD)/nl-stack CONV= run-os9newlib || exit 1; \
	  echo "== newlib on OS-9, -mos9call"; \
	  $(MAKE) --no-print-directory BUILD=$(BUILD)/nl-os9call CONV=-mos9call run-os9newlib

clean:
	rm -rf $(BUILD)

.PHONY: all run run-mod run-l68 run-mw-l68 run-newlib check check-mw check-mod check-l68 check-lsym \
	check-newlib check-os9 check-os9mix check-os9mod run-os9mod \
	check-os9newlib run-os9newlib check-os9math run-os9math clean
.SECONDARY:
