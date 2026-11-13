"""Writes measure/fields.rs from the Rust sim's structs: what C# `Visibility` (Measure/LeakRun.cs)
got by reflection. For SimState, RoomRuntime and every `Hz` variant: its fields in reflection
order (the type's own fields in declaration order, then its parent's: `b: Bouncer`,
`boss: Boss`, `c: CoinPickup`, and last `base: Base` = kind, alive, t), each with its Ty, a
getter, a setter for the transplant candidates and the no-argument methods visible.tsv may name.

    cd tools/fastsim-rs
    python fastsim/src/measure/gen/rs_fields.py sim/src fastsim/src/measure/fields.rs

Python 3 stdlib only. See README.md here for when to run it.
"""
import os
import re
import sys

ROOT = sys.argv[1]  # tools/fastsim-rs/sim/src
OUT = sys.argv[2]

# Rust names a field after a keyword with a trailing `_` (`def_`); the table keeps the sim's name.
KEYWORDS = {'def', 'move', 'crate', 'type', 'loop', 'ref', 'box', 'mod', 'match', 'fn', 'in', 'use',
            'where', 'impl', 'self', 'super', 'dyn', 'gen'}

# Fields only the Rust port has (no GDScript / C# counterpart): never part of the table.
RUST_ONLY = {
    'Base': {'idx'},  # the hazard's own index in room.hazards (rooms/hazard.rs)
}

# The Rust field type -> Ty (fields.rs).
TY = {'i64': 'Long', 'bool': 'Bool', "&'static str": 'Str', 'SimRng': 'Rng', 'Vec<i64>': 'ListLong',
      'Vec<bool>': 'ListBool', 'Vec<Hz>': 'Hazards', "Option<&'static RoomDef>": 'Def',
      # another hazard of the room, by index (Gate.partner, Stalactite.partner)
      'Option<usize>': 'Ref',
      # a hazard object of its own (SplittingBouncer.other)
      'Option<Bouncer>': 'Child'}


def ty_of(t):
    if t in TY:
        return TY[t]
    m = re.fullmatch(r'\[(i64|bool);\s*\w+\]', t)
    if m:
        return 'ArrLong' if m.group(1) == 'i64' else 'ArrBool'
    raise SystemExit('rs_fields.py: no Ty for the Rust type %r' % t)


def parse_structs(path, structs):
    src = open(path, encoding='utf-8').read()
    for m in re.finditer(r'^pub struct (\w+)\s*\{(.*?)^\}', src, re.S | re.M):
        fields = []
        for line in m.group(2).split('\n'):
            line = re.sub(r'//.*', '', line).strip()
            if not line or line.startswith('#'):
                continue
            fm = re.fullmatch(r'(?:pub(?:\([^)]*\))?\s+)?(\w+)\s*:\s*(.+?),?', line)
            if not fm:
                raise SystemExit('rs_fields.py: cannot read the field %r in %s' % (line, path))
            fields.append((fm.group(1), fm.group(2).strip()))
        structs[m.group(1)] = fields


structs = {}
hz_dir = os.path.join(ROOT, 'hazards')
paths = [os.path.join(hz_dir, f) for f in sorted(os.listdir(hz_dir)) if f.endswith('.rs')]
paths += [os.path.join(ROOT, 'sim_state.rs'), os.path.join(ROOT, 'rooms', 'room_runtime.rs'),
          os.path.join(ROOT, 'rooms', 'hazard.rs')]
for p in paths:
    parse_structs(p, structs)

# The hazard types: the variants of `Hz` (hazard_enum! in hazards/mod.rs), in its order.
mod_src = open(os.path.join(hz_dir, 'mod.rs'), encoding='utf-8').read()
HZ = re.findall(r'\w+', re.search(r'^hazard_enum!\((.*?)\);', mod_src, re.S | re.M).group(1))


def sim_name(f):
    return f[:-1] if f.endswith('_') and f[:-1] in KEYWORDS else f


