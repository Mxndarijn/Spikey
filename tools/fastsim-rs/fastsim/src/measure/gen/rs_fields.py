import re, sys, os, json

ROOT = sys.argv[1]  # tools/fastsim-rs/sim/src
structs = {}
files = [os.path.join(ROOT, 'hazards', f) for f in sorted(os.listdir(os.path.join(ROOT, 'hazards')))]
files += [os.path.join(ROOT, 'sim_state.rs'), os.path.join(ROOT, 'rooms', 'room_runtime.rs'), os.path.join(ROOT, 'rooms', 'hazard.rs')]
for p in files:
    s = open(p, encoding='utf-8').read()
    for m in re.finditer(r'pub struct (\w+)\s*\{(.*?)\n\}', s, re.S):
        body = re.sub(r'//[^\n]*', '', m.group(2))
        fields = []
        for fm in re.finditer(r'(?:pub(?:\([^)]*\))?\s+)?(\w+)\s*:\s*([^,]+?),?\s*\n', body + '\n'):
            fields.append((fm.group(1), fm.group(2).strip()))
        structs[m.group(1)] = fields
json.dump(structs, open(sys.argv[2], 'w'), indent=1)

cs = json.load(open(sys.argv[3]))
KW = {'move': 'move_', 'def': 'def_', 'type': 'type_', 'crate': 'crate_', 'loop': 'loop_', 'ref': 'ref_', 'box': 'box_', 'mod': 'mod_', 'match': 'match_', 'fn': 'fn_', 'in': 'in_', 'use': 'use_', 'where': 'where_', 'impl': 'impl_', 'self': 'self_', 'super': 'super_', 'dyn': 'dyn_', 'gen': 'gen_'}
for c, v in cs.items():
    if c not in structs:
        print('NO RUST', c)
        continue
    rf = dict(structs[c])
    names = [KW.get(n, n) for n, t, ro in v['fields']]
    for n, t, ro in v['fields']:
        rn = KW.get(n, n)
        if rn not in rf:
            print('MISSING', c, n, t)
    extra = [f for f, t in structs[c] if f not in names]
    print(c, 'extra rust:', extra)
