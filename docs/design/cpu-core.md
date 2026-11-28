# CPU core C2: internal structure (design)

Status: approved by the owner on 2026-11-27, with option A of section 1 and the proposals of section 9.3. Date: 2026-11-27. Step: C2a of `docs/progress/cpu.md`.
An Opus agent wrote it. The main session reviewed it (section 10).
Work orders 1-8 are done (2026-11-27). Deviations: `c816_decode` has the extra output `seq_wdmx`.
The own vectors got cycle counts after work order 9 (approved by the owner), so the cycle faults exist now.
Work order 8 kept two pass lists. Work order 9 (approved by the owner) deleted the old core, the
`CORE` variable, and the names with `_c816`. The text below keeps the plan as it was approved.
Scope: the new 65C816 core that replaces `rtl/cpu65816x.v`. Nothing in this document is implemented.

## 0. Facts and assumptions

**Verified in the public vectors** (SingleStepTests/65816, `v1/`, read-only, Python with `-I`):

- A throwaway cycle model (§5.3) ran on **all 1,060,000 vectors** of the 53 opcodes. It predicted the cycle count.
  For **every cycle**, it also predicted the address and the kind (opcode, program, data read, data write, internal). There were 0 differences. This includes the addresses of the internal (IO) cycles.
- Decimal mode adds no cycle: `69.n`, `6d.n`, `e9.n` have the same counts with D = 1 and D = 0.
- In emulation mode, the final S always has the high byte 01, and the low byte wraps in page 1. Examples: `20 e 210`, `60 e 121`, `48 e 64`, `68 e 484`.
- After `XCE` from emulation to native, S keeps the high byte 01, also when the vector started with another value (`fb e 1`).
- In native mode, the stack does not wrap in a page (`68 n 257`).
- The data value is `null` in IO cycles. The second cycle of `WDM` is an IO cycle, not a program read (`42.n`, `42.e`).
- The E, M, X columns of the cycle flags show the values at the start of the instruction. This is also true in the last cycle of `REP`, `SEP`, `XCE`.
- VPB and MLB are never set in 95,825 sampled cycles.

**Assumed (not verified):**

- A 16-bit data access at `$xxFFFF` continues in the next bank (24-bit increment). Only one vector shows it (`bd n 353`).
- IO cycles do not cause a bus read on the SNES. This must be checked in phase F3 with SNES documents.
- The cycle rules of §5.4 for modes that are not in the 53 opcodes (C3, C4, C5) come from general 65C816 knowledge. Check each one with the vectors when its opcode is added.

## 1. Key decision: FPGA clocks for each CPU cycle

| Criterion | A: 2 clocks, fixed | B: 1 clock, address look-ahead | C: variable (read 2, write and IO 1) | D: 4 clocks, fixed |
|---|---|---|---|---|
| CPU cycles at a 50 MHz FPGA clock (estimate) | 25 M/s | 50 M/s at most; the long path reduces Fmax (estimate 30-40 MHz) | about 30-40 M/s | 12.5 M/s |
| Memory interface | as today: address and `rd` in phase 0, registered data in phase 1 | the next address comes from the data read in the same clock: BRAM output to adder to BRAM input | as today | as A, more slack |
| DMA and `halt` | stop at any cycle boundary (phase 0) | `halt` must be known one clock early | stop at a cycle boundary | as A |
| Test bench | counts `cyc_end` pulses | the memory model changes | counts `cyc_end` pulses | as A |
| Later `bus_wait` (F3) | stretches phase 1; a 6/8/12 master-clock cycle is a simple counter | must act on the look-ahead address | the base length depends on the cycle kind | as A |
| Prefetch, SDRAM (C7, F4) | a unit answers OPF/PRG cycles; SDRAM holds `bus_wait` | difficult | possible, uneven timing | as A |

The SNES needs at most 3.58 M cycles/s. Option A gives about 7 times this rate (estimate).
With SDRAM, the memory latency dominates, so option B loses most of its gain.

**Recommendation: option A.** One CPU cycle is two FPGA clocks, phase 0 and phase 1. `bus_wait` can stretch phase 1. `halt` can hold phase 0.

## 2. Block structure

### 2.1 Files (new folder `rtl/cpu/`)

| File | Module | Responsibility |
|---|---|---|
| `rtl/cpu/c816_core.v` | `c816_core` | top of the core; latches IR, AL, AH, BA, DL, DH; bus outputs; execute (commit) logic |
| `rtl/cpu/c816_seq.v` | `c816_seq` | step counter `t`, phase `ph`, last and skip logic, `halt`, `bus_wait`, reset entry, `dbg_illegal` |
| `rtl/cpu/c816_decode.v` | `c816_decode` | **generated**: opcode (9-bit IR) to decode fields |
| `rtl/cpu/c816_ucode.v` | `c816_ucode` | **generated**: (sequence, step) to the cycle descriptor |
| `rtl/cpu/c816_regs.v` | `c816_regs` | A X Y S D PC PBR DBR P E, write ports, width and emulation rules |
| `rtl/cpu/c816_alu.v` | `c816_alu` | the one ALU, combinational |
| `rtl/cpu/c816_addr.v` | `c816_addr` | address of each cycle, effective address, page carry, branch target |
| `rtl/cpu/c816_ext.v` | `c816_ext` | `WDM` extensions (MUL, DIV, MAC, MACRD, MACCLR), active only with `ext_en = 1` |
| `rtl/cpu/c816_tables.txt` | - | single source of the two generated files |
| `sim/gen_c816_tables.py` | - | generator and checker of the tables |

Add the `.v` files to `rtl/files.f` in WO3. Write no word that ends in `.v` in the comments of that file.

### 2.2 Ports of `c816_core`