def is_parent(t):
    """A field holding the parent type: `base: Base` or a hazard struct by value (`b: Bouncer`)."""
    return t == 'Base' or (t in structs and any(ft == 'Base' or is_parent(ft) for _, ft in structs[t]))


def chain(c):
    """Reflection order (C# Visibility.fields): own fields, then the parent's, Base last."""
    out = []
    path = ''
    while c is not None:
        parent = None
        for f, t in structs[c]:
            if f in RUST_ONLY.get(c, ()):
                continue
            if is_parent(t):
                assert parent is None, (c, 'two parent fields')
                parent = (f, t)
                continue
            out.append((sim_name(f), t, False, path + '.' + f))
        if parent is None:
            break
        path += '.' + parent[0]
        c = parent[1]
    return [(n, ty_of(t), ro, p) for n, t, ro, p in out]


# The no-argument methods visible.tsv can name (C# Visibility.no_arg_method), by class:
# (name, V constructor, Rust call on `x`). Kept by hand: it is what the painters read (see
# visibility.rs), not every no-argument method (methods.rs has those).
METHODS = {
    'SimState': [('copy', 'Obj', None)],
    'RoomRuntime': [('blink_showing_second', 'B', 'x.blink_showing_second()'), ('inset', 'I', 'x.inset(0)'),
                    ('spike_depth', 'I', 'x.spike_depth()'), ('spike_half_base', 'I', 'x.spike_half_base()'),
                    ('variant_id', 'S', 'x.variant_id()'), ('wall_left', 'I', 'x.wall_left()'),
                    ('wall_right', 'I', 'x.wall_right()')],
    'Block': [('opacity', 'I', None)],
    'BossCrusher': [('lane_half', 'I', None)],
    'BossSaw': [('ring_max', 'I', None)],
    'Bubble': [('coin_in_reach', 'B', None)],
    'Dart': [('glow', 'I', None), ('tail_x', 'I', None)],
    'Drop': [('falling', 'B', None), ('stake_half_base', 'I', None), ('stake_height', 'I', None),
             ('staked', 'B', None), ('warn_progress', 'I', None), ('warning', 'B', None)],
    'ExitKey': [('done', 'B', None), ('locked', 'B', None)],
    'Firework': [('fuse_progress', 'I', None), ('spark_count', 'I', None)],
    'Gate': [('gap_bottom', 'I', None), ('gap_top', 'I', None)],
    'Pendulum': [('has_twin', 'B', None)],
    'Piston': [('base_x', 'I', None), ('extent', 'I', None), ('glow', 'I', None)],
    'Stalactite': [('bottom_tip', 'I', None), ('top_tip', 'I', None)],
    'Updraft': [('gust_step', 'I', None)],
    'Wind': [('blowing', 'B', None), ('warning', 'B', None)],
}


def get_expr(ty, p):
    return {
        'Long': f'V::I(x{p})', 'Bool': f'V::B(x{p})', 'Str': f'V::S(x{p})', 'Rng': f'V::Rng(x{p})',
        'ListLong': f'V::L(x{p}.clone())', 'ArrLong': f'V::L(x{p}.to_vec())', 'ListBool': f'V::LB(x{p}.clone())',
        'ArrBool': f'V::LB(x{p}.to_vec())', 'Hazards': f'V::Objs(x{p}.len())',
        'Def': f'opt(x{p}.is_some())', 'Ref': f'opt(x{p}.is_some())', 'Child': f'opt(x{p}.is_some())',
    }[ty]


def set_stmt(ty, p):
    return {
        'Long': f'x{p} = v.i()', 'Bool': f'x{p} = v.b()', 'Rng': f'x{p} = v.rng()',
        'ListLong': f'x{p} = v.l().clone()', 'ArrLong': f'x{p} = v.l().as_slice().try_into().expect("array length")',
    }.get(ty)


