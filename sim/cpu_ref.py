"""cpu_ref.py - modello di riferimento del 65C816, un'istruzione alla volta.

Scritto dal comportamento documentato del processore, non dal Verilog: serve a generare i vettori
del banco di prova (sim/cpu_vectors.py). Copre solo gli opcode in OPCODES. WDM ($42) si comporta
come sul chip vero: salta due byte. ADC e SBC sono modellati solo in binario (flag D = 0).
Non conta i cicli.
"""

N, V, M, X, D, I, Z, C = 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01

REGS = ('pc', 's', 'p', 'a', 'x', 'y', 'dbr', 'd', 'pbr', 'e')

# opcode -> (operazione, modo di indirizzamento o argomento)
OPCODES = {
    0xA9: ('lda', 'imm'), 0xAD: ('lda', 'abs'), 0xBD: ('lda', 'absx'), 0xAF: ('lda', 'long'),
    0xA2: ('ldx', 'imm'), 0xAE: ('ldx', 'abs'), 0xA0: ('ldy', 'imm'), 0xAC: ('ldy', 'abs'),
    0x8D: ('sta', 'abs'), 0x9D: ('sta', 'absx'), 0x8F: ('sta', 'long'),
    0x8E: ('stx', 'abs'), 0x8C: ('sty', 'abs'),
    0x69: ('adc', 'imm'), 0x6D: ('adc', 'abs'), 0xE9: ('sbc', 'imm'),
    0xC9: ('cmp', 'imm'), 0xCD: ('cmp', 'abs'),
    0x29: ('and_', 'imm'), 0x09: ('ora', 'imm'), 0x49: ('eor', 'imm'),
    0xE8: ('step', ('x', 1)), 0xCA: ('step', ('x', -1)),
    0xC8: ('step', ('y', 1)), 0x88: ('step', ('y', -1)),
    0x1A: ('step', ('a', 1)), 0x3A: ('step', ('a', -1)),
    0xAA: ('to_index', 'x'), 0xA8: ('to_index', 'y'),
    0x8A: ('to_acc', 'x'), 0x98: ('to_acc', 'y'),
    0x18: ('flag', (C, False)), 0x38: ('flag', (C, True)),
    0x78: ('flag', (I, True)), 0x58: ('flag', (I, False)),
    0xFB: ('xce', None), 0xC2: ('rep', None), 0xE2: ('sep', None),
    0x80: ('branch', None), 0xD0: ('branch', (Z, False)), 0xF0: ('branch', (Z, True)),
    0x90: ('branch', (C, False)), 0xB0: ('branch', (C, True)),
    0x10: ('branch', (N, False)), 0x30: ('branch', (N, True)),
    0x4C: ('jmp', None), 0x5C: ('jml', None), 0x20: ('jsr', None), 0x60: ('rts', None),
    0x48: ('pha', None), 0x68: ('pla', None),
    0xEA: ('nop', None), 0x42: ('wdm', None),
}