| Port | Dir | Width | Meaning |
|---|---|---|---|
| `clk`, `rst` | in | 1 | clock; synchronous reset |
| `halt` | in | 1 | 1 = do not start the next cycle (DMA). Acts in phase 0 |
| `bus_wait` | in | 1 | 1 = stretch phase 1. Tie to 0 in C2 and in all compatible CPU tests |
| `ext_en` | in | 1 | 1 = `WDM` runs the extensions |
| `nmi`, `irq` | in | 1 | reserved for C5; ignored in C2; tie to 0 |
| `din` | in | 8 | read data, valid in phase 1 |
| `addr` | out | 24 | address of the cycle, stable in both phases |
| `rd`, `wr` | out | 1 | strobes, phase 0 only, one clock each |
| `wdata` | out | 8 | write data, valid with `wr` |
| `vda`, `vpa` | out | 1 | cycle kind as on the 65C816 (both 0 = IO cycle) |
| `sync` | out | 1 | 1 during the opcode fetch cycle (`t = 0`) |
| `cyc_end` | out | 1 | 1 in the clock that ends a CPU cycle (`ph = 1` and `bus_wait = 0`) |
| `dbg_illegal` | out | 1 | sticky; 1 after the core decoded an unimplemented opcode |
| `dbg_pc`, `dbg_a`, `dbg_x`, `dbg_y` | out | 16 | as today |

Bus protocol (replaces "Bus protocol" in `docs/ARCHITECTURE.md` at the switch):

| Clock | `addr` | `rd` / `wr` | `din` |
|---|---|---|---|
| phase 0 | valid | one pulse if the cycle is a read or a write and `halt = 0` | - |
| phase 1 (repeated while `bus_wait = 1`) | same value | 0 | the core captures it at the edge that ends phase 1 with `bus_wait = 0` |

IO cycles drive `addr` but no strobe. While `bus_wait = 1`, the system must hold `din` stable. In F3, `s_cpu_5a22` can latch `bus_rdata` in the first clock after `rd`.

### 2.3 Internal port lists

```
c816_seq   (input clk, rst, halt, bus_wait, input [2:0] bus, input [2:0] last, input [2:0] skip,
            input imp, input w8, input taken, input br_cross, input xcarry, input is_store, input e,
            output reg [3:0] t, output reg ph, output reg illegal,
            output cyc_end, output commit, output skip1, output rd, output wr, output sync);
c816_decode(input [8:0] ir, output reg [4:0] seq, output reg [4:0] op, output reg [3:0] ea,
            output reg [2:0] w, output reg [2:0] src, output reg [2:0] dst, output reg [3:0] arg,
            output reg imp, output [4:0] seq_wdmx);
c816_ucode (input [4:0] seq, input [3:0] t, output reg [2:0] bus, output reg [3:0] asel,
            output reg [2:0] cap, output reg pcinc, output reg [1:0] sop, output reg [2:0] wsel,
            output reg [2:0] last, output reg [2:0] skip, output reg [2:0] pcop, output reg [1:0] hold);
c816_regs  (input clk, rst,
            input wr_en, input [2:0] wr_sel, input [15:0] wr_val, input wr_w16,
            input ext_we_a, input ext_we_y, input [15:0] ext_a, input [15:0] ext_y,
            input [3:0] f_we, input f_n, input f_v, input f_z, input f_c,   // mask order N V Z C
            input p_we, input [7:0] p_val, input e_we, input e_val,
            input pc_we, input [15:0] pc_val, input pbr_we, input [7:0] pbr_val,
            input s_inc, input s_dec,
            output reg [15:0] a, x, y, s, d, pc, output reg [7:0] pbr, dbr, p, output reg e);
c816_alu   (input [3:0] op, input [15:0] a, input [15:0] b, input ci, input w16, input dec,
            output reg [15:0] r, output reg n, output reg v, output reg z, output reg c);
c816_addr  (input [3:0] asel, input [3:0] ea, input [15:0] pc, input [7:0] pbr, input [7:0] dbr,
            input [15:0] s, input [15:0] x, input e, input [7:0] al, input [7:0] ah, input [7:0] ba,
            input [7:0] vec, output reg [23:0] addr, output xcarry, output br_cross,
            output [15:0] br_target, output [15:0] pc_m1);
c816_ext   (input clk, rst, input go, input [7:0] sub, input [15:0] a, input [15:0] x,
            output we_a, output we_y, output [15:0] a_out, output [15:0] y_out,
            output f_we, output f_n, output f_z, output fv_we, output f_v, output busy);
```

Rules for all modules (subset of `sim/vsim.py`): one clock, `always @(posedge clk)` and `always @*` only. Use no `function`, `task`, `generate`, `for`, `casez`, `signed`, or instance parameters. Use no reduction operators (`|x`, `&x`); write `x != 0`. Use no indexed part-select (`+:`). Connect each instance output to a plain wire name, not to a slice or a concatenation. Give every `always @*` output a default value first.

### 2.4 Changes to `s_cpu_5a22.v` and the top (WO8 only)

- Replace the `cpu65816x` instance with `c816_core`. Connect `bus_wait`, `nmi`, `irq` to `1'b0`.
- Keep `halt = dma_pending | dma_active`. The meaning changes: the CPU stops at the next cycle boundary, also inside an instruction. `dma_pending` rises after the write to `$420B` in phase 0. Thus the CPU completes phase 1 of that write and then stops.
- Add the output `dbg_illegal` to `s_cpu_5a22` and `snes_plus_top`. Make `sim/run_tests.py` and `tb/tb_snes_plus.v` fail when it is 1.
- Make no other change to the bus, the DMA, or the memory map.

## 3. Datapath

### 3.1 Registers (`c816_regs`)

| Register | Width | Reset value | Rule applied to the next value at every clock |
|---|---|---|---|
| A | 16 | 0 | an 8-bit write (`wr_w16 = 0`) changes only A[7:0] |
| X, Y | 16 | 0 | if P.X = 1, then X[15:8] = Y[15:8] = 0 |
| S | 16 | `$01FF` | if E = 1, then S[15:8] = `$01`; `s_inc`/`s_dec` change only S[7:0] when E = 1 |
| D | 16 | 0 | none (C3 uses it) |
| PC | 16 | from the reset vector | wraps in the bank |
| PBR, DBR | 8 | 0 | none |
| P | 8 (N V M X D I Z C) | `$34` | if E = 1, then P.M = P.X = 1 |
| E | 1 | 1 | - |

Apply the rules to the next value, after all write ports. Thus the test bench can load any S with E = 1: the first clock edge sets S[15:8] to `$01`, as the vectors expect.
Priority when two ports write the same register in one clock: `wr_en`, then `ext_we_*`, then `s_inc`/`s_dec`.