def emit_class(c, rust_ty, lines, consts):
    fl = chain(c)
    cname = c.upper() if c in ('SimState', 'RoomRuntime') else c.upper()
    consts.append(f'pub const {cname}: &[F] = &[')
    for n, t, ro, p in fl:
        consts.append(f'    F {{ name: "{n}", ty: Ty::{t}, readonly: {"true" if ro else "false"} }},')
    consts.append('];')
    fn = c.lower()
    lines.append(f'fn {fn}_get(x: &{rust_ty}, i: usize) -> V {{')
    lines.append('    match i {')
    for i, (n, t, ro, p) in enumerate(fl):
        lines.append(f'        {i} => {get_expr(t, p)},')
    lines.append(f'        _ => panic!("{c}: no field {{}}", i),')
    lines.append('    }')
    lines.append('}')
    lines.append('')
    lines.append(f'fn {fn}_set(x: &mut {rust_ty}, i: usize, v: &V) {{')
    lines.append('    match i {')
    for i, (n, t, ro, p) in enumerate(fl):
        s = set_stmt(t, p)
        if s:
            lines.append(f'        {i} => {s},')
    lines.append(f'        _ => panic!("{c}: field {{}} is not a transplant candidate", i),')
    lines.append('    }')
    lines.append('}')
    lines.append('')
    lines.append(f'fn {fn}_method(x: &{rust_ty}, name: &str) -> Option<V> {{')
    ms = METHODS.get(c, [])
    if not any(call is None or 'x.' in (call or '') for n, k, call in ms if k != 'Obj'):
        lines.append('    let _ = x;')
    lines.append('    match name {')
    for n, k, call in ms:
        call = call or f'x.{n}()'
        lines.append(f'        "{n}" => Some({"V::Obj" if k == "Obj" else f"V::{k}({call})"}),')
    lines.append('        _ => None,')
    lines.append('    }')
    lines.append('}')
    lines.append('')


consts = []
lines = []
emit_class('SimState', 'SimState', lines, consts)
emit_class('RoomRuntime', 'RoomRuntime', lines, consts)
for h in HZ:
    emit_class(h, h, lines, consts)

hdr = '''//! GENERATED by gen/rs_fields.py from the Rust sim's structs (sim/src/sim_state.rs,
//! rooms/room_runtime.rs, hazards/*.rs): what C# `Visibility` (Measure/LeakRun.cs) got by
//! reflection. For every type: its fields in `Type.GetFields` order (the type's own fields, then
//! its parent's: `b: Bouncer`, `boss: Boss`, `c: CoinPickup`, `base: Base` last: kind, alive, t),
//! each with its Ty, a getter, a setter for the transplant candidates (value types, SimRng,
//! Vec<i64>, [i64; N]) and the no-argument methods visible.tsv may name. Regenerate when a sim
//! type gains or loses a field (see gen/README.md).
#![allow(clippy::match_single_binding)]
use sim::prelude::*;

/// The C# type of a field, as far as Visibility cares.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Ty {
    Long,
    Bool,
    /// `string` (a reference type: never a transplant candidate).
    Str,
    Rng,
    ListLong,
    ArrLong,
    ListBool,
    ArrBool,
    /// `List<Hazard>` (RoomRuntime.hazards).
    Hazards,
    /// `RoomDef`.
    Def,
    /// A reference to another hazard of the room (`Gate partner`).
    Ref,
    /// A hazard object of its own (`SplittingBouncer.other`).
    Child,
}

pub struct F {
    pub name: &'static str,
    pub ty: Ty,
    pub readonly: bool,
}

/// A field's value as `FieldInfo.GetValue` would box it. `Obj` is a non-null object (a def,
/// another hazard): hashed as nothing and equal to nothing but itself.
#[derive(Clone, Debug)]
pub enum V {
    Null,
    Obj,
    I(i64),
    B(bool),
    S(&'static str),
    Rng(SimRng),
    L(Vec<i64>),
    LB(Vec<bool>),
    Objs(usize),
}

impl V {
    fn i(&self) -> i64 {
        match self {
            V::I(x) => *x,
            _ => panic!("not a long: {:?}", self),
        }
    }
    fn b(&self) -> bool {
        match self {
            V::B(x) => *x,
            _ => panic!("not a bool: {:?}", self),
        }
    }
    fn rng(&self) -> SimRng {
        match self {
            V::Rng(x) => *x,
            _ => panic!("not a SimRng: {:?}", self),
        }
    }
    fn l(&self) -> &Vec<i64> {
        match self {
            V::L(x) => x,
            _ => panic!("not a list of longs: {:?}", self),
        }
    }
}

fn opt(some: bool) -> V {
    if some {
        V::Obj
    } else {
        V::Null
    }
}

'''

