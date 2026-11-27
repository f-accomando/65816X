"""cpu_ref.py - modello di riferimento del 65C816, un'istruzione alla volta.

Scritto dal comportamento documentato del processore, non dal Verilog: serve a generare i vettori
del banco di prova (sim/cpu_vectors.py). Copre solo gli opcode in OPCODES. WDM ($42) si comporta
come sul chip vero: salta due byte. ADC e SBC sono modellati solo in binario (flag D = 0).
Registra ogni ciclo di bus in self.cycles come (tipo, indirizzo, byte): tipo bit 0 = VDA,
bit 1 = VPA, bit 2 = scrittura; byte = None nei cicli interni.
"""

N, V, M, X, D, I, Z, C = 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01

REGS = ('pc', 's', 'p', 'a', 'x', 'y', 'dbr', 'd', 'pbr', 'e')

# modi di indirizzamento delle otto istruzioni del primo gruppo: scostamento dall'opcode base
# dp = direct page, i = indiretto, il = indiretto lungo, sr = relativo alla pila
GROUP_ONE_MODES = (
    (0x01, 'dpxi'), (0x03, 'sr'), (0x05, 'dp'), (0x07, 'dpil'), (0x09, 'imm'), (0x0D, 'abs'),
    (0x0F, 'long'), (0x11, 'dpiy'), (0x12, 'dpi'), (0x13, 'sriy'), (0x15, 'dpx'), (0x17, 'dpily'),
    (0x19, 'absy'), (0x1D, 'absx'), (0x1F, 'longx'),
)
GROUP_ONE = ((0x00, 'ora'), (0x20, 'and_'), (0x40, 'eor'), (0x60, 'adc'), (0x80, 'sta'),
             (0xA0, 'lda'), (0xC0, 'cmp'), (0xE0, 'sbc'))

# opcode -> (operazione, modo di indirizzamento o argomento)
OPCODES = {base + offset: (name, mode) for base, name in GROUP_ONE for offset, mode in GROUP_ONE_MODES
           if not (name == 'sta' and mode == 'imm')}
