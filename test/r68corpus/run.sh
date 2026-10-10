#!/bin/bash
# run.sh STAGE ... (in WSL): the r68 corpus (README.md).
#   run.sh ucc                 Ultra C's r68 on each source of $LIST, in its directory in the
#                              mirror ($MIRLIST, mirror.py; WSL interop), objects into $WORK/ucc
#   run.sh ours OUT [OPTS...]  m68k-os9-r68 (with OPTS, e.g. -dialect=c32) on each source, in
#                              $JOBS parallel ranges, compared with the references: Ultra C's
#                              ($WORK/ucc) and C 3.2's ($RC/NNNN.R, from rc.sh); $WORK/OUT/results:
#                              <n> <vs Ultra C> <vs C 3.2> <name> <path>, each SAME, DIFF, REFFAIL
#                              (the reference didn't assemble it), USFAIL, BOTHFAIL
# Settings (environment): WORK (default ~/build/r68corpus), LIST ($WORK/list.txt, from
# psectscan.py), MIRLIST ($WORK/mirlist.txt, from mirror.py), DEFS ($WORK/defs), SYSL (CD-i's
# SYS.L), R68 (Ultra C's r68.exe), RC (C 3.2's objects), JOBS (3), and PATH for m68k-os9-r68 and
# the m68k-elfos9 binutils. Nothing is written beside the sources: Microware's assemblers run in
# the mirror, m68k-os9-r68 (which writes nothing there) on the originals.
set -u
here=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HOME/build/r68corpus}
LIST=${LIST:-$WORK/list.txt}
MIRLIST=${MIRLIST:-$WORK/mirlist.txt}
DEFS=${DEFS:-$WORK/defs}
SYSL=${SYSL:-/path/to/sys.l}
R68=${R68:-/path/to/r68.exe}
RC=${RC:-/mnt/c/VDOS/RC}
JOBS=${JOBS:-3}
# SYS.L converted into a cache, not beside it (the tools' default, save=beside, writes libsys.a
# into the user's kit)
export M68K_OS9_ELF=${M68K_OS9_ELF:-save=cache,cache=$WORK/cache}

name_of() {	# N PATH
	local f=${2##*/}
	echo "$(printf '%04d' "$1")-$(echo "${f%.*}" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9_\n' '_')"
}

entries() {	# FROM TO: "n path" lines
	tr -d '\r' < "$LIST" | awk -v a="$1" -v b="$2" 'NF && NR >= a && NR <= b { print NR, $0 }'
}

cmp_ref() {	# REFDIS OURDIS
	if [ -s "$1" ] && [ -s "$2" ]; then cmp -s "$1" "$2" && echo SAME || echo DIFF
	elif [ -s "$1" ]; then echo USFAIL
	elif [ -s "$2" ]; then echo REFFAIL
	else echo BOTHFAIL; fi
}

ucc() {	# in the mirror: Microware's assemblers have left temp files in their directory
	# r68.exe (Windows) can't use \\wsl.localhost\... paths for -u and -o
	case "$WORK $DEFS" in
	/mnt/[a-z]/*" "/mnt/[a-z]/*) ;;
	*) echo "run.sh ucc: WORK and DEFS must be on a Windows drive (/mnt/c/...), for r68.exe" >&2; exit 1;;
	esac
	mkdir -p "$WORK/ucc"
	entries 1 999999 | while read -r n w; do
		m=$(tr -d '\r' < "$MIRLIST" | sed -n "${n}p")
		[ -n "$m" ] || continue
		l=$(wslpath -u "$m")
		o=$WORK/ucc/$(name_of "$n" "$w")
		rm -f "$o".*
		(cd "${l%/*}" && timeout 60 "$R68" "${l##*/}" -q -u="$(wslpath -w "$DEFS")" -o="$(wslpath -w "$o.r")") \
			> "$o.log" 2>&1 < /dev/null
	done
}

ours_range() {	# OUT FROM TO OPTS...
	local out=$1 from=$2 to=$3
	shift 3
	entries "$from" "$to" | while read -r n w; do
		l=/mnt/c/${w#[Cc]:/}
		name=$(name_of "$n" "$w")
		o=$out/$name
		rm -f "$o".*
		(cd "${l%/*}" && timeout 60 m68k-os9-r68 "${l##*/}" -q "$@" -u="$DEFS" -sysl="$SYSL" -o="$o.us.o") \
			> "$o.us.log" 2>&1 < /dev/null
		[ -f "$o.us.o" ] && bash "$here/dis.sh" "$o.us.o" > "$o.us.dis" 2>&1
		if [ -s "$WORK/ucc/$name.r" ]; then
			rof2elf -e "$SYSL" -o "$o.mw.o" "$WORK/ucc/$name.r" > /dev/null 2>&1 &&
				bash "$here/dis.sh" "$o.mw.o" > "$o.mw.dis" 2>&1
		fi
		r32=$(printf '%s/%04d.R' "$RC" "$n")
		[ -f "$r32" ] || r32=$(printf '%s/%04d.r' "$RC" "$n")
		if [ -s "$r32" ]; then
			rof2elf -e "$SYSL" -o "$o.c32.o" "$r32" > /dev/null 2>&1 &&
				bash "$here/dis.sh" "$o.c32.o" > "$o.c32.dis" 2>&1
		fi
		echo "$n $(cmp_ref "$o.mw.dis" "$o.us.dis") $(cmp_ref "$o.c32.dis" "$o.us.dis") $name $w" >> "$out/results"
	done
}

case ${1:-} in
ucc)
	ucc ;;
ours)
	out=$WORK/$2
	shift 2
	rm -rf "$out"
	mkdir -p "$out"
	total=$(tr -d '\r' < "$LIST" | wc -l)
	step=$(( (total + JOBS - 1) / JOBS ))
	for ((a = 1; a <= total; a += step)); do
		ours_range "$out" "$a" $((a + step - 1)) "$@" &
	done
	wait
	sort -n -o "$out/results" "$out/results"
	awk '{ print $2, $3 }' "$out/results" | sort | uniq -c | sort -rn ;;
*)
	sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
	exit 2 ;;
esac
