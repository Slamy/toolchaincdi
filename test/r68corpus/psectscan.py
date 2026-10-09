#!/usr/bin/env python3
"""psectscan.py ROOT LIST: the r68 sources under ROOT (.s files with a psect line), one per
content (the first path in sorted order), into LIST as Windows paths (C:/...); counts and the
largest directory groups on standard output. Read only."""
import collections, hashlib, os, re, sys

root, out = sys.argv[1], sys.argv[2]
found, seen = [], {}
for dp, dn, fn in os.walk(root):
    for f in fn:
        if not f.lower().endswith('.s'):
            continue
        p = os.path.join(dp, f)
        try:
            t = open(p, 'rb').read()
        except OSError:
            continue
        if not re.search(rb'(?im)^[ \t]*psect[ \t]', t):
            continue
        w = p.replace('\\', '/')
        found.append(w)
        seen.setdefault(hashlib.md5(t).hexdigest(), []).append(w)
distinct = sorted(min(v) for v in seen.values())
lines = sum(max(open(p, 'rb').read().count(b'\n'), 1) for p in distinct)
print('%d r68 sources, %d distinct, %d lines' % (len(found), len(distinct), lines))
groups = collections.Counter('/'.join(w.split('/')[:3]) for w in found)
for g, n in groups.most_common(10):
    print('%6d %s' % (n, g))
with open(out, 'w', newline='\n') as f:
    for w in distinct:
        f.write(w + '\n')
