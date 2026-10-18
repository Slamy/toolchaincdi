#!/bin/bash
# dis.sh OBJ: a normalized listing for comparing r68 objects. Sections are padded to a multiple
# of 4 (Ultra C's r68 pads code with NOPs, data with zeros). The contents come from a link of
# the object alone (gas keeps relocations for branches to global symbols that rof2elf's
# objects have resolved), the relocations from the object, less the PC-relative ones to
# symbols it defines. (corp: .bss starts at a multiple of 4: C 3.2's R68 aligns sections to 2.)
# .r68ord (r68togas's order records for elf2rof and elf2mod; rof2elf writes it only for some
# ROFs) is left out of the section list.
B=~/build/install/bin/m68k-elfos9-
o=$1
t=$(mktemp -d)
cat > $t/ld.x <<'EOF'
SECTIONS {
  .text 0 : { *(.text) }
  .data 0 : { *(.data) }
  .bss ALIGN(4) : { *(.bss) }
  .remote.data 0 : { *(.remote.data) }
  .remote.bss ALIGN(4) : { *(.remote.bss) }
  /DISCARD/ : { *(.comment) *(.note*) }
}
EOF
${B}ld -T $t/ld.x --no-check-sections --unresolved-symbols=ignore-all -e 0 -o $t/x.elf "$o" 2>$t/err ||
  sed "s|$o|OBJ|" $t/err | grep -v ': in function '	# (corp: which symbol ld names varies)
echo "== sections"
${B}objdump -h "$o" | awk '$2 ~ /^\./ && $3 != "00000000" {print $2, $3}' | grep -v '^\.comment\|^\.note\|^\.r68x\|^\.r68ord' | sort |
  while read n s; do printf '%s %08x\n' $n $(( (0x$s + 3) / 4 * 4 )); done
echo "== globals"
# undefined symbols: referenced by a relocation (U); a link-time expression's term, named only
# in .r68x's notes, left out (rof2elf's objects have them as symbols, ours don't); any other
# one is listed as U-unused, as the Microware assemblers write no reference for it and a link
# would take in a library member for it
used=$(${B}objdump -r "$o" | awk '/R_68K/ {s = $3; sub(/[-+]0x.*/, "", s); print s}' | sort -u)
notes=$(${B}readelf -p .r68x "$o" 2>/dev/null | sed '1,/^String dump/d; s/^ *\[ *[0-9a-f]*\]//' | tr -c 'A-Za-z0-9_$.@' '\n' | sort -u)
${B}nm -g "$o" | sed 's/^ *//' | awk -v used="$used" -v notes="$notes" '
  BEGIN { n = split(used, u, "\n"); for (i = 1; i <= n; i++) ref[u[i]] = 1
          n = split(notes, u, "\n"); for (i = 1; i <= n; i++) note[u[i]] = 1 }
  { if (NF == 2) { if ($2 in ref) print "U", $2; else if (!($2 in note)) print "U-unused", $2 } else print $2, $3, $1 }' | sort |
  # (corp: rof2elf lists a common symbol also as undefined: the U line dropped)
  awk '{ line[NR] = $0; if ($1 == "C") com[$2] = 1; name[NR] = $2; type[NR] = $1 }
    END { for (i = 1; i <= NR; i++) if (!(type[i] == "U" && name[i] in com)) print line[i] }'
defined=$(${B}nm "$o" | awk 'NF==3 {print $3, $2}')
for s in .text .data .remote.data; do
  ${B}objcopy -O binary -j $s $t/x.elf $t/b 2>/dev/null || continue
  [ -s $t/b ] || continue
  while [ $(( $(stat -c %s $t/b) % 4 )) != 0 ]; do
    if [ $s = .text ] && [ $(( $(stat -c %s $t/b) % 2 )) = 0 ]; then printf '\x4e\x71' >> $t/b; else printf '\x00' >> $t/b; fi
  done
  # Ultra C's r68 pads the code to 4 with trapf for -m1..6, nop without -m: a last word trapf
  # as nop, in the bytes (disassembled, it can join the word before it: 0000 51fc, orib #-4)
  [ $s = .text ] && perl -0777 -pi -e 's/\x51\xfc\z/\x4e\x71/' $t/b
  echo "== $s"
  if [ $s = .text ]; then
    # (corp: zeros disassembled too; a last word of zeros, padding, as nop)
    ${B}objdump -z -b binary -m m68k:68000 -D $t/b | grep -P '^\s+[0-9a-f]+:' | sed -E 's/[ \t]+$//' |
      sed -E '$ s/^(\s+[0-9a-f]+:\s+)(0000\s+\.short 0x0000|Address 0x[0-9a-f]+ is out of bounds\.)$/\14e71           \tnop/'
  else
    od -An -tx1 -v -w16 $t/b
  fi
  echo "== $s relocs"
  # a symbol defined here counts as its section (rof2elf refers to the section)
  # (corp: sorted, gas writes them backwards; a negative section addend too; a 16-bit field's
  # addend -0x8000 is +0x8000, as rof2elf and gas write $8000)
  ${B}objdump -r -j $s "$o" 2>/dev/null | grep R_68K | awk '{print $1, $2, $3}' | sort |
    sed -E 's/\.(text|data|bss)([-+]0x[0-9a-f]+)?$/.\1+?/; s/^([0-9a-f]+ R_68K_16 [^ ]+)-0x00008000$/\1+0x00008000/' |
    awk -v map="$defined" 'BEGIN { n = split(map, m, "\n"); for (i = 1; i <= n; i++) { split(m[i], f, " "); sec[f[1]] = f[2] } }
      { t = $3; sub(/[-+]0x.*/, "", t); if (t in sec) { if ($2 ~ /PC/) next; c = tolower(sec[t]); $3 = (c == "t" ? ".text" : c == "d" ? ".data" : c == "b" ? ".bss" : $3) "+?" } print }'
done
rm -r $t