### 3.2 ALU (`c816_alu`)

| `op` | Code | Result | Carry |
|---|---|---|---|
| PASSB | 0 | B | - |
| PASSA | 1 | A | - |
| ADD | 2 | A + B + ci | carry out of bit 7 or 15 |
| SUB | 3 | A + ~B + ci | same |
| CMP | 4 | A + ~B + 1 | same |
| AND, ORA, EOR | 5, 6, 7 | logic | - |
| INC, DEC | 8, 9 | A + 1, A - 1 | - |
| 10-15 | reserved | ASL, LSR, ROL, ROR, BIT, TSB/TRB (C4) | |

`w16 = 0` uses bits 7:0. Then N = r[7], Z = (r[7:0] == 0), and V comes from bit 7. `r[15:8]` is "don't care"; the register rules keep the high byte. V for ADD is `~(a^b) & (a^r)` at the sign bit; for SUB it is `(a^b) & (a^r)`. Input `dec` (P.D) is reserved for C5; ignore it in C2.

### 3.3 Address unit (`c816_addr`)

Effective address `EA` (decode field `ea`): ABS (1) = `{DBR, AH, AL}`; ABSX (2) = `{DBR, AH, AL} + X` (24-bit); LONG (3) = `{BA, AH, AL}`.
`xcarry` = carry out of `AL + X[7:0]`. `br_target = PC + sign_extend(AL)`. `br_cross = (br_target[15:8] != PC[15:8])`.

| `asel` | Code | Address |
|---|---|---|
| PC | 0 | `{PBR, PC}` |
| PCD | 1 | `{PBR, PC - 1}` (16-bit wrap) |
| EA | 2 | EA |
| EA1 | 3 | EA + 1 (24-bit) |
| DUMX | 4 | `{DBR, AH, (AL + X[7:0]) mod 256}` |
| S | 5 | E ? `{$00, $01, S[7:0]}` : `{$00, S}` |
| S1 | 6 | E ? `{$00, $01, S[7:0] + 1}` : `{$00, S + 1}` |
| VEC | 7 | `{$00, $FF, vec}`; `vec = $FC` in C2 |
| VEC1 | 8 | VEC + 1 |
| 9-15 | reserved | DP, DP1, wide stack S and S+1 for PEA/PEI/JSL/RTL, block move (C3, C4) |

### 3.4 Width

`w8` is the operand width: `w` = M (0) gives P.M; X (1) gives P.X; B8 (2) gives 1; W16 (3) gives 0. Codes 4-7 are reserved (32-bit mode, C7). In emulation mode, P.M = P.X = 1, so all M and X operands are 8-bit. ALU `w16 = !w8`. The register write uses `wr_w16 = !w8`.

### 3.5 Bypass

The core reads the latches through a bypass: `al_by = (capture into AL now) ? din : AL`. The same applies to AH, BA, DL, DH. The execute logic and the PC logic use the bypass values. The address unit uses only the latch values.

## 4. Decode

### 4.1 Recommendation

Generate both tables from one text file with a Python script. Commit the generated `.v` files with the header `// generated by sim/gen_c816_tables.py: do not edit`.
Reasons: 256 opcodes and about 40 sequences need many fields. A script can check them (unique opcodes, valid names, a reachable end in each sequence). Committed output needs no Python step in yosys, iverilog, vsim, or the CI.
`make tables` writes the files. `make tables-check` regenerates them into `build/` and compares them with `cmp`. Add `tables-check` to `make check` and to the CI.

### 4.2 Source format (`rtl/cpu/c816_tables.txt`)

- `#` starts a comment. Fields are separated by spaces. `-` is code 0 (for `w`, `-` is B8).
- `[seq NAME]` starts a sequence. The generator numbers the sequences in file order, from 0. Make `IMP` the first.
- A step line is `t bus asel cap pc sop wsel last skip pcop hold`. Step 0 is implicit and the same for all sequences: `OPF PC IR INC - - - - - -`.
- `[ops]` starts the decode rows: `opc mnem seq op ea w src dst arg`. `opc` is 9-bit hex: `000`-`0FF` are opcodes, `100`-`1FF` are pseudo-opcodes.
- An opcode without a row decodes to `seq IMP, op NOP, imp 0`. Every row gives `imp = 1`.

Generated shape (vsim-compatible):

```
always @* begin
  bus = 3'd0; asel = 4'd0; cap = 3'd0; pcinc = 1'b0; sop = 2'd0; wsel = 3'd0;
  last = 3'd1; skip = 3'd0; pcop = 3'd0; hold = 2'd0;     // default: IO, last
  if (t == 4'd0) begin bus = 3'd1; cap = 3'd6; pcinc = 1'b1; last = 3'd0; end
  else case ({seq, t})
    9'h031: begin bus = 3'd2; cap = 3'd4; pcinc = 1'b1; last = 3'd2; end
    ...
  endcase
end
```

### 4.3 Field encodings

| Field | Codes |
|---|---|
| `bus` (3) | 0 IO, 1 OPF, 2 PRG, 3 DAT (read, or write if `op = ST`), 4 DRD, 5 DWR |
| `cap` (3) | 0 none, 1 AL, 2 AH, 3 BA, 4 DL, 5 DH, 6 IR |
| `pc` (1) | INC = PC + 1 at the end of the cycle |
| `sop` (2) | 0 none, 1 INC, 2 DEC (S at the end of the cycle) |
| `wsel` (3) | 0 RLO = src[7:0], 1 RHI = src[15:8], 2 PCDL, 3 PCDH (bytes of PC - 1); 4-7 reserved (P, PBR, DBR, DL) |
| `last` (3) | 0 NO, 1 ALW, 2 W8 (last if `w8`), 3 NTK (last if branch not taken), 4 NEC (last if not (E and `br_cross`)); 5-7 reserved |
| `skip` (3) | skip step t+1: 0 NO, 1 XNC (not a store, P.X = 1, no `xcarry`), 2 W8; 3-7 reserved (DL0 for C3) |
| `pcop` (3) | 0 none, 1 ABS (PC = `{ah_by, al_by}`), 2 LONG (also PBR = `ba_by`), 3 BRL (PC = `br_target` if this step is last), 4 BR (PC = `br_target`), 5 RTS (PC = `{AH, AL} + 1`); 6-7 reserved (RTL, block-move rewind) |
| `hold` (2) | 0 none; 1-3 reserved (C6 `ext busy`, C5 WAI, C5 STP) |
| `op` (5) | 0 NOP, 1 LD, 2 ST, 3 TR, 4 ADC, 5 SBC, 6 CMP, 7 AND, 8 ORA, 9 EOR, 10 INC, 11 DEC, 12 FLG, 13 REP, 14 SEP, 15 XCE, 16 BR, 17 BRA, 18 WDM; 19-31 reserved |
| `ea` (4) | 0 none, 1 ABS, 2 ABSX, 3 LONG; 4-15 reserved (C3) |
| `w` (3) | 0 M, 1 X, 2 B8, 3 W16; 4-7 reserved |
| `src`, `dst` (3) | 0 none, 1 A, 2 X, 3 Y, 4 S, 5 D; 6-7 reserved |
| `arg` (4) | FLG and BR: bit 3 = value, bits 2:0 = P bit (7 N, 6 V, 5 M, 4 X, 3 D, 2 I, 1 Z, 0 C) |

