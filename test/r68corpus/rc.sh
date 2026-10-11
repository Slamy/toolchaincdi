#!/bin/bash
# rc.sh [STEP] (Git Bash, the vDos poller running): the corpus through C 3.2's assembler in vDos,
# in the mirror (mirror.py), in chunks of STEP (120) sources. Settings (all but ASM and ASMOPTS
# required): MIRLIST (Windows path of the mirrored list), MIRROR (the mirror's root, Windows
# path), ASM (R68, or R68020) and ASMOPTS (e.g. -m2), OUT (8.3 path for the objects), VJOB (the
# vDos poller's job runner: writes the batch as the poller's job, waits, prints its output),
# RCDEFS (8.3 path of the defs directory).
here=$(cd "$(dirname "$0")" && pwd)
MIRLIST=${MIRLIST:?MIRLIST: the mirrored list (Windows path; mirror.py)}
MIRROR=${MIRROR:?MIRROR: the mirror's root (Windows path; mirror.py)}
ASM=${ASM:-R68}
ASMOPTS=${ASMOPTS:-}
OUT=${OUT:?OUT: an 8.3 Windows path for the objects}
VJOB=${VJOB:?VJOB: the vDos poller's job runner}
RCDEFS=${RCDEFS:?RCDEFS: the 8.3 Windows path of the defs directory}
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
