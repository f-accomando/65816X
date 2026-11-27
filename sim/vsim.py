#!/usr/bin/env python3
"""vsim.py - mini simulatore Verilog (sottoinsieme sincrono, un solo clock).

Scritto perche' nell'ambiente di sviluppo non erano disponibili iverilog/verilator.
Supporta: moduli ANSI, wire/reg/array, localparam, assign, always @(posedge clk) e @*,
if/case, assegnazioni bloccanti e non bloccanti, concatenazioni, istanze con porte per nome.
NON supporta: parametri di istanza, generate, function/task, signed, x/z, piu' clock.
Non sostituisce iverilog/verilator: serve come test di regressione rapido e senza dipendenze.
"""
import re

class VErr(Exception):
    pass

def mask(w):
    return (1 << w) - 1

_TOK = re.compile(r'''
 (?P<ws>\s+) |
 (?P<com>//[^\n]*|/\*.*?\*/) |
 (?P<str>"[^"]*") |
 (?P<num>\d[\d_]*'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ]+|\d[\d_]*) |
 (?P<id>[A-Za-z_$][A-Za-z0-9_$]*) |
 (?P<op><<|>>|<=|>=|==|!=|&&|\|\||[-+*/%&|^~!<>=?:;,.\#@(){}\[\]])
''', re.X | re.S)

def tokenize(src):
    out = []
    pos = 0
    while pos < len(src):
        m = _TOK.match(src, pos)
        if not m:
            raise VErr("carattere non riconosciuto: %r" % src[pos:pos + 20])
        pos = m.end()
        k = m.lastgroup
        if k in ('ws', 'com'):
            continue
        out.append((k, m.group()))
    return out

def parse_num(text):
    text = text.replace('_', '')
    if "'" in text:
        size, rest = text.split("'")
        rest = rest.lstrip('sS')
        base = {'b': 2, 'o': 8, 'd': 10, 'h': 16}[rest[0].lower()]
        digits = re.sub('[xXzZ]', '0', rest[1:])
        w = int(size)
        return ('num', int(digits, base) & mask(w), w)
    return ('num', int(text), 32)

class Module:
    def __init__(self, name):
        self.name = name
        self.ports = []      # (dir, name)
        self.sigs = {}       # name -> (width, depth|None)
        self.params = {}     # name -> (value, width)
        self.assigns = []    # (lhs, expr)
        self.combs = []
        self.seqs = []
        self.insts = []      # (modname, instname, {port: expr|None})

BINLEVELS = [['||'], ['&&'], ['|'], ['^'], ['&'], ['==', '!='], ['<', '<=', '>', '>='],
             ['<<', '>>'], ['+', '-'], ['*', '/', '%']]

def const_eval(n, params):
    t = n[0]
    if t == 'num':
        return n[1]
    if t == 'id':
        return params[n[1]][0]
    if t == 'bin':
        a = const_eval(n[2], params)
        b = const_eval(n[3], params)
        return {'+': a + b, '-': a - b, '*': a * b, '/': a // b if b else 0,
                '<<': a << b, '>>': a >> b}[n[1]]
    if t == 'un' and n[1] == '-':
        return -const_eval(n[2], params)
    raise VErr("espressione non costante: %r" % (n,))

