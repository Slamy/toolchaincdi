#!/bin/sh
# r68xld.sh LD ARGS... -o OUT ...: LD (GNU ld) with ARGS, and where the link fails only for
# undefined r68x_ symbols (link-time expressions of sys.l's equates, which rof2elf notes in the
# objects' .r68x section, src/elf2mod/r68x_note.h), linked again with their definitions, as
# os9link.c does for the front ends: a link written anyway gives the notes of the objects and
# members linked; each referred-to NAME=TEXT becomes NAME = TEXT (the names quoted) in a linker
# script, with -u for each term so that sys.l's members are taken in.
set -e
LD=$1
shift
out=
prev=
for a in "$@"; do
	[ "$prev" = -o ] && out=$a
	prev=$a
done
: "${out:?r68xld.sh: no -o OUT}"
OBJCOPY=$(echo "$LD" | sed 's/ld$/objcopy/')
if "$LD" "$@" 2> "$out.ldlog"; then
	cat "$out.ldlog" >&2
	exit 0
fi
if ! grep -q 'undefined reference to .r68x_' "$out.ldlog"; then
	cat "$out.ldlog" >&2
	exit 1
fi
"$LD" "$@" --noinhibit-exec 2> /dev/null || true
"$OBJCOPY" --dump-section .r68x="$out.r68x" "$out" "$out.tmp" 2> /dev/null
rm -f "$out.tmp"
awk -v ldlog="$out.ldlog" -v script="$out.r68x.ld" -v undef="$out.r68x.u" '
BEGIN {
	while ((getline l < ldlog) > 0)
		if (match(l, /r68x_[0-9a-f]+/))
			want[substr(l, RSTART, RLENGTH)] = 1
}
{
	eq = index($0, "=")
	if (eq == 0)
		next
	name = substr($0, 1, eq - 1)
	text = substr($0, eq + 1)
	if (!(name in want) || (name in done))
		next
	done[name] = 1
	e = ""
	while (text != "") {
		match(text, /^[-+]?([0-9]+\*)?[^-+]+/)
		term = substr(text, 1, RLENGTH)
		text = substr(text, RLENGTH + 1)
		sign = ""
		if (term ~ /^[-+]/) {
			sign = substr(term, 1, 1)
			term = substr(term, 2)
		}
		coef = ""
		if (match(term, /^[0-9]+\*/)) {
			coef = substr(term, 1, RLENGTH - 1) " * "
			term = substr(term, RLENGTH + 1)
		}
		e = e (e == "" ? sign : " " (sign == "" ? "+" : sign) " ") coef "\"" term "\""
		print "-u" term > undef
	}
	print name " = " e ";" > script
}' "$out.r68x"
"$LD" "$@" $(cat "$out.r68x.u") "$out.r68x.ld"
