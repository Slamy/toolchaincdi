#!/bin/sh
# check-os9mix: mwside.c compiled by Microware C on OS-9 itself, gccside.c
# by GCC with -mos9call, linked both ways and run on OS-9:
#   l68    Microware's cc links mwside.r with gccside.r (elf2rof) on OS-9
#   ld     GNU ld links gccside.o with mwside.r (copied up, rof2elf), with
#          cstart.r, clib.l, math.l and sys.l (rof2elf), then elf2mod
#   mismatch  as ld, with gccside.c built -DMISMATCH_FLOAT: m10's float
#          argument goes unwidened, which must fail just that one check
# Run by the Makefile (make check-os9mix), which passes the variables below.
# Each program prints its failures and exits with 0x100 plus their number;
# the Status line of cdirun -st gives it (its exit code may be cut to the
# low 8 bits on the way here).
set -e
: "${HERE:?}" "${BUILD:?}" "${GCC:?}" "${CDIRUN:?}" "${CFLAGS_MW:?}" "${CSTART:?}" "${CLIB:?}" \
  "${MATHL:?}" "${SYSL:?}" "${SYSA:?}" "${LIBGCC:?}"
TPREFIX=${TPREFIX:-m68k-elfos9-}

work=$BUILD/os9mix
rm -rf "$work"
mkdir -p "$work"
cd "$work"

cdirun() { $CDIRUN $CDIRUN_FLAGS "$@"; }
# A step on OS-9 whose output only matters when it fails.
step() {
	if ! cdirun "$@" > step.log 2>&1; then
		echo "FAIL: os9mix: cdirun $*"
		cat step.log
		exit 1
	fi
}

# The GCC side, as ELF and as ROF, and the mismatch.
$GCC -c $CFLAGS_MW -o gccside.o "$HERE/mixtests/gccside.c"
$GCC -c $CFLAGS_MW -DMISMATCH_FLOAT -o gccmis.o "$HERE/mixtests/gccside.c"
"$BUILD/elf2rof" -o gccside.r gccside.o

# What earlier runs left on OS-9 goes first; errors are expected.
cdirun "unlink mixl68 mixld mixmis" > /dev/null 2>&1 || true
cdirun "del mwside.c mwside.r gccside.r mixl68 mixld mixmis" > /dev/null 2>&1 || true

# The Microware side, compiled on OS-9 and copied up.
cp "$HERE/mixtests/mwside.c" .
step -te -dc mwside.c
step -t 0 "cc -r $OS9_CCFLAGS mwside.c"
mkdir up
(cd up && cdirun -uc mwside.r > ../step.log 2>&1) || { echo "FAIL: os9mix: upcopy of mwside.r"; cat step.log; exit 1; }

# l68: linked by Microware's cc on OS-9.
step -dc gccside.r
step -t 0 "cc -fd=mixl68 $OS9_CCFLAGS mwside.r gccside.r"

# ld: linked by GNU ld, and the mismatch.
"$BUILD/rof2elf" -e "$SYSL" -o mwside.o up/mwside.r
"$BUILD/rof2elf" -e "$SYSL" -o math.a "$MATHL"
${TPREFIX}ranlib math.a
for m in mixld:gccside.o mixmis:gccmis.o; do
	mod=${m%%:*}
	sh "$HERE/r68xld.sh" ${TPREFIX}ld -q --no-check-sections -T "$HERE/../l68cmp/mod.lds" -o "$mod.elf" \
	  "$CSTART" "${m#*:}" mwside.o --start-group "$CLIB" math.a --end-group "$LIBGCC" "$SYSA"
	"$BUILD/elf2mod" -n "$mod" "$mod.elf" "$mod" > /dev/null
done
step -dc mixld mixmis
step "attr mixl68 -e -pe; attr mixld -e -pe; attr mixmis -e -pe"
step "load -d mixl68; load -d mixld; load -d mixmis"

fail=0
for mod in mixl68 mixld; do
	cdirun -t 60 -st $mod > $mod.out 2>&1 || true
	if grep -q "^Status 000:000" $mod.out; then
		echo "PASS: os9mix/$mod"
	else
		echo "FAIL: os9mix/$mod"; cat $mod.out; fail=1
	fi
done

# The mismatch fails exactly the check of m10's arguments: one failure.
cdirun -t 60 -st mixmis > mixmis.out 2>&1 || true
if grep -q "^Status 001:001" mixmis.out && grep -q "FAIL: arguments as m10 saw them" mixmis.out; then
	echo "PASS: os9mix/mixmis (the unwidened float is caught)"
else
	echo "FAIL: os9mix/mixmis (expected Status 001:001 with m10's arguments)"
	cat mixmis.out; fail=1
fi
exit $fail
