#!/bin/bash
# rc.sh [STEP] (Git Bash, the vDos poller running): the corpus through C 3.2's assembler in vDos,
# in the mirror (mirror.py), in chunks of STEP (120) sources. Settings: MIRLIST (Windows path of
# the mirrored list), MIRROR (the mirror's root, default C:\VDOS\MR), ASM (R68, or
# R68020) and ASMOPTS (e.g. -m2), OUT (8.3 path for the objects, default C:\VDOS\RC),
# VJOB (the poller's job runner, vjob.py), RCDEFS (8.3 path of the defs directory).
here=$(cd "$(dirname "$0")" && pwd)
MIRLIST=${MIRLIST:?MIRLIST: the mirrored list (Windows path; mirror.py)}
MIRROR=${MIRROR:-'C:\VDOS\MR'}
ASM=${ASM:-R68}
ASMOPTS=${ASMOPTS:-}
OUT=${OUT:-'C:\VDOS\RC'}
VJOB=${VJOB:-/c/path/to/vjob.py}
RCDEFS=${RCDEFS:-'C:\VDOS\RDEFS'}
step=${1:-120}
total=$(tr -d '\r' < "$(cygpath -u "$MIRLIST")" | wc -l)
mkdir -p "$(cygpath -u "$OUT")"
tmp=$(mktemp -d)
for ((a = 1; a <= total; a += step)); do
	python "$here/mkbat.py" "$MIRLIST" "$(cygpath -w "$tmp/rc.bat")" "$OUT" "$RCDEFS" "$MIRROR" "$ASM" "$ASMOPTS" \
		$a $((a + step - 1)) || exit 1
	python "$VJOB" "$tmp/rc.bat" | tail -1
done
rm -r "$tmp"
