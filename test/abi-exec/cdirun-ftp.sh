#!/bin/bash
# cdirun-ftp.sh: a CDIRUN= wrapper for the OS-9 targets (check-os9 and the others) on a CD-i
# player on a network, where the player's telnet session is bridged to a cdirun terminal and an
# ftp session to the PC stays open on the player's console:
#   make check-os9 MWLIB=... CDIRUN=$PWD/cdirun-ftp.sh
# Setup, outside this script: an ftp server on the PC serving STAGE; on the player, ftp logged in
# to it (binary mode) in the current directory the tests run in, and runst (cdirun's helper
# module) in memory or in the execution directory.
# Environment: CDIRUN_EXE (default cdirun.exe), CDIRUN_TERM (the bridged terminal, required),
# CDIRUN_STAGE (the ftp server's directory, required).
#
# -dc FILE... copies each FILE into STAGE and has the player fetch it ("get NAME NAME"); any other
# command line runs through ftp's shell escape ("!COMMAND"); with -st through "!runst COMMAND",
# whose last line "Error #GGG:NNN" (the status) is written as cdirun -st writes it, "Status
# GGG:NNN". -t SECONDS passes on to cdirun (default 60).
C=${CDIRUN_EXE:-cdirun.exe}
: "${CDIRUN_TERM:?the bridged cdirun terminal}" "${CDIRUN_STAGE:?the directory the ftp server serves}"
# the ftp prompt may follow output without a line end
P=(-p "term:$CDIRUN_TERM" -pr "ftp> " -mid)
if [ "$1" = "-dc" ]; then
	shift
	for f; do
		b=$(basename "$f")
		cp "$f" "$CDIRUN_STAGE/$b" || exit 1
		out=$("$C" "${P[@]}" -t 60 "get $b $b" 2>&1)
		echo "$out"
		echo "$out" | grep -q -E '(^|[^0-9])226[ -]' || exit 1
	done
	exit 0
fi
t=(-t 60); st=0; cmd=
while [ $# -gt 0 ]; do
	case $1 in
		-t) t=(-t "$2"); shift 2 ;;
		-st) st=1; shift ;;
		*) cmd="$cmd${cmd:+ }$1"; shift ;;
	esac
done
if [ $st = 1 ]; then
	out=$("$C" "${P[@]}" "${t[@]}" "!runst $cmd" 2>&1)
	rc=$?
	echo "$out"
	s=$(echo "$out" | tr -d '\r' | sed -n 's/.*Error #\([0-9]*:[0-9]*\).*/\1/p' | tail -1)
	[ -n "$s" ] || { echo "no status line"; exit 1; }
	echo "Status $s"
	exit $rc
fi
exec "$C" "${P[@]}" "${t[@]}" "!$cmd"
