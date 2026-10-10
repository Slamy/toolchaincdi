#!/usr/bin/env python3
"""mkbat.py LIST BAT OUTDIR DEFS MIRROR ASM OPTS [FROM [TO] | @NUMBERS] (Windows Python): a vDos
batch that assembles each source of LIST, the mirrored list (mirror.py), with C 3.2's ASM (R68
or R68020) and OPTS ("" or e.g. "-m2") in its directory in the mirror, never in the originals'
(a path outside MIRROR is refused), through the 8.3 names (vDos has no long ones), CDEF set to
DEFS (an 8.3 path holding the defs files the sources use with <...>); objects and listings of
errors into OUTDIR (8.3 path) as NNNN.R and NNNN.LOG (NNNN: the source's line in LIST). FROM-TO
a range of lines, @NUMBERS a file of line numbers (a sample). Sources whose directory has no
short name, or a too long one, are left out."""
import ctypes, os, sys

lst, bat, outdir, defs, mirror, asm, opts = sys.argv[1:8]
pick = None
lo, hi = 1, 999999
if len(sys.argv) > 8 and sys.argv[8].startswith('@'):
    pick = set(int(x) for x in open(sys.argv[8][1:]).read().split())
else:
    lo = int(sys.argv[8]) if len(sys.argv) > 8 else 1
    hi = int(sys.argv[9]) if len(sys.argv) > 9 else 999999
mroot = os.path.normcase(os.path.normpath(mirror)) + os.sep
buf = ctypes.create_unicode_buffer(1024)


def short(p):
    n = ctypes.windll.kernel32.GetShortPathNameW(p, buf, 1024)
    return buf.value if n else None


lines = ['@echo off', 'set CDEF=%s' % defs]
count = skipped = 0
for n, w in enumerate(open(lst).read().split('\n'), 1):
    if not w or (pick is not None and n not in pick) or (pick is None and (n < lo or n > hi)):
        continue
    w = w.replace('/', '\\')
    if not os.path.normcase(os.path.normpath(w)).startswith(mroot):
        sys.exit('mkbat.py: %s is not in the mirror %s (mirror.py)' % (w, mirror))
    s = short(w)
    d, f = os.path.split(s) if s else ('', '')
    if s is None or len(d) > 60:
        skipped += 1
        continue
    lines.append('cd %s' % d)
    lines.append('%s %s -q %s -o=%s\\%04d.R > %s\\%04d.LOG' % (asm, f, opts, outdir, n, outdir, n))
    count += 1
lines.append('echo finished')
open(bat, 'w', newline='\r\n').write('\n'.join(lines) + '\n')
print(count, 'sources,', skipped, 'left out (no short name, or a too long one)')
