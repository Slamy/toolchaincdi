#!/bin/bash
# rc.sh [STEP] (Git Bash, the vDos poller running): the corpus through C 3.2's R68 in vDos, in
# chunks of STEP (120) sources; objects into C:\VDOS\RC. Settings: LIST (Windows path of
# the list), VJOB (the poller's job runner, vjob.py), RCDEFS (8.3 path of the defs directory).
here=$(cd "$(dirname "$0")" && pwd)
LIST=${LIST:?LIST: the list (Windows path)}
VJOB=${VJOB:-/c/path/to/vjob.py}
RCDEFS=${RCDEFS:-'C:\VDOS\RDEFS'}
step=${1:-120}
total=$(tr -d '\r' < "$(cygpath -u "$LIST")" | wc -l)
mkdir -p /c/VDOS/RC
tmp=$(mktemp -d)
for ((a = 1; a <= total; a += step)); do
	python "$here/mkbat.py" "$LIST" "$(cygpath -w "$tmp/rc.bat")" 'C:\VDOS\RC' "$RCDEFS" $a $((a + step - 1))
	python "$VJOB" "$tmp/rc.bat" | tail -1
done
rm -r "$tmp"