`pcop` has priority over `pc INC` in the same step.

## 5. Sequencer

### 5.1 Behavior

```
w8       = (w==M) ? p[5] : (w==X) ? p[4] : (w != W16);
taken    = (op==BRA) | (p[arg[2:0]] == arg[3]);
is_last  = last==ALW | (last==W8 & w8) | (last==NTK & !taken) | (last==NEC & !(e & br_cross));
skip1    = (skip==XNC & op!=ST & p[4] & !xcarry) | (skip==W8 & w8);
reads    = bus==OPF | bus==PRG | bus==DRD | (bus==DAT & op!=ST);
writes   = bus==DWR | (bus==DAT & op==ST);
rd = !ph & !halt & reads;   wr = !ph & !halt & writes;   sync = (t==0);
vda = bus==OPF | bus==DAT | bus==DRD | bus==DWR;   vpa = bus==OPF | bus==PRG;
cyc_end = ph & !bus_wait;   commit = cyc_end & is_last;

rst:               t <= 1; ph <= 0; ir <= 9'h100; illegal <= 0;    // pseudo-op RST
ph==0 & !halt:     ph <= 1;
cyc_end:           ph <= 0;
                   if (reads & cap!=0) latch[cap] <= din;          // IR gets {1'b0, din}
                   if (t==1 & !imp) illegal <= 1;
                   PC, PBR, S changes of the step (pc, pcop, sop);
                   if (commit) execute (5.2);
                   t <= is_last ? 0 : t + 1 + skip1;
```

The core selects the sequence: `seq_eff = (ir == 9'h042 && ext_en) ? WDMX : seq`. An unimplemented opcode runs as a 2-cycle NOP and sets `dbg_illegal`.

### 5.2 Execute at `commit`

| `op` | ALU | Register write | Flags |
|---|---|---|---|
| LD | PASSB, B = `{dh_by, dl_by}` | `dst` | N Z |
| TR | PASSA, A = `src` | `dst` | N Z |
| ADC, SBC | ADD, SUB, `ci` = P.C | A | N V Z C |
| CMP | CMP | none | N Z C |
| AND, ORA, EOR | logic | A | N Z |
| INC, DEC | INC, DEC, A = `src` | `dst` | N Z |
| FLG | - | P[arg[2:0]] = arg[3] | - |
| REP / SEP | - | P = P & ~DL / P \| DL | - |
| XCE | - | C = E, E = C | - |
| WDM | `c816_ext`, `go = commit & ext_en` | A and Y by sub-opcode DL | as the old core |
| ST, NOP, BR, BRA | - | none | - |

Copy the `WDM` semantics of `rtl/cpu65816x.v` lines 373-391 into `c816_ext`. `busy` is 0 in C2.

### 5.3 Sequence table for the 53 opcodes (content of `c816_tables.txt`)