class Parser:
    def __init__(self, toks):
        self.t = toks
        self.i = 0
        self.mod = None

    def peek(self, k=0):
        j = self.i + k
        return self.t[j][1] if j < len(self.t) else None

    def kind(self):
        return self.t[self.i][0]

    def next(self):
        tok = self.t[self.i][1]
        self.i += 1
        return tok

    def expect(self, s):
        got = self.next()
        if got != s:
            raise VErr("atteso %r, trovato %r (token %d)" % (s, got, self.i))

    def const(self, e):
        return const_eval(e, self.mod.params)

    def rng(self):
        self.expect('[')
        hi = self.const(self.parse_expr())
        self.expect(':')
        lo = self.const(self.parse_expr())
        self.expect(']')
        return abs(hi - lo) + 1

    def modules(self):
        mods = []
        while self.i < len(self.t):
            mods.append(self.module())
        return mods

    def module(self):
        self.expect('module')
        m = Module(self.next())
        self.mod = m
        self.expect('(')
        width = 1
        dirn = None
        while self.peek() != ')':
            if self.peek() in ('input', 'output', 'inout'):
                dirn = self.next()
                width = 1
                if self.peek() in ('wire', 'reg'):
                    self.next()
                if self.peek() == '[':
                    width = self.rng()
            name = self.next()
            m.ports.append((dirn, name))
            m.sigs[name] = (width, None)
            if self.peek() == ',':
                self.next()
        self.expect(')')
        self.expect(';')
        while self.peek() != 'endmodule':
            p = self.peek()
            if p in ('wire', 'reg'):
                self.decl()
            elif p in ('localparam', 'parameter'):
                self.next()
                while True:
                    name = self.next()
                    self.expect('=')
                    e = self.parse_expr()
                    w = e[2] if e[0] == 'num' else 32
                    m.params[name] = (self.const(e), w)
                    if self.peek() == ',':
                        self.next()
                        continue
                    break
                self.expect(';')
            elif p == 'assign':
                self.next()
                lhs = self.lvalue()
                self.expect('=')
                e = self.parse_expr()
                self.expect(';')
                m.assigns.append((lhs, e))
            elif p == 'always':
                self.next()
                self.expect('@')
                if self.peek() == '*':
                    self.next()
                    kind = 'comb'
                else:
                    self.expect('(')
                    if self.peek() == '*':
                        self.next()
                        kind = 'comb'
                    else:
                        self.expect('posedge')
                        self.next()
                        kind = 'seq'
                    self.expect(')')
                st = self.stmt()
                (m.combs if kind == 'comb' else m.seqs).append(st)
            elif p == 'initial':
                self.next()
                if self.peek() == 'begin':
                    depth = 0
                    while True:
                        x = self.next()
                        if x == 'begin':
                            depth += 1
                        elif x == 'end':
                            depth -= 1
                            if depth == 0:
                                break
                else:
                    while self.next() != ';':
                        pass
            else:
                self.instance()
        self.expect('endmodule')
        return m

    def decl(self):
        self.next()
        width = 1
        if self.peek() == '[':
            width = self.rng()
        while True:
            name = self.next()
            depth = None
            if self.peek() == '[':
                depth = self.rng()
            self.mod.sigs[name] = (width, depth)
            if self.peek() == '=':
                self.next()
                self.mod.assigns.append((('id', name), self.parse_expr()))
            if self.peek() == ',':
                self.next()
                continue
            break
        self.expect(';')

    def instance(self):
        modname = self.next()
        instname = self.next()
        self.expect('(')
        conns = {}
        while self.peek() != ')':
            self.expect('.')
            port = self.next()
            self.expect('(')
            if self.peek() == ')':
                conns[port] = None
            else:
                conns[port] = self.parse_expr()
            self.expect(')')
            if self.peek() == ',':
                self.next()
        self.expect(')')
        self.expect(';')
        self.mod.insts.append((modname, instname, conns))

    def lvalue(self):
        name = self.next()
        if self.peek() == '[':
            self.next()
            e1 = self.parse_expr()
            if self.peek() == ':':
                self.next()
                e2 = self.parse_expr()
                self.expect(']')
                return ('slice', name, self.const(e1), self.const(e2))
            self.expect(']')
            return ('idx', name, e1)
        return ('id', name)

    def stmt(self):
        p = self.peek()
        if p == 'begin':
            self.next()
            body = []
            while self.peek() != 'end':
                body.append(self.stmt())
            self.next()
            return ('block', body)
        if p == 'if':
            self.next()
            self.expect('(')
            c = self.parse_expr()
            self.expect(')')
            th = self.stmt()
            el = None
            if self.peek() == 'else':
                self.next()
                el = self.stmt()
            return ('if', c, th, el)
        if p == 'case':
            self.next()
            self.expect('(')
            ex = self.parse_expr()
            self.expect(')')
            items = []
            while self.peek() != 'endcase':
                if self.peek() == 'default':
                    self.next()
                    self.expect(':')
                    items.append((None, self.stmt()))
                else:
                    labels = [self.parse_bin(0)]
                    while self.peek() == ',':
                        self.next()
                        labels.append(self.parse_bin(0))
                    self.expect(':')
                    items.append((labels, self.stmt()))
            self.next()
            return ('case', ex, items)
        if p == ';':
            self.next()
            return ('nop',)
        lhs = self.lvalue()
        op = self.next()
        if op not in ('=', '<='):
            raise VErr("assegnazione attesa, trovato %r" % op)
        rhs = self.parse_expr()
        self.expect(';')
        return ('asn', op, lhs, rhs)

    def parse_expr(self):
        c = self.parse_bin(0)
        if self.peek() == '?':
            self.next()
            a = self.parse_expr()
            self.expect(':')
            b = self.parse_expr()
            return ('tern', c, a, b)
        return c

    def parse_bin(self, lvl):
        if lvl == len(BINLEVELS):
            return self.parse_unary()
        left = self.parse_bin(lvl + 1)
        while self.peek() in BINLEVELS[lvl]:
            op = self.next()
            right = self.parse_bin(lvl + 1)
            left = ('bin', op, left, right)
        return left

    def parse_unary(self):
        if self.peek() in ('~', '!', '-', '+') and self.kind() == 'op':
            op = self.next()
            return ('un', op, self.parse_unary())
        return self.primary()

    def primary(self):
        k = self.kind()
        t = self.next()
        if k == 'num':
            return parse_num(t)
        if t == '(':
            e = self.parse_expr()
            self.expect(')')
            return e
        if t == '{':
            first = self.parse_expr()
            if self.peek() == '{':
                self.next()
                items = [self.parse_expr()]
                while self.peek() == ',':
                    self.next()
                    items.append(self.parse_expr())
                self.expect('}')
                self.expect('}')
                return ('rep', self.const(first), ('cat', items))
            items = [first]
            while self.peek() == ',':
                self.next()
                items.append(self.parse_expr())
            self.expect('}')
            return ('cat', items)
        if k == 'id':
            if self.peek() == '[':
                self.next()
                e1 = self.parse_expr()
                if self.peek() == ':':
                    self.next()
                    e2 = self.parse_expr()
                    self.expect(']')
                    return ('slice', t, self.const(e1), self.const(e2))
                self.expect(']')
                return ('idx', t, e1)
            return ('id', t)
        raise VErr("token inatteso %r" % t)