disp = []
disp.append('/// The C# class name of a hazard (`GetType().Name`).')
disp.append('pub fn hz_class(h: &Hz) -> &\'static str {')
disp.append('    match h {')
for h in HZ:
    disp.append(f'        Hz::{h}(_) => "{h}",')
disp.append('        Hz::Taken => panic!("Hz::Taken"),')
disp.append('    }')
disp.append('}')
disp.append('')
for fnname, sig, ret, call in [
    ('hz_get', 'h: &Hz, i: usize', 'V', 'get'),
    ('hz_set', 'h: &mut Hz, i: usize, v: &V', '()', 'set'),
    ('hz_method', 'h: &Hz, name: &str', 'Option<V>', 'method'),
]:
    disp.append(f'pub fn {fnname}({sig}) -> {ret} {{')
    disp.append('    match h {')
    for h in HZ:
        if call is None:
            disp.append(f'        Hz::{h}(_) => {h.upper()},')
        elif call == 'get':
            disp.append(f'        Hz::{h}(x) => {h.lower()}_get(x, i),')
        elif call == 'set':
            disp.append(f'        Hz::{h}(x) => {h.lower()}_set(x, i, v),')
        else:
            disp.append(f'        Hz::{h}(x) => {h.lower()}_method(x, name),')
    disp.append('        Hz::Taken => panic!("Hz::Taken"),')
    disp.append('    }')
    disp.append('}')
    disp.append('')
disp.append('/// The fields of a class by its C# name (SimState, RoomRuntime or a hazard).')
disp.append("pub fn class_fields(c: &str) -> &'static [F] {")
disp.append('    match c {')
for c in ['SimState', 'RoomRuntime'] + HZ:
    disp.append(f'        "{c}" => {c.upper()},')
disp.append('        _ => &[],')
disp.append('    }')
disp.append('}')
disp.append('')
disp.append('/// The no-argument methods of a class that `*_method` can call.')
disp.append("pub fn class_methods(c: &str) -> &'static [&'static str] {")
disp.append('    match c {')
for c, ms in METHODS.items():
    disp.append(f'        "{c}" => &[{", ".join(chr(34) + m[0] + chr(34) for m in ms)}],')
disp.append('        _ => &[],')
disp.append('    }')
disp.append('}')
disp.append('')
for c in ['SimState', 'RoomRuntime']:
    lo = c.lower()
    short = 'state' if c == 'SimState' else 'room'
    disp.append(f'pub fn {short}_get(x: &{c}, i: usize) -> V {{')
    disp.append(f'    {lo}_get(x, i)')
    disp.append('}')
    disp.append(f'pub fn {short}_set(x: &mut {c}, i: usize, v: &V) {{')
    disp.append(f'    {lo}_set(x, i, v)')
    disp.append('}')
    disp.append(f'pub fn {short}_method(x: &{c}, name: &str) -> Option<V> {{')
    disp.append(f'    {lo}_method(x, name)')
    disp.append('}')
    disp.append('')

open(OUT, 'w', newline='\n').write(hdr + '\n'.join(consts) + '\n\n' + '\n'.join(disp) + '\n' + '\n'.join(lines))