```
#   t bus asel cap pc  sop wsel last skip pcop hold
[seq IMP]                       # implied: 2 cycles
    1 IO  PC   -   -   -   -    ALW  -    -    -
[seq WDM]                       # WDM, ext_en = 0: 2 cycles, the second byte is skipped
    1 IO  PC   -   INC -   -    ALW  -    -    -
[seq WDMX]                      # WDM, ext_en = 1: the sub-opcode is a program byte
    1 PRG PC   DL  INC -   -    ALW  -    -    -
[seq IMM]                       # immediate: 2 (8-bit) or 3 (16-bit)
    1 PRG PC   DL  INC -   -    W8   -    -    -
    2 PRG PC   DH  INC -   -    ALW  -    -    -
[seq IMM8P]                     # REP, SEP: 3
    1 PRG PC   DL  INC -   -    -    -    -    -
    2 IO  PCD  -   -   -   -    ALW  -    -    -
[seq ABS]                       # 4 or 5
    1 PRG PC   AL  INC -   -    -    -    -    -
    2 PRG PC   AH  INC -   -    -    -    -    -
    3 DAT EA   DL  -   -   RLO  W8   -    -    -
    4 DAT EA1  DH  -   -   RHI  ALW  -    -    -
[seq ABSX]                      # load 4-6, store 5-6
    1 PRG PC   AL  INC -   -    -    -    -    -
    2 PRG PC   AH  INC -   -    -    XNC  -    -
    3 IO  DUMX -   -   -   -    -    -    -    -
    4 DAT EA   DL  -   -   RLO  W8   -    -    -
    5 DAT EA1  DH  -   -   RHI  ALW  -    -    -
[seq LONG]                      # 5 or 6
    1 PRG PC   AL  INC -   -    -    -    -    -
    2 PRG PC   AH  INC -   -    -    -    -    -
    3 PRG PC   BA  INC -   -    -    -    -    -
    4 DAT EA   DL  -   -   RLO  W8   -    -    -
    5 DAT EA1  DH  -   -   RHI  ALW  -    -    -
[seq JMP]                       # 3
    1 PRG PC   AL  INC -   -    -    -    -    -
    2 PRG PC   AH  INC -   -    ALW  -    ABS  -
[seq JML]                       # 4
    1 PRG PC   AL  INC -   -    -    -    -    -
    2 PRG PC   AH  INC -   -    -    -    -    -
    3 PRG PC   BA  INC -   -    ALW  -    LONG -
[seq BR]                        # 2 not taken, 3 taken, 4 taken with E = 1 and page cross
    1 PRG PC   AL  INC -   -    NTK  -    -    -
    2 IO  PCD  -   -   -   -    NEC  -    BRL  -
    3 IO  PCD  -   -   -   -    ALW  -    BR   -
[seq JSR]                       # 6
    1 PRG PC   AL  INC -   -    -    -    -    -
    2 PRG PC   AH  INC -   -    -    -    -    -
    3 IO  PCD  -   -   -   -    -    -    -    -
    4 DWR S    -   -   DEC PCDH -    -    -    -
    5 DWR S    -   -   DEC PCDL ALW  -    ABS  -
[seq RTS]                       # 6
    1 IO  PC   -   -   -   -    -    -    -    -
    2 IO  PC   -   -   -   -    -    -    -    -
    3 DRD S1   AL  -   INC -    -    -    -    -
    4 DRD S1   AH  -   INC -    -    -    -    -
    5 IO  S    -   -   -   -    ALW  -    RTS  -
[seq PUSH]                      # PHA: 3 or 4, high byte first
    1 IO  PC   -   -   -   -    -    W8   -    -
    2 DWR S    -   -   DEC RHI  -    -    -    -
    3 DWR S    -   -   DEC RLO  ALW  -    -    -
[seq PULL]                      # PLA: 4 or 5, low byte first
    1 IO  PC   -   -   -   -    -    -    -    -
    2 IO  PC   -   -   -   -    -    -    -    -
    3 DRD S1   DL  -   INC -    W8   -    -    -
    4 DRD S1   DH  -   INC -    ALW  -    -    -
[seq RST]                       # pseudo-op 100: simplified reset (C5 makes it exact)
    1 DRD VEC  AL  -   -   -    -    -    -    -
    2 DRD VEC1 AH  -   -   -    ALW  -    ABS  -

[ops]
# opc mnem seq   op  ea   w   src dst arg
018 CLC  IMP   FLG  -    -   -   -   0
038 SEC  IMP   FLG  -    -   -   -   8
058 CLI  IMP   FLG  -    -   -   -   2
078 SEI  IMP   FLG  -    -   -   -   A
01A INC  IMP   INC  -    M   A   A   0
03A DEC  IMP   DEC  -    M   A   A   0
0E8 INX  IMP   INC  -    X   X   X   0
0CA DEX  IMP   DEC  -    X   X   X   0
0C8 INY  IMP   INC  -    X   Y   Y   0
088 DEY  IMP   DEC  -    X   Y   Y   0
0AA TAX  IMP   TR   -    X   A   X   0
0A8 TAY  IMP   TR   -    X   A   Y   0
08A TXA  IMP   TR   -    M   X   A   0
098 TYA  IMP   TR   -    M   Y   A   0
0EA NOP  IMP   NOP  -    -   -   -   0
0FB XCE  IMP   XCE  -    -   -   -   0
042 WDM  WDM   WDM  -    W16 A   A   0
0C2 REP  IMM8P REP  -    -   -   -   0
0E2 SEP  IMM8P SEP  -    -   -   -   0
0A9 LDA  IMM   LD   -    M   -   A   0
0A2 LDX  IMM   LD   -    X   -   X   0
0A0 LDY  IMM   LD   -    X   -   Y   0
069 ADC  IMM   ADC  -    M   A   A   0
0E9 SBC  IMM   SBC  -    M   A   A   0
0C9 CMP  IMM   CMP  -    M   A   -   0
029 AND  IMM   AND  -    M   A   A   0
009 ORA  IMM   ORA  -    M   A   A   0
049 EOR  IMM   EOR  -    M   A   A   0
0AD LDA  ABS   LD   ABS  M   -   A   0
0AE LDX  ABS   LD   ABS  X   -   X   0
0AC LDY  ABS   LD   ABS  X   -   Y   0
06D ADC  ABS   ADC  ABS  M   A   A   0
0CD CMP  ABS   CMP  ABS  M   A   -   0
08D STA  ABS   ST   ABS  M   A   -   0
08E STX  ABS   ST   ABS  X   X   -   0
08C STY  ABS   ST   ABS  X   Y   -   0
0BD LDA  ABSX  LD   ABSX M   -   A   0
09D STA  ABSX  ST   ABSX M   A   -   0
0AF LDA  LONG  LD   LONG M   -   A   0
08F STA  LONG  ST   LONG M   A   -   0
04C JMP  JMP   NOP  -    -   -   -   0
05C JML  JML   NOP  -    -   -   -   0
020 JSR  JSR   NOP  -    -   -   -   0
060 RTS  RTS   NOP  -    -   -   -   0
048 PHA  PUSH  NOP  -    M   A   -   0
068 PLA  PULL  LD   -    M   -   A   0
080 BRA  BR    BRA  -    -   -   -   0
0D0 BNE  BR    BR   -    -   -   -   1
0F0 BEQ  BR    BR   -    -   -   -   9
090 BCC  BR    BR   -    -   -   -   0
0B0 BCS  BR    BR   -    -   -   -   8
010 BPL  BR    BR   -    -   -   -   7
030 BMI  BR    BR   -    -   -   -   F
100 RST  RST   NOP  -    -   -   -   0
```

The cycle model that matched all 1,060,000 vectors uses the same rules as this table. Notes on the checked cycles:

| Case | Verified sequence (vector) |
|---|---|
| Implied, XCE, WDM | opcode; IO at P+1 (`42.n`, `ea.n`, `fb.n`) |
| REP/SEP | opcode; operand at P+1; IO at P+1 (`c2 n 2`) |
| Immediate | 1 extra program byte for 16-bit (`a9 n 2` versus `a9 n 1`) |
| abs,X read | dummy IO at `{DBR, AH, AL+XL}` if X is 16-bit or the page crosses (`bd n 1`, `bd n 6`, `bd e 2`; none in `bd n 17`) |
| abs,X store | dummy IO always (`9d n 3`) |
| Branch | IO at P+1 if taken; a second IO at P+1 only with E = 1 and a page cross (`80 e 2`, `d0 e 8`; native cross `80 n 1` has 3 cycles) |
| JSR | IO at P+2; push PCH at S, PCL at S-1; value = P+2 (`20 n 3`) |
| RTS | IO P+1, IO P+1, read S+1, read S+2, IO S+2 (`60 n 7`) |
| PHA / PLA | high byte pushed first (`48 n 2`); low byte pulled first (`68 n 3`) |