OPCODES.update({
    0xA2: ('ldx', 'imm'), 0xA6: ('ldx', 'dp'), 0xAE: ('ldx', 'abs'), 0xB6: ('ldx', 'dpy'),
    0xBE: ('ldx', 'absy'),
    0xA0: ('ldy', 'imm'), 0xA4: ('ldy', 'dp'), 0xAC: ('ldy', 'abs'), 0xB4: ('ldy', 'dpx'),
    0xBC: ('ldy', 'absx'),
    0x86: ('stx', 'dp'), 0x8E: ('stx', 'abs'), 0x96: ('stx', 'dpy'),
    0x84: ('sty', 'dp'), 0x8C: ('sty', 'abs'), 0x94: ('sty', 'dpx'),
    0x64: ('stz', 'dp'), 0x74: ('stz', 'dpx'), 0x9C: ('stz', 'abs'), 0x9E: ('stz', 'absx'),
    0xE0: ('cpx', 'imm'), 0xE4: ('cpx', 'dp'), 0xEC: ('cpx', 'abs'),
    0xC0: ('cpy', 'imm'), 0xC4: ('cpy', 'dp'), 0xCC: ('cpy', 'abs'),
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
})


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
        self.cycles = []

    def regs(self):
        return {r: getattr(self, r) for r in REGS}

    # ---- memoria e cicli di bus ----
    def load(self, addr, kind):
        if addr not in self.mem:
            self.mem[addr] = self.initial[addr] = self.new_byte(kind) & 0xFF
        return self.mem[addr]

    def read(self, addr, cycle=1, kind='data'):
        addr &= 0xFFFFFF
        value = self.load(addr, kind)
        self.cycles.append((cycle, addr, value))
        return value

    def write(self, addr, value):
        addr &= 0xFFFFFF
        self.mem[addr] = value & 0xFF
        self.cycles.append((5, addr, value & 0xFF))

    def io(self, addr):
        """ciclo interno: l'indirizzo e' sul bus, la memoria non viene usata"""
        self.cycles.append((0, addr & 0xFFFFFF, None))

    def code_address(self, back=0):
        return (self.pbr << 16) | ((self.pc - back) & 0xFFFF)

    def fetch(self, count=1, cycle=2):
        value = 0
        for i in range(count):
            value |= self.read(self.code_address(), cycle, 'code') << (8 * i)
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

    # direct page: indirizzo nel banco 0
    def old_wrap(self):
        """in emulazione con D allineato alla pagina, i modi del 6502 restano nella pagina"""
        return bool(self.e) and (self.d & 0xFF) == 0

    def dp_address(self, offset, index=0):
        if self.old_wrap():
            return (self.d & 0xFF00) | ((offset + index) & 0xFF)
        return (self.d + offset + index) & 0xFFFF

    def direct_offset(self):
        offset = self.fetch()
        if self.d & 0xFF:  # un ciclo in piu' per sommare D quando non e' allineato
            self.io(self.code_address(1))
        return offset

    def pointer(self, base, count, wrap=False):
        value = 0
        for i in range(count):
            addr = (base & 0xFF00) | ((base + i) & 0xFF) if wrap else (base + i) & 0xFFFF
            value |= self.read(addr) << (8 * i)
        return value

    def indexed(self, base, index, store):
        """ciclo in piu' per correggere il byte alto: sempre nelle scritture e con indici a 16 bit,
        altrimenti solo se si cambia pagina"""
        low = (base & 0xFF) + (index & 0xFF)
        if store or not self.x8() or low > 0xFF:
            self.io((base & 0xFFFF00) | (low & 0xFF))
        return (base + index) & 0xFFFFFF

    def effective(self, mode, store=False):
        """restituisce (indirizzo, True se il secondo byte resta nel banco 0)"""
        if mode == 'abs':
            return (self.dbr << 16) | self.fetch(2), False
        if mode in ('absx', 'absy'):
            base = (self.dbr << 16) | self.fetch(2)
            return self.indexed(base, self.x if mode == 'absx' else self.y, store), False
        if mode == 'long':
            return self.fetch(3), False
        if mode == 'longx':
            return (self.fetch(3) + self.x) & 0xFFFFFF, False
        if mode == 'sr':
            offset = self.fetch()
            self.io(self.code_address(1))
            return (self.s + offset) & 0xFFFF, True
        if mode == 'sriy':
            offset = self.fetch()
            self.io(self.code_address(1))
            base = (self.s + offset) & 0xFFFF
            low = self.pointer(base, 2)
            self.io((base + 1) & 0xFFFF)
            return (((self.dbr << 16) | low) + self.y) & 0xFFFFFF, False
        offset = self.direct_offset()
        if mode == 'dp':
            return self.dp_address(offset), True
        if mode in ('dpx', 'dpy'):
            self.io(self.code_address(1))
            return self.dp_address(offset, self.x if mode == 'dpx' else self.y), True
        if mode == 'dpi':
            return (self.dbr << 16) | self.pointer(self.dp_address(offset), 2, self.old_wrap()), False
        if mode == 'dpxi':
            self.io(self.code_address(1))
            low = self.pointer(self.dp_address(offset, self.x), 2, self.old_wrap())
            return (self.dbr << 16) | low, False
        if mode == 'dpiy':
            base = (self.dbr << 16) | self.pointer(self.dp_address(offset), 2, self.old_wrap())
            return self.indexed(base, self.y, store), False
        if mode in ('dpil', 'dpily'):
            base = self.pointer((self.d + offset) & 0xFFFF, 3)
            return (base + (self.y if mode == 'dpily' else 0)) & 0xFFFFFF, False
        raise ValueError(mode)

    @staticmethod
    def second(ea, bank0):
        return (ea + 1) & (0xFFFF if bank0 else 0xFFFFFF)

    def operand(self, mode, w8):
        if mode == 'imm':
            return self.fetch(1 if w8 else 2)
        ea, bank0 = self.effective(mode)
        value = self.read(ea)
        if not w8:
            value |= self.read(self.second(ea, bank0)) << 8
        return value

    def store(self, mode, value, w8):
        ea, bank0 = self.effective(mode, True)
        self.write(ea, value)
        if not w8:
            self.write(self.second(ea, bank0), value >> 8)

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
        op = self.fetch(1, 3)
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

    def compare(self, reg, mode, w8):
        value = self.operand(mode, w8)
        mask = 0xFF if w8 else 0xFFFF
        left = reg & mask
        self.setf(C, left >= value)
        self.nz((left - value) & mask, w8)

    def op_cmp(self, mode):
        self.compare(self.a, mode, self.m8())

    def op_cpx(self, mode):
        self.compare(self.x, mode, self.x8())

    def op_cpy(self, mode):
        self.compare(self.y, mode, self.x8())

    def op_stz(self, mode):
        self.store(mode, 0, self.m8())

    def op_and_(self, mode):
        self.set_a(self.a & self.operand(mode, self.m8()))

    def op_ora(self, mode):
        mask = 0xFF if self.m8() else 0xFFFF
        self.set_a((self.a & mask) | self.operand(mode, self.m8()))

    def op_eor(self, mode):
        mask = 0xFF if self.m8() else 0xFFFF
        self.set_a((self.a & mask) ^ self.operand(mode, self.m8()))

    def op_step(self, arg):
        self.io(self.code_address())
        reg, delta = arg
        if reg == 'a':
            self.set_a(self.a + delta)
        else:
            self.set_index(reg, getattr(self, reg) + delta)

    def op_to_index(self, reg):
        self.io(self.code_address())
        self.set_index(reg, self.a)

    def op_to_acc(self, reg):
        self.io(self.code_address())
        self.set_a(getattr(self, reg))

    def op_flag(self, arg):
        self.io(self.code_address())
        self.setf(*arg)

    def op_xce(self, _):
        self.io(self.code_address())
        carry = self.p & C
        self.setf(C, self.e)
        self.e = 1 if carry else 0
        if self.e:
            self.s = 0x0100 | (self.s & 0xFF)
        self.width_rules()

    def op_rep(self, _):
        mask = self.fetch()
        self.io(self.code_address(1))
        self.p &= ~mask & 0xFF
        self.width_rules()

    def op_sep(self, _):
        mask = self.fetch()
        self.io(self.code_address(1))
        self.p |= mask
        self.width_rules()

    def op_branch(self, cond):
        offset = self.fetch()
        if cond is None or bool(self.p & cond[0]) == cond[1]:
            target = (self.pc + (offset - 0x100 if offset & 0x80 else offset)) & 0xFFFF
            self.io(self.code_address(1))
            if self.e and (target >> 8) != (self.pc >> 8):  # cambio pagina in emulazione
                self.io(self.code_address(1))
            self.pc = target

    def op_jmp(self, _):
        self.pc = self.fetch(2)

    def op_jml(self, _):
        target = self.fetch(3)
        self.pc, self.pbr = target & 0xFFFF, target >> 16

    def op_jsr(self, _):
        target = self.fetch(2)
        back = (self.pc - 1) & 0xFFFF
        self.io(self.code_address(1))
        self.push(back >> 8)
        self.push(back)
        self.pc = target

    def op_rts(self, _):
        self.io(self.code_address())
        self.io(self.code_address())
        lo = self.pull()
        hi = self.pull()
        self.io(self.s)
        self.pc = (((hi << 8) | lo) + 1) & 0xFFFF

    def op_pha(self, _):
        self.io(self.code_address())
        if not self.m8():
            self.push(self.a >> 8)
        self.push(self.a)

    def op_pla(self, _):
        self.io(self.code_address())
        self.io(self.code_address())
        value = self.pull()
        if not self.m8():
            value |= self.pull() << 8
        self.set_a(value)

    def op_nop(self, _):
        self.io(self.code_address())

    def op_wdm(self, _):
        # il secondo byte viene saltato: il chip non lo legge come dato valido
        self.io(self.code_address())
        self.pc = (self.pc + 1) & 0xFFFF
