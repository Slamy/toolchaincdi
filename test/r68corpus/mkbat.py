#!/usr/bin/env python3
"""mkbat.py LIST BAT OUTDIR DEFS [FROM [TO]] (Windows Python): a vDos batch that assembles each
source of LIST (C:/... paths) with C 3.2's R68 in its own directory, through the 8.3 names (vDos
has no long ones), CDEF set to DEFS (an 8.3 path holding the defs files the sources use with
<...>); objects and listings of errors into OUTDIR (8.3 path) as NNNN.R and NNNN.LOG (NNNN: the
source's line in LIST). Sources whose directory has no short name, or a too long one, are left
out."""
import ctypes, os, sys

lst, bat, outdir, defs = sys.argv[1:5]
lo = int(sys.argv[5]) if len(sys.argv) > 5 else 1
hi = int(sys.argv[6]) if len(sys.argv) > 6 else 999999
buf = ctypes.create_unicode_buffer(1024)


def short(p):
    n = ctypes.windll.kernel32.GetShortPathNameW(p, buf, 1024)
    return buf.value if n else None


lines = ['@echo off', 'set CDEF=%s' % defs]
count = 0
for n, w in enumerate(open(lst).read().split('\n'), 1):
    if not w or n < lo or n > hi:
        continue
    s = short(w.replace('/', '\\'))
    if s is None:
        continue
    d, f = os.path.split(s)
    if len(d) > 60:
        continue
    lines.append('cd %s' % d)
    lines.append('R68 %s -q -o=%s\\%04d.R > %s\\%04d.LOG' % (f, outdir, n, outdir, n))
    count += 1
lines.append('echo finished')
open(bat, 'w', newline='\r\n').write('\n'.join(lines) + '\n')
print(count, 'sources')
