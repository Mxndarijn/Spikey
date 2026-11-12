import re, sys, os, json

ROOT = sys.argv[1]
MODS = r'\b(public|private|internal|protected|readonly|new|volatile)\b'


def strip(s):
    s = re.sub(r'"(\\.|[^"\\\n])*"', '""', s)
    s = re.sub(r"'(\\.|[^'\\\n])'", "' '", s)
    s = re.sub(r'//[^\n]*', '', s)
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    return s


def split_top(s):
    out = []
    d = 0
    cur = ''
    for c in s:
        if c in '<([{':
            d += 1
        if c in '>)]}':
            d -= 1
        if c == ',' and d == 0:
            out.append(cur)
            cur = ''
        else:
            cur += c
    out.append(cur)
    return out


def parse_file(path):
    src = strip(open(path, encoding='utf-8').read())
    classes = {}
    depth = 0
    stack = []
    stmt_start = 0
    cur = None
    for m in re.finditer(r'[{};]', src):
        ch = m.group(0)
        chunk = src[stmt_start:m.start()]
        if ch == '{':
            cm = re.search(r'\bclass\s+(\w+)(?:\s*:\s*(\w+))?', chunk)
            if cm and depth == 0:
                cur = cm.group(1)
                classes[cur] = {'base': cm.group(2), 'fields': [], 'abstract': 'abstract' in chunk}
                stack.append('class')
                depth += 1
                stmt_start = m.end()
                continue
            if depth == 1 and '=' in chunk and '(' not in chunk.split('=')[0] and '=>' not in chunk:
                stack.append('init')
                depth += 1
                continue
            stack.append('blk')
            depth += 1
            stmt_start = m.end()
            continue
        if ch == '}':
            depth -= 1
            k = stack.pop()
            if k == 'init':
                continue
            stmt_start = m.end()
            continue
        if depth == 1 and cur:
            st = src[stmt_start:m.start()].strip()
            st = re.sub(r'^\[[^\]]*\]\s*', '', st)
            head = st.split('=')[0]
            if '(' not in head.replace('(long', '').replace('(int', '') or head.strip().startswith('('):
                pass
            if '=>' not in st and not re.search(r'\b(const|static)\b', head) and st:
                ro = bool(re.search(r'\breadonly\b', head))
                words = re.sub(MODS, '', st).strip()
                mm = re.match(r'(\([^)]*\)(?:\[\])?|[\w.]+(?:<[^=;]*?>)?(?:\[\])?\??)\s+(\w.*)$', words, re.S)
                if mm and '(' not in mm.group(2).split('=')[0]:
                    typ = mm.group(1).strip()
                    for part in split_top(mm.group(2)):
                        nm = part.split('=')[0].strip()
                        if re.match(r'^\w+$', nm):
                            classes[cur]['fields'].append((nm, typ, ro))
        stmt_start = m.end()
    return classes


allc = {}
for d in ['Sim/Hazards', 'Sim/Rooms']:
    for f in sorted(os.listdir(os.path.join(ROOT, d))):
        if f.endswith('.cs'):
            allc.update(parse_file(os.path.join(ROOT, d, f)))
allc.update(parse_file(os.path.join(ROOT, 'Sim/SimState.cs')))
json.dump(allc, open(sys.argv[2], 'w'), indent=1)
types = set()
for c, v in allc.items():
    for n, t, ro in v['fields']:
        types.add(t)
print(sorted(types))
for c in ['SimState', 'RoomRuntime', 'Hazard', 'Gate', 'Boss', 'BossSaw', 'Beam']:
    print(c, allc.get(c))