### 5.4 Extra cycles for later steps (assumed, check with the vectors)

| Rule | Mechanism |
|---|---|
| Direct page: one IO after the operand when D[7:0] != 0 (C3) | `skip DL0` on step 1 |
| abs,Y and (dp),Y: as abs,X (C3) | same `XNC` with Y; decode field `ea` |
| Emulation, D[7:0] = 0: dp indexed wraps in the page (C3) | address unit rule for `asel` DP |
| RMW: 16-bit reads lo, hi; IO; writes hi, lo (C4) | `skip W8` on the lo read and on the IO step |
| RMW in emulation mode writes the old value in the modify cycle (C4) | sequence variant chosen by E |
| PEA, PEI, PER, JSL, RTL, PHD, PLD, PHB, PLB leave page 1 inside the instruction (C4) | wide stack `asel` codes; S[15:8] = 01 again by the register rule |
| MVN/MVP: 7 cycles per byte, repeat until A = `$FFFF` (C4) | `pcop` rewind code |

## 6. Hooks for later steps

- **Reset and interrupts (C5).** Reset already enters through the pseudo-op `100` at step 1. For NMI and IRQ, latch the request at `commit`. Then the next step 0 reads the opcode but does not store it or increment PC. It loads `ir` with a pseudo-op (`101` NMI, `102` IRQ, `103` ABORT). Write BRK and COP as normal rows. `vec` comes from the pseudo-op and E.
- **WAI, STP (C5).** Use `hold` codes 2 and 3: the step repeats IO cycles until an interrupt or a reset.
- **ABORT (optional).** It needs a copy of the registers at the start of each instruction. Leave it out unless the owner asks.
- **Decimal (C5).** Use ALU input `dec`. No cycle changes (verified).
- **Divider (C6).** `c816_ext.busy` repeats a step of `WDM DIV` (section 14).
- **Wait and SNES timing (F3).** `bus_wait` stretches phase 1. `vda`, `vpa`, and `addr` give the 5A22 what it needs to choose 6, 8, or 12 master clocks.
- **SDRAM (F4).** The memory port holds `bus_wait` until `din` is valid.
- **Prefetch, 32-bit mode (C7).** OPF and PRG cycles are explicit, so a prefetch unit can answer them. Width codes 4-7 and op codes 19-31 are free. Keep the prefetch off when `ext_en = 0`.

## 7. Test bench and coexistence

### 7.1 Vector format

Append a bus list to each line of the vector file: `nc`, then `nc` triples `kind addr value`.
`kind` bit 0 = VDA, bit 1 = VPA, bit 2 = write. `value = 100` (hex) means no value.
- `sim/cpu_sst.py convert`: add the option `--bus`. With it, write the cycles of the vector; without it, write `0`.
- `sim/cpu_vectors.py`: write `0` at the end of each line.

### 7.2 `tb/tb_cpu.v`

- Move the DUT instance, `load_state`, `state_diff`, and the end-of-instruction loop into two include files: `tb/cpu_adapt_old.vh` and `tb/cpu_adapt_c816.vh`. Select one with `ifdef C816`. Compile with `-I tb`. Only these files read internal registers.
- Extend the mask: `F_CYC = 13`, `F_BUS = 14`, `F_ILL = 15`. In `cpu_adapt_c816.vh` only, set `F_CYC` when `expcyc != 0` and the counted cycles differ. The old core counts clocks, so it never sets `F_CYC` or `F_BUS`.
- Read the bus list into arrays of 16 entries.
- `cpu_adapt_c816.vh`, `load_state`: write `dut.u_regs.{pc,s,p,a,x,y,d,dbr,pbr,e}` from the vector without changes. Write `dut.u_seq.t = 0`, `dut.u_seq.ph = 0`, `dut.u_seq.illegal = 0`, `dut.u_ext.acc = 0`. Tie `halt`, `bus_wait`, `ext_en`, `nmi`, `irq` to 0.
- Cycle count (ports only): at each negative edge, sample `cyc_end`. After the next positive edge, if the sample was 1, add one cycle. Stop when the count is above 0 and `sync = 1`.
- Bus check (only if `nc > 0`): at the negative edge of phase 0, store `rd`, `wr`, `wdata`. At the negative edge with `cyc_end = 1`, compare `vda`, `vpa`, and `addr` with entry k. Then compare the stored strobe with the kind, and `wdata` for a write. Any difference, or a count different from `nc`, sets `F_BUS`.
- Set `F_ILL` when `dbg_illegal = 1`. Compare `D` with `dut.u_regs.d`.
- Write the cycle count (not the clock count) in the result column.
- `sim/cpu_score.py`: append three names to `FIELDS` (`cicli`, `bus`, `illegale`). Add `--passlist <file>` (default `tests/cpu_pass.txt`).

### 7.3 Makefile and coexistence

- `CORE ?= old`. With `CORE=c816`, compile with `-DC816` into `build/tb_cpu_c816.vvp`. Write `build/cpu_score_c816.txt` and use `tests/cpu_pass_c816.txt`.
- Add `cpu-c816` (`$(MAKE) cpu CORE=c816`) and `tables-check` to `check`. Make the CI run the same targets.
- Add `-s tb_snes_plus` to the `iverilog` target, because the new modules are extra roots.
- `s_cpu_5a22.v` keeps the old core until WO8. The system tests do not change until then.
- `make test` parses all files of `rtl/files.f`, so it finds vsim problems in the new files early.

### 7.4 vsim

Keep `sim/vsim.py` for C2. Retire it if `make test` or `make mutation` stops working with the new core, or if `make mutation` takes more than 10 minutes in the CI. Then `make test` runs the `iverilog` target. `make mutation` writes each mutant into `build/mut/` and runs `tb_snes_plus` with iverilog.

