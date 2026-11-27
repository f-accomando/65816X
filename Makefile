# 65816X - comandi principali
PY ?= python3
IVERILOG ?= iverilog
YOSYS ?= yosys

.PHONY: test mutation rom iverilog synth clean

# Collaudo con il mini simulatore Python (nessuna dipendenza esterna)
test:
	$(PY) sim/run_tests.py

# Verifica che il collaudo scopra guasti introdotti di proposito nell'RTL
mutation:
	$(PY) sim/mutation_check.py

# Assembla il programma di collaudo in rom.hex (letto da cart_rom.v)
rom: rom.hex
rom.hex: tests/test_program.asm sim/asm.py
	$(PY) sim/asm.py tests/test_program.asm rom.hex

# Simulazione con Icarus Verilog (richiede iverilog installato)
iverilog: rom.hex
	mkdir -p build
	$(IVERILOG) -g2012 -o build/sim.vvp rtl/*.v tb/tb_snes_plus.v
	vvp build/sim.vvp

# Sintesi di prova per ECP5 (richiede yosys): stampa il conteggio reale di LUT/BRAM
synth:
	$(YOSYS) -p "read_verilog rtl/cpu65816x.v rtl/s_cpu_5a22.v rtl/ppu_stub.v rtl/apu_stub.v rtl/wram.v rtl/cart_rom.v rtl/ext_regs.v rtl/snes_plus_top.v; synth_ecp5 -top snes_plus_top; stat"

clean:
	rm -rf build rom.hex
