#!/usr/bin/env python3
"""mirror.py LIST ROOT MIRLIST [UP] (Windows Python): a mirror of the sources of LIST (C:/...
paths) under ROOT, for running Microware's assemblers in, never in the originals' directories
(C 3.2's R68 has no -u, resolves use relative to the current directory, and has left temp files
there): each source's directory and its UP parents (default 2) with their text files (no NUL
byte in the first 64 KB, under 4 MB), not recursively, and every file a use names (relative
to the source's directory; of any kind, in any subdirectory; used text files followed in turn),
each at ROOT plus its path (C:\\SRC\\X -> ROOT\\SRC\\X). Files already there are kept.
MIRLIST: the mirrored source's path on the same line as LIST's (empty where it wasn't
mirrored). The originals are only read."""
import os, re, shutil, sys

lst, root, mirlist = sys.argv[1:4]
up = int(sys.argv[4]) if len(sys.argv) > 4 else 2
done = {}
out = []
files = size = 0
USE = re.compile(rb'^[^*;\s]*\s+use\s+"?([^"\s<>]+)"?', re.I)


def copy(orig):
    global files, size
    t = os.path.join(root, orig[3:])        # without "C:\"
    if not os.path.exists(t):
        os.makedirs(os.path.dirname(t), exist_ok=True)
        shutil.copy2(orig, t)
        files += 1
        size += os.path.getsize(orig)


def mirror_dir(d):
    if d in done or len(d) <= 3:
        return
    os.makedirs(os.path.join(root, d[3:]), exist_ok=True)
    for e in os.scandir(d):
        if not e.is_file() or e.stat().st_size >= 4 << 20:
            continue
        with open(e.path, 'rb') as fp:
            if b'\0' in fp.read(65536):
                continue
        copy(e.path)
    done[d] = True


def mirror_uses(path, cwd, seen):
    if path in seen or not os.path.isfile(path):
        return
    seen.add(path)
    data = open(path, 'rb').read()
    if b'\0' in data[:65536]:
        return
    for line in data.splitlines():
        m = USE.match(line)
        if not m:
            continue
        name = m.group(1).decode('latin1').replace('/', '\\')
        if ':' in name:                     # an absolute path: read in place
            continue
        orig = os.path.normpath(os.path.join(cwd, name))
        if os.path.isfile(orig):
            copy(orig)
            mirror_uses(orig, cwd, seen)


for w in open(lst).read().split('\n'):
    if not w:
        out.append('')
        continue
    src = w.replace('/', '\\')
    d, f = os.path.split(src)
    p = d
    for i in range(up + 1):
        mirror_dir(p)
        p = os.path.dirname(p)
    mirror_uses(src, d, set())
    m = os.path.join(root, d[3:], f)
    out.append(m if os.path.exists(m) else '')
open(mirlist, 'w', newline='\n').write('\n'.join(out))
print(len(done), 'directories,', files, 'files copied,', size // 1000000, 'MB;',
      sum(1 for x in out if x), 'sources mirrored')