class Cpu:
    """Stato dei registri piu' una memoria riempita a richiesta.

    new_byte(kind) fornisce il valore di un byte mai visto; kind e' 'code' o 'data'.
    Dopo step(): self.initial = memoria richiesta prima di eseguire, self.mem = memoria finale.
    """

    def __init__(self, regs, new_byte):
        for r in REGS:
            setattr(self, r, regs[r])
        self.new_byte = new_byte
        self.mem = {}
        self.initial = {}

    def regs(self):
        return {r: getattr(self, r) for r in REGS}

    # ---- memoria ----
    def read(self, addr, kind='data'):
        addr &= 0xFFFFFF
        if addr not in self.mem:
            self.mem[addr] = self.initial[addr] = self.new_byte(kind) & 0xFF
        return self.mem[addr]

    def write(self, addr, value):
        self.mem[addr & 0xFFFFFF] = value & 0xFF

    def fetch(self, count=1):
        value = 0
        for i in range(count):
            value |= self.read((self.pbr << 16) | self.pc, 'code') << (8 * i)
            self.pc = (self.pc + 1) & 0xFFFF
        return value

    # ---- larghezze, flag, indirizzi ----
    def m8(self):
        return bool(self.p & M)

    def x8(self):
        return bool(self.p & X)

    def setf(self, bit, on):
        self.p = (self.p | bit) if on else (self.p & ~bit & 0xFF)

    def nz(self, value, w8):
        sign, mask = (0x80, 0xFF) if w8 else (0x8000, 0xFFFF)
        self.setf(N, value & sign)
        self.setf(Z, (value & mask) == 0)

    def effective(self, mode):
        if mode == 'abs':
            return (self.dbr << 16) | self.fetch(2)
        if mode == 'absx':
            return (((self.dbr << 16) | self.fetch(2)) + self.x) & 0xFFFFFF
        if mode == 'long':
            return self.fetch(3)
        raise ValueError(mode)

    def operand(self, mode, w8):
        if mode == 'imm':
            return self.fetch(1 if w8 else 2)
        ea = self.effective(mode)
        value = self.read(ea)
        if not w8:
            value |= self.read(ea + 1) << 8
        return value

    def store(self, mode, value, w8):
        ea = self.effective(mode)
        self.write(ea, value)
        if not w8:
            self.write(ea + 1, value >> 8)

    def set_a(self, value):
        if self.m8():
            self.a = (self.a & 0xFF00) | (value & 0xFF)
        else:
            self.a = value & 0xFFFF
        self.nz(value, self.m8())

    def set_index(self, reg, value):
        value &= 0xFF if self.x8() else 0xFFFF
        setattr(self, reg, value)
        self.nz(value, self.x8())

    # ---- pila (in emulazione resta nella pagina 1 per le istruzioni qui modellate) ----
    def move_sp(self, delta):
        if self.e:
            self.s = 0x0100 | ((self.s + delta) & 0xFF)
        else:
            self.s = (self.s + delta) & 0xFFFF

    def push(self, value):
        self.write(self.s, value)
        self.move_sp(-1)

    def pull(self):
        self.move_sp(1)
        return self.read(self.s)

    def width_rules(self):
        if self.e:
            self.p |= M | X
        if self.p & X:
            self.x &= 0xFF
            self.y &= 0xFF

    # ---- esecuzione ----
    def step(self):
        if self.e:  # in emulazione il byte alto di S vale sempre 01
            self.s = 0x0100 | (self.s & 0xFF)
        op = self.fetch()
        name, arg = OPCODES[op]
        getattr(self, 'op_' + name)(arg)
        return op

    def op_lda(self, mode):
        self.set_a(self.operand(mode, self.m8()))

    def op_ldx(self, mode):
        self.set_index('x', self.operand(mode, self.x8()))

    def op_ldy(self, mode):
        self.set_index('y', self.operand(mode, self.x8()))

    def op_sta(self, mode):
        self.store(mode, self.a, self.m8())

    def op_stx(self, mode):
        self.store(mode, self.x, self.x8())

    def op_sty(self, mode):
        self.store(mode, self.y, self.x8())

    def add(self, value):
        if self.p & D:
            raise ValueError('modo decimale non modellato')
        w8 = self.m8()
        mask, sign = (0xFF, 0x80) if w8 else (0xFFFF, 0x8000)
        a = self.a & mask
        r = a + value + (self.p & C)
        self.setf(C, r > mask)
        self.setf(V, ~(a ^ value) & (a ^ r) & sign)
        self.set_a(r & mask)

    def op_adc(self, mode):
        self.add(self.operand(mode, self.m8()))

    def op_sbc(self, mode):
        mask = 0xFF if self.m8() else 0xFFFF
        self.add(self.operand(mode, self.m8()) ^ mask)

    def op_cmp(self, mode):
        value = self.operand(mode, self.m8())
        mask = 0xFF if self.m8() else 0xFFFF
        a = self.a & mask
        self.setf(C, a >= value)
        self.nz((a - value) & mask, self.m8())

    def op_and_(self, mode):
        self.set_a(self.a & self.operand(mode, self.m8()))

    def op_ora(self, mode):
        mask = 0xFF if self.m8() else 0xFFFF
        self.set_a((self.a & mask) | self.operand(mode, self.m8()))

    def op_eor(self, mode):
        mask = 0xFF if self.m8() else 0xFFFF
        self.set_a((self.a & mask) ^ self.operand(mode, self.m8()))

    def op_step(self, arg):
        reg, delta = arg
        if reg == 'a':
            self.set_a(self.a + delta)
        else:
            self.set_index(reg, getattr(self, reg) + delta)

    def op_to_index(self, reg):
        self.set_index(reg, self.a)

    def op_to_acc(self, reg):
        self.set_a(getattr(self, reg))

    def op_flag(self, arg):
        self.setf(*arg)

    def op_xce(self, _):
        carry = self.p & C
        self.setf(C, self.e)
        self.e = 1 if carry else 0
        if self.e:
            self.s = 0x0100 | (self.s & 0xFF)
        self.width_rules()

    def op_rep(self, _):
        self.p &= ~self.fetch() & 0xFF
        self.width_rules()

    def op_sep(self, _):
        self.p |= self.fetch()
        self.width_rules()

    def op_branch(self, cond):
        offset = self.fetch()
        if cond is None or bool(self.p & cond[0]) == cond[1]:
            self.pc = (self.pc + (offset - 0x100 if offset & 0x80 else offset)) & 0xFFFF

    def op_jmp(self, _):
        self.pc = self.fetch(2)

    def op_jml(self, _):
        target = self.fetch(3)
        self.pc, self.pbr = target & 0xFFFF, target >> 16

    def op_jsr(self, _):
        target = self.fetch(2)
        back = (self.pc - 1) & 0xFFFF
        self.push(back >> 8)
        self.push(back)
        self.pc = target

    def op_rts(self, _):
        lo = self.pull()
        hi = self.pull()
        self.pc = (((hi << 8) | lo) + 1) & 0xFFFF

    def op_pha(self, _):
        if not self.m8():
            self.push(self.a >> 8)
        self.push(self.a)

    def op_pla(self, _):
        value = self.pull()
        if not self.m8():
            value |= self.pull() << 8
        self.set_a(value)

    def op_nop(self, _):
        pass

    def op_wdm(self, _):
        # il secondo byte viene saltato: il chip non lo legge come dato valido
        self.pc = (self.pc + 1) & 0xFFFF
