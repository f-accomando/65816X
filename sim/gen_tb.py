#!/usr/bin/env python3
"""gen_tb.py - genera i controlli per tb/tb_snes_plus.v (Icarus Verilog) da
tests/test_program.expect e dall'etichetta 'done' del programma di collaudo.
Uso: python3 sim/gen_tb.py build/checks.vh"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import asm, run_tests

def main(out):
    _, labels = asm.assemble(open(run_tests.PROGRAM).read())
    expect = run_tests.load_expect()
    lines = ["// generato da sim/gen_tb.py: non modificare",
             "localparam [15:0] DONE = 16'h%04X;" % labels['done'],
             "localparam integer MAX_CYCLES = %d;" % run_tests.MAX_CYCLES,
             "localparam integer TOTAL = %d;" % len(expect),
             "task run_checks;",
             "  begin"]
    for mem, addr, exp in expect:
        ref = "dut.%s[%d]" % (run_tests.MEMS[mem], addr)
        lines.append('    if (%s !== 8\'h%02X) begin $display("FAIL %s[%04X] = %%h, atteso %02X", %s); fails = fails + 1; end'
                     % (ref, exp, mem, addr, exp, ref))
    lines += ["  end", "endtask", ""]
    os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
    open(out, 'w').write("\n".join(lines))

if __name__ == '__main__':
    main(sys.argv[1])
