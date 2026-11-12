import json, sys

cs = json.load(open(sys.argv[1]))
rs = json.load(open(sys.argv[2]))
OUT = sys.argv[3]
KW = {'def': 'def_', 'move': 'move_', 'crate': 'crate_', 'type': 'type_'}

HZ = ['Beam', 'Belt', 'Block', 'BossCrusher', 'BossSaw', 'BossWatcher', 'Bouncer', 'Bubble', 'Bumper', 'CoinPickup',
      'CrateDrop', 'Crawler', 'CuriousBouncer', 'Dart', 'Drop', 'Echo', 'EdgePad', 'ExitKey', 'Firework', 'Gate',
      'HeavyBouncer', 'KeepyBall', 'Lava', 'Mover', 'OrbitCoin', 'OrchardSpawner', 'PadCoin', 'Pendulum', 'Piston',
      'RevvingBouncer', 'Rotor', 'SawRing', 'SpikeBall', 'SplittingBouncer', 'Stalactite', 'Stalker', 'Updraft', 'Wind']

# The no-argument methods visible.tsv can name (C# Visibility.no_arg_method), by class:
# (name, V constructor, Rust call on `x`).
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
    'EdgePad': [('line_y', 'I', None), ('x0', 'I', None), ('x1', 'I', None)],
    'ExitKey': [('done', 'B', None), ('locked', 'B', None)],
    'Firework': [('fuse_progress', 'I', None), ('spark_count', 'I', None)],
    'Gate': [('gap_bottom', 'I', None), ('gap_top', 'I', None)],
    'Pendulum': [('has_twin', 'B', None)],
    'Piston': [('base_x', 'I', None), ('extent', 'I', None), ('glow', 'I', None)],
    'Stalactite': [('bottom_tip', 'I', None), ('top_tip', 'I', None)],
    'Updraft': [('gust_step', 'I', None)],
    'Wind': [('blowing', 'B', None), ('warning', 'B', None)],
}

TY = {'long': 'Long', 'bool': 'Bool', 'string': 'Str', 'SimRng': 'Rng', 'List<long>': 'ListLong',
      'long[]': 'ArrLong', 'List<bool>': 'ListBool', 'bool[]': 'ArrBool', 'List<Hazard>': 'Hazards',
      'RoomDef': 'Def', 'Gate': 'Ref', 'Piston': 'Ref', 'Stalactite': 'Ref', 'Bouncer': 'Child'}


def chain(c):
    """C# reflection order (Visibility.fields): own fields, then the base classes'."""
    out = []
    path = ''
    while c is not None:
        for n, t, ro in cs[c]['fields']:
            out.append((n, t, ro, path + '.' + KW.get(n, n)))
        base = cs[c]['base']
        if base is None:
            break
        if c in rs:
            # The Rust field holding the parent (`base: Base`, `b: Bouncer`, `boss: Boss`, `c: CoinPickup`).
            want = 'Base' if base == 'Hazard' else base
            pf = [f for f, t in rs[c] if t == want]
            assert len(pf) == 1, (c, base)
            path += '.' + pf[0]
        c = base
    return out


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
        consts.append(f'    F {{ name: "{n}", ty: Ty::{TY[t]}, readonly: {"true" if ro else "false"} }},')
    consts.append('];')
    fn = c.lower()
    lines.append(f'fn {fn}_get(x: &{rust_ty}, i: usize) -> V {{')
    lines.append('    match i {')
    for i, (n, t, ro, p) in enumerate(fl):
        lines.append(f'        {i} => {get_expr(TY[t], p)},')
    lines.append(f'        _ => panic!("{c}: no field {{}}", i),')
    lines.append('    }')
    lines.append('}')
    lines.append('')
    lines.append(f'fn {fn}_set(x: &mut {rust_ty}, i: usize, v: &V) {{')
    lines.append('    match i {')
    for i, (n, t, ro, p) in enumerate(fl):
        s = set_stmt(TY[t], p)
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

hdr = '''//! GENERATED from the C# sim's field declarations (Sim/SimState.cs, Sim/Rooms/RoomRuntime.cs,
//! Sim/Hazards/*.cs) and the Rust structs: what C# `Visibility` (Measure/LeakRun.cs) gets by
//! reflection. For every type: its instance fields in C# `Type.GetFields` order (the class's
//! own fields, then its base classes', `Hazard` last: kind, alive, t), each with its C# type,
//! a getter, a setter for the transplant candidates (value types, SimRng, List<long>, long[])
//! and the no-argument methods visible.tsv may name. A field added to the sim must be added
//! here too (regenerate: the script is described in measure/leak_run.rs).
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
