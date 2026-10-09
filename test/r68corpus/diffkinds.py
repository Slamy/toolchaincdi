"""diffkinds.py DIR REF [N]: over DIR's NNNN-*.REF.dis / .us.dis pairs that differ, the changed
code lines paired up (difflib), grouped by "ref mnemonic (opcode) -> our mnemonic (opcode)";
other differing sections counted. Examples for the N most common."""
import collections, difflib, glob, os, re, sys
d, ref = sys.argv[1], sys.argv[2]
top = int(sys.argv[3]) if len(sys.argv) > 3 else 30
kinds = collections.Counter()
ex = {}
files = collections.defaultdict(set)
other = collections.Counter()
def parse(path):
    sec, out = None, []
    for l in open(path, encoding='latin1'):
        l = l.rstrip('\n')
        if l.startswith('== '):
            sec = l[3:]
            continue
        out.append((sec, l))
    return out
for r in sorted(glob.glob(os.path.join(d, '*.%s.dis' % ref))):
    u = r[:-len(ref) - 5] + '.us.dis'
    if not os.path.exists(u):
        continue
    a, b = parse(r), parse(u)
    if a == b:
        continue
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        if op == 'equal':
            continue
        for k in range(max(i2 - i1, j2 - j1)):
            x = a[i1 + k] if i1 + k < i2 else (None, '')
            y = b[j1 + k] if j1 + k < j2 else (None, '')
            sec = x[0] or y[0]
            if sec == '.text':
                mx = re.match(r'\s*[0-9a-f]+:\s+([0-9a-f]{4})\S*\s+(\S+)', x[1])
                my = re.match(r'\s*[0-9a-f]+:\s+([0-9a-f]{4})\S*\s+(\S+)', y[1])
                key = '%s -> %s' % (mx.group(2) if mx else '-', my.group(2) if my else '-')
            else:
                key = 'section %s' % sec
            kinds[key] += 1
            files[key].add(os.path.basename(r)[:4])
            ex.setdefault(key, (os.path.basename(r), x[1].strip(), y[1].strip()))
for k, n in kinds.most_common(top):
    f, x, y = ex[k]
    print('%5d %3d files  %-40s  e.g. %s\n        ref: %s\n        us:  %s' % (n, len(files[k]), k, f, x[:70], y[:70]))