def parse_source(src):
    return Parser(tokenize(src)).modules()

class Inst:
    def __init__(self, mod, path):
        self.mod = mod
        self.path = path
        self.v = {}
        self.arr = {}
        self.children = {}
        for name, (w, depth) in mod.sigs.items():
            if depth:
                self.arr[name] = [0] * depth
            else:
                self.v[name] = 0

class Sim:
    def __init__(self, sources, top):
        self.mods = {}
        for s in sources:
            for m in parse_source(s):
                self.mods[m.name] = m
        self._wd = {}
        self.combs = []
        self.seqs = []
        self.top = self._build(self.mods[top], top)
        self.settle()

    # ---------- elaborazione ----------
    def _build(self, mod, path):
        inst = Inst(mod, path)
        for lhs, e in mod.assigns:
            self.combs.append(self._mk_assign(inst, lhs, e))
        for st in mod.combs:
            self.combs.append(self._mk_comb(inst, st))
        for st in mod.seqs:
            self.seqs.append((inst, st))
        for modname, iname, conns in mod.insts:
            if modname not in self.mods:
                raise VErr("modulo sconosciuto %s" % modname)
            child = self._build(self.mods[modname], path + '.' + iname)
            inst.children[iname] = child
            dirs = dict((n, d) for d, n in child.mod.ports)
            for port, e in conns.items():
                if e is None:
                    continue
                if dirs[port] == 'input':
                    self.combs.append(self._mk_conn_in(inst, child, port, e))
                else:
                    self.combs.append(self._mk_conn_out(inst, child, port, e))
        return inst

    def _mk_assign(self, inst, lhs, e):
        def run():
            before = self._read_lhs(inst, lhs)
            self.exec(inst, ('asn', '=', lhs, e), None)
            return before != self._read_lhs(inst, lhs)
        return run

    def _read_lhs(self, inst, lhs):
        if lhs[0] == 'id':
            return inst.v[lhs[1]]
        return inst.v[lhs[1]]

    def _assigned(self, st, acc):
        t = st[0]
        if t == 'block':
            for s in st[1]:
                self._assigned(s, acc)
        elif t == 'if':
            self._assigned(st[2], acc)
            if st[3]:
                self._assigned(st[3], acc)
        elif t == 'case':
            for _, s in st[2]:
                self._assigned(s, acc)
        elif t == 'asn':
            acc.add(st[2][1])
        return acc

    def _mk_comb(self, inst, st):
        names = sorted(self._assigned(st, set()))
        def run():
            before = tuple(inst.v[n] for n in names)
            self.exec(inst, st, None)
            return before != tuple(inst.v[n] for n in names)
        return run

    def _mk_conn_in(self, parent, child, port, e):
        w = child.mod.sigs[port][0]
        def run():
            val = self.ev(parent, e, max(w, self.wd(parent.mod, e))) & mask(w)
            if child.v[port] != val:
                child.v[port] = val
                return True
            return False
        return run

    def _mk_conn_out(self, parent, child, port, e):
        if e[0] != 'id':
            raise VErr("uscita collegata a un'espressione non semplice: %r" % (e,))
        w = parent.mod.sigs[e[1]][0]
        def run():
            val = child.v[port] & mask(w)
            if parent.v[e[1]] != val:
                parent.v[e[1]] = val
                return True
            return False
        return run

    # ---------- larghezze e valutazione ----------
    def wd(self, mod, n):
        key = id(n)
        r = self._wd.get(key)
        if r is not None:
            return r
        t = n[0]
        if t == 'num':
            r = n[2]
        elif t == 'id':
            r = mod.sigs[n[1]][0] if n[1] in mod.sigs else mod.params[n[1]][1]
        elif t == 'idx':
            s = mod.sigs[n[1]]
            r = s[0] if s[1] else 1
        elif t == 'slice':
            r = n[2] - n[3] + 1
        elif t == 'un':
            r = 1 if n[1] == '!' else self.wd(mod, n[2])
        elif t == 'bin':
            op = n[1]
            if op in ('&&', '||', '==', '!=', '<', '<=', '>', '>='):
                r = 1
            elif op in ('<<', '>>'):
                r = self.wd(mod, n[2])
            else:
                r = max(self.wd(mod, n[2]), self.wd(mod, n[3]))
        elif t == 'tern':
            r = max(self.wd(mod, n[2]), self.wd(mod, n[3]))
        elif t == 'cat':
            r = sum(self.wd(mod, p) for p in n[1])
        elif t == 'rep':
            r = n[1] * self.wd(mod, n[2])
        else:
            raise VErr("nodo sconosciuto %r" % (t,))
        self._wd[key] = r
        return r

    def ev(self, inst, n, w):
        t = n[0]
        mod = inst.mod
        if t == 'num':
            return n[1]
        if t == 'id':
            v = inst.v.get(n[1])
            if v is None:
                v = mod.params[n[1]][0]
            return v
        if t == 'idx':
            i = self.ev(inst, n[2], max(1, self.wd(mod, n[2])))
            a = inst.arr.get(n[1])
            if a is not None:
                return a[i] if 0 <= i < len(a) else 0
            return (inst.v[n[1]] >> i) & 1
        if t == 'slice':
            return (inst.v[n[1]] >> n[3]) & mask(n[2] - n[3] + 1)
        if t == 'un':
            op, e = n[1], n[2]
            if op == '!':
                return 0 if self.ev(inst, e, self.wd(mod, e)) else 1
            w2 = max(w, self.wd(mod, e))
            x = self.ev(inst, e, w2)
            if op == '~':
                return (~x) & mask(w2)
            if op == '-':
                return (-x) & mask(w2)
            return x
        if t == 'bin':
            op, a, b = n[1], n[2], n[3]
            if op == '&&':
                return int(self.ev(inst, a, self.wd(mod, a)) != 0 and self.ev(inst, b, self.wd(mod, b)) != 0)
            if op == '||':
                return int(self.ev(inst, a, self.wd(mod, a)) != 0 or self.ev(inst, b, self.wd(mod, b)) != 0)
            if op in ('==', '!=', '<', '<=', '>', '>='):
                w2 = max(self.wd(mod, a), self.wd(mod, b))
                x, y = self.ev(inst, a, w2), self.ev(inst, b, w2)
                return int({'==': x == y, '!=': x != y, '<': x < y, '<=': x <= y,
                            '>': x > y, '>=': x >= y}[op])
            if op in ('<<', '>>'):
                w2 = max(w, self.wd(mod, a))
                x = self.ev(inst, a, w2)
                s = self.ev(inst, b, self.wd(mod, b))
                return ((x << s) & mask(w2)) if op == '<<' else (x >> s)
            w2 = max(w, self.wd(mod, a), self.wd(mod, b))
            x, y = self.ev(inst, a, w2), self.ev(inst, b, w2)
            if op == '+':
                r = x + y
            elif op == '-':
                r = x - y
            elif op == '*':
                r = x * y
            elif op == '&':
                r = x & y
            elif op == '|':
                r = x | y
            elif op == '^':
                r = x ^ y
            elif op == '/':
                r = x // y if y else 0
            else:
                r = x % y if y else 0
            return r & mask(w2)
        if t == 'tern':
            c = self.ev(inst, n[1], self.wd(mod, n[1]))
            w2 = max(w, self.wd(mod, n[2]), self.wd(mod, n[3]))
            return self.ev(inst, n[2] if c else n[3], w2)
        if t == 'cat':
            acc = 0
            for p in n[1]:
                pw = self.wd(mod, p)
                acc = (acc << pw) | (self.ev(inst, p, pw) & mask(pw))
            return acc
        if t == 'rep':
            inner = n[2]
            pw = self.wd(mod, inner)
            v = self.ev(inst, inner, pw)
            acc = 0
            for _ in range(n[1]):
                acc = (acc << pw) | v
            return acc
        raise VErr("nodo sconosciuto %r" % (t,))

    # ---------- esecuzione ----------
    def exec(self, inst, s, nba):
        t = s[0]
        mod = inst.mod
        if t == 'block':
            for x in s[1]:
                self.exec(inst, x, nba)
        elif t == 'if':
            if self.ev(inst, s[1], self.wd(mod, s[1])):
                self.exec(inst, s[2], nba)
            elif s[3] is not None:
                self.exec(inst, s[3], nba)
        elif t == 'case':
            w = self.wd(mod, s[1])
            default = None
            for labels, _ in s[2]:
                if labels:
                    for l in labels:
                        w = max(w, self.wd(mod, l))
            v = self.ev(inst, s[1], w)
            for labels, st in s[2]:
                if labels is None:
                    default = st
                    continue
                for l in labels:
                    if self.ev(inst, l, w) == v:
                        self.exec(inst, st, nba)
                        return
            if default is not None:
                self.exec(inst, default, nba)
        elif t == 'asn':
            op, lhs, rhs = s[1], s[2], s[3]
            kind = lhs[0]
            name = lhs[1]
            sig = mod.sigs[name]
            if kind == 'id':
                W = sig[0]
                tgt = ('id', name)
            elif kind == 'idx':
                idx = self.ev(inst, lhs[2], max(1, self.wd(mod, lhs[2])))
                if sig[1]:
                    W = sig[0]
                    tgt = ('arr', name, idx)
                else:
                    W = 1
                    tgt = ('bit', name, idx)
            else:
                W = lhs[2] - lhs[3] + 1
                tgt = ('sl', name, lhs[3], W)
            val = self.ev(inst, rhs, max(W, self.wd(mod, rhs))) & mask(W)
            if op == '=':
                self.apply(inst, tgt, val)
            else:
                nba.append((inst, tgt, val))

    def apply(self, inst, tgt, val):
        k = tgt[0]
        name = tgt[1]
        if k == 'id':
            inst.v[name] = val
        elif k == 'arr':
            a = inst.arr[name]
            if 0 <= tgt[2] < len(a):
                a[tgt[2]] = val
        elif k == 'bit':
            i = tgt[2]
            inst.v[name] = (inst.v[name] & ~(1 << i)) | (val << i)
        else:
            lo, W = tgt[2], tgt[3]
            inst.v[name] = (inst.v[name] & ~(mask(W) << lo)) | (val << lo)

    def settle(self):
        for _ in range(200):
            changed = False
            for p in self.combs:
                if p():
                    changed = True
            if not changed:
                return
        raise VErr("la logica combinatoria non converge")

    def tick(self):
        nba = []
        for inst, st in self.seqs:
            self.exec(inst, st, nba)
        for inst, tgt, val in nba:
            self.apply(inst, tgt, val)
        self.settle()

    # ---------- accesso per nome gerarchico ----------
    def _find(self, path):
        parts = path.split('.')
        inst = self.top
        for p in parts[:-1]:
            inst = inst.children[p]
        return inst, parts[-1]

    def poke(self, path, value):
        inst, name = self._find(path)
        inst.v[name] = value & mask(inst.mod.sigs[name][0])
        self.settle()

    def peek(self, path):
        inst, name = self._find(path)
        return inst.v[name]

    def array(self, path):
        inst, name = self._find(path)
        return inst.arr[name]