## 8. Work orders

Each work order that changes `rtl/` or a manual source ends with a manual update (`manuals/README.md`).
Levels follow `CLAUDE.md` (Necessity N; N >= 4 uses the expensive model). "Own" = `make cpu CORE=c816`. "Public" = `make cpu-public CORE=c816 SST=../65816-test-vectors`.

| WO | Files | Change | Verification and expected result | Level |
|---|---|---|---|---|
| 1 | `sim/cpu_sst.py`, `sim/cpu_vectors.py`, `sim/cpu_score.py`, `tb/tb_cpu.v`, `tb/cpu_adapt_old.vh`, `Makefile` | §7.1-7.3 without the C816 adapter | `make cpu`: 47 of 256 opcodes, 20,845 of 21,200 vectors (unchanged). `make cpu-public SST=../65816-test-vectors SST_FLAGS=--bus`: 266,966 of 1,060,000 (unchanged) | standard, N=2 |
| 2 | `rtl/cpu/c816_tables.txt`, `sim/gen_c816_tables.py`, generated `c816_decode.v`, `c816_ucode.v`, `Makefile` | §4 and §5.3 exactly | `make tables-check` passes. `python3 sim/gen_c816_tables.py --check` exits 0. `iverilog -g2012 -o build/t.vvp` on the two files: no error. `vsim.parse_source` reads both | standard, N=3 |
| 3 | `rtl/cpu/c816_core.v`, `c816_seq.v`, `c816_regs.v`, `c816_alu.v`, `c816_addr.v` (PC, PCD only), `rtl/files.f`, `tb/cpu_adapt_c816.vh`, `tests/cpu_pass_c816.txt` | §2.2, §3, §5.1, §5.2; sequences IMP, IMM, IMM8P | Own: the 28 opcodes 09 18 1A 29 38 3A 42 49 58 69 78 88 8A 98 A0 A2 A8 A9 AA C2 C8 C9 CA E2 E8 E9 EA FB pass in n and e. Public with `SST_FLAGS=--limit 1000`: these 28 have no `cicli`; all except 69 and E9 pass. `make check` passes | expensive, N=4 (it fixes the structure) |
| 4 | `c816_addr.v`, `c816_core.v` | EA, EA1, DUMX, `xcarry`, `XNC`, `pcop` ABS and LONG | Own: AD AE AC 6D CD 8D 8E 8C BD 9D AF 8F 4C 5C also pass in n and e (42 in total) | standard, N=3 |
| 5 | `c816_addr.v`, `c816_core.v`, `c816_seq.v`, `c816_ext.v` | S, S1, VEC, `sop`, PCDH/PCDL, BRL, BR, RTS, NTK, NEC, WDMX, `dbg_illegal` | Own: 53 of 256 in both modes, 21,200 of 21,200. One added vector with opcode `$02` sets `illegale` | standard, N=3 |
| 6 | `docs/progress/cpu.md`, `docs/VERIFICATION.md`, fixes | full public run | Public with `SST_FLAGS=--bus`: 50 of 256 opcodes in both modes. Only $69, $6D, $E9 fail, only in vectors with D = 1, with no `cicli` or `bus` bit | standard, N=3; expensive if a difference stays after one attempt |
| 7 | `sim/mutation_check.py`, `Makefile` | add `--cpu`: mutate the new core text, run `tb_cpu` with own vectors, `--limit` 20; target `cpu-mutation` in `check` | 5 mutants or more, all found: SEP does not set D; S high byte not held; abs,X dummy cycle never skipped; ADC carry 0; RTS without +1 | standard, N=2 |
| 8 | `rtl/s_cpu_5a22.v`, `rtl/snes_plus_top.v`, `sim/run_tests.py`, `tb/tb_snes_plus.v`, `sim/mutation_check.py` (CPU mutants on the new text), `tests/cpu_pass.txt`, docs | §2.4; `make cpu-update CORE=c816`, copy to `tests/cpu_pass.txt` | `make check`: `make test` 56/56 plus the `dbg_illegal` check; `make mutation` 10 of 10; `make synth` fits B (record LUT4 with the yosys version) | standard, N=3 |
| 9 | `rtl/cpu65816x.v` (delete), `tb/cpu_adapt_old.vh` (delete), `Makefile` (`CORE` default c816), `docs/ARCHITECTURE.md`, `HANDOFF.md` | remove the old core after the owner agrees | `make check` passes | standard, N=1 |

## 9. Risks, resources, open questions

### 9.1 Risks

| Risk | Effect | Action |
|---|---|---|
| vsim is too slow for the case tables and more modules | `make test` and `make mutation` slow | measure in WO3; retire vsim by §7.4 |
| The din-to-ALU-to-register path limits Fmax | lower clock (nextpnr is not installed) | measure in C6; move execute to phase 0 of the next cycle if necessary |
| `halt` inside an instruction changes DMA timing | system results change | WO8 runs the 56 system checks |
| 16-bit access at a bank end (one vector only) | a rare wrong address | keep the 24-bit increment; check again in C3 |
| IO cycles without `rd` | SNES behavior not verified | check in F3 |
| Yosys 0.33 and 0.52 give different LUT counts | budget numbers differ | quote the version with each number |
| Vector files with `--bus` are larger | slower public runs (estimate 5-8 min) | use `--bus` only for acceptance |

### 9.2 Resources (estimate, not measured)

| Block | LUT4 (estimate) | FF (estimate) |
|---|---|---|
| Registers and write rules | 250-400 | 130 |
| Latches and sequencer | 100-200 | 60 |
| ALU 16-bit | 120-200 | 0 |
| Address unit (24-bit adders, 9-input mux) | 250-400 | 0 |
| Decode (53 rows; 256 rows in C4) | 150-300 (400-700) | 0 |
| Micro table | 100-250 | 0 |
| `WDM` unit (combinational DIV until C6) | 700-1,500 | 35 |
| Total | 1,700-3,300 | about 230 |

Plus 2 `MULT18X18D` and no BRAM. The ±50% range follows from no synthesis.

### 9.3 Open questions for the owner

1. Approve 2 FPGA clocks for each CPU cycle (option A)?
2. Approve the DMA stop at a cycle boundary, also inside an instruction?
3. Approve IO cycles without a `rd` strobe on the SNES bus?
4. Approve generated tables committed to the repository, with `tables-check` in `make check` and the CI?
5. Approve the names `c816_*` and the folder `rtl/cpu/`?
6. Unimplemented opcode: a 2-cycle NOP with a sticky `dbg_illegal` (proposed), or stop the core?
7. Delete `rtl/cpu65816x.v` in WO9 after the new core passes?
8. Keep `sim/vsim.py` for now (proposed), or retire it in C2?

## 10. Review

Checked on 2026-11-27 with a second script, written from the text of this document:

- The script reads the tables of section 5.3 and applies the rules of sections 3.3, 3.4, and 5.1.
- It compared them with all 1,060,000 public vectors of the 53 opcodes.
- Cycle count, cycle kind (VDA, VPA, write), address, and written data: 0 differences.

Corrected in the review: the cycle and bus checks of section 7.2 apply only to the new core.
Not checked: the module port lists, the resource estimates, and the rules of section 5.4.

## 11. Step C3: all addressing modes (done 2026-11-28)

The structure of the sections above did not change. The additions:

| Part | Addition |
|---|---|
| Latch | `OF`, the offset byte of a direct page or stack relative instruction (`cap` code 7) |
| `asel` (now 5 bits) | `DUMI` replaces `DUMX` (X or Y); `DP0 DP1` pointer of (dp) and (dp),Y; `DX0 DX1` pointer of (dp,X); `LP0 LP1 LP2` pointer of [dp]; `SR0 SR1` pointer of (sr,S),Y |
| `ea` | `ABSY LONGX LONGY DP DPX DPY SR` |
| `skip` | `DL0`: skip the next step if D[7:0] = 0 |
| Sequences | `DP DPX DPIND DPXIND DPINDY DPLONG SR SRINDY`; `abs,Y` uses `ABSX`, and `long,X` uses `LONG` |
| Ports | `c816_addr` has `y`, `d`, and `of`; `c816_seq` has `dlz` |

Rules that the public vectors confirm:

- Direct page and stack relative data stay in bank 0, also the second byte of a 16-bit value.
- In emulation mode with D[7:0] = 0, direct page indexing and the pointers of (dp), (dp,X), and
  (dp),Y stay in one page. The pointer of [dp] does not.
- (sr,S),Y has an internal cycle with the address of the high byte of the pointer.
- The internal cycles of direct page and stack relative instructions drive the address of the offset byte.

## 12. Step C4: remaining instructions (done 2026-11-28)

| Part | Addition |
|---|---|
| `bus` | `MOD` (6): the modify cycle of a read-modify-write; a write without VDA in emulation mode |
| `asel` | `SW S1W` stack of a wide instruction; `AB0 AB1 AB2` jump pointer in bank 0; `PX0 PX1` table of (abs,X); `MVS MVD` block move; `EAL` last data byte |
| `wsel` (now 4 bits) | `ALUL ALUH DL PBR AL AH PCL PCH PERL PERH` |
| `pcop` (now 4 bits) | `REL16 RTL DPTR DPTRL REWIND` |
| `hold` | `WIDE`: the stack of the instruction leaves page 1 until its last cycle |
| `op` | `ASL LSR ROL ROR TSB TRB BIT BITI XBA PLP MVN MVP` |
| `src`, `dst` (now 4 bits) | `P DBR PBR` |
| `seq` (now 6 bits) | 18 new sequences; 42 in total |
| Ports | `c816_regs` has `s_wide`, `s_open`, and the block move inputs; `c816_addr` has `w8` and `rel16` |

A read-modify-write on memory takes its ALU input from the data latches: the decode row has no
source register. A block move fetches its opcode again after each byte, until A is `$FFFF`.

Rules that the public vectors confirm:

- In emulation mode, the modify cycle writes the old byte, with VDA and VPA at 0.
- `PEA`, `PEI`, `PER`, `PHD`, `PLD`, `PLB`, `JSL`, `RTL`, and `JSR (abs,X)` leave page 1 in
  emulation mode. S is in page 1 again at the end of the instruction.
- The jump table of (abs,X) is read in the program bank, with VDA.

## 13. Step C5: decimal mode and interrupts (done 2026-11-28)

| Part | Addition |
|---|---|
| ALU | digit by digit adjust of `ADC` and `SBC` when D = 1; V comes from the sum before the last digit is corrected |
| `ir` | pseudo-opcodes `$101` NMI and `$102` IRQ; `$100` reset |
| Sampling | at `commit`: `take_nmi`, `take_irq`; nothing is taken at the end of an interrupt sequence |
| `last`, `skip` | `EMU`: end or skip in emulation mode |
| `pcop` | `VECT`: load PC from the vector, PBR = 0 |
| `wsel` | `PSW`: P; in emulation mode, NMI and IRQ push it with bit 4 at 0 |
| `hold` | `WAI` repeats the step until a request; `STP` repeats it until reset |
| `op` | `BRK` (31): set I, clear D |
| Sequences | `BRK INT RTI WAI STP`, and a new `RST` of 7 cycles |

The public vectors confirm decimal mode, `BRK`, `COP`, `RTI`, and the first cycles of `WAI` and
`STP`. The directed tests `tb/tb_cpu_int.v` and `tb/tb_snes_nmi.v` check NMI, IRQ, and reset.

## 14. Step C6: sequential dividers (done 2026-11-28)

| Part | Addition |
|---|---|
| `c816_ext` | restoring divider, one quotient bit at each FPGA clock; `start` loads A and X; `busy` is 1 for 16 clocks |
| `c816_core` | `start` at the end of the sub-opcode cycle of `WDM DIV` |
| `last` | `NDIV`: end the instruction here, unless it is `WDM DIV` |
| `c816_seq` | `ext_busy` holds the step, as `WAI` does |
| Sequences | `WDMX` has a second step, an IO cycle |
| `s_cpu_5a22` | multiply (8 steps) and divide (16 steps), one step at the end of each CPU cycle |

`WDM DIV` takes 11 CPU cycles: the opcode, the sub-opcode, and 9 IO cycles. The extensions exist
only in extended mode, so no SNES timing changes. The synthesis has no `$div` or `$mod` cell.
