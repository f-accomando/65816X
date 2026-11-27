# 65816X - comandi principali
PY ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yosys
# varianti controllate da "make synth" (A = 45F, B = 85F); vedi docs/VERIFICATION.md
BUDGET ?= B

RTL := $(filter %.v,$(shell cat rtl/files.f))

.PHONY: test mutation rom iverilog unit cpu cpu-run cpu-update synth check clean

# Collaudo con il mini simulatore Python (nessuna dipendenza esterna)
test:
	$(PY) sim/run_tests.py

# Verifica che il collaudo scopra guasti introdotti di proposito nell'RTL
mutation:
	$(PY) sim/mutation_check.py

# Assembla il programma di collaudo in rom.hex (letto da cart_rom.v con $$readmemh)
rom: rom.hex
rom.hex: tests/test_program.asm sim/asm.py
	$(PY) sim/asm.py tests/test_program.asm rom.hex

build/checks.vh: tests/test_program.expect tests/test_program.asm sim/gen_tb.py sim/run_tests.py
	$(PY) sim/gen_tb.py build/checks.vh

# Simulazione con Icarus Verilog: stessi controlli di "make test"
iverilog: rom.hex build/checks.vh
	$(IVERILOG) -g2012 -I build -o build/sim.vvp $(RTL) tb/tb_snes_plus.v
	$(VVP) -n build/sim.vvp

# Test per modulo con Icarus Verilog (confronto con i modelli di riferimento in tb/)
unit:
	mkdir -p build
	$(IVERILOG) -g2012 -o build/tb_wram.vvp rtl/wram.v tb/wram_ref.v tb/tb_wram.v
	$(VVP) -n build/tb_wram.vvp

# Banco di prova della sola CPU: pagella in build/cpu_score.txt (vedi docs/VERIFICATION.md)
build/cpu_vectors.txt: sim/cpu_vectors.py sim/cpu_ref.py
	$(PY) sim/cpu_vectors.py $@

cpu-run: build/cpu_vectors.txt
	$(IVERILOG) -g2012 -s tb_cpu -o build/tb_cpu.vvp $(RTL) tb/tb_cpu.v
	$(VVP) -n build/tb_cpu.vvp +vec=build/cpu_vectors.txt +out=build/cpu_results.txt

cpu: cpu-run
	$(PY) sim/cpu_score.py build/cpu_results.txt build/cpu_score.txt

# riscrive tests/cpu_pass.txt con cio' che passa oggi: guardare la differenza prima di tenerla
cpu-update: cpu-run
	$(PY) sim/cpu_score.py build/cpu_results.txt build/cpu_score.txt --update

# Sintesi ECP5 con yosys: conteggio reale delle celle e controllo del budget
synth: rom.hex
	mkdir -p build
	$(YOSYS) -q -l build/synth.log -p "read_verilog $(RTL); synth_ecp5 -top snes_plus_top; tee -q -o build/stat.json stat -json"
	$(PY) syn/budget.py build/stat.json $(BUDGET)

# Tutto quello che esegue la CI
check: test mutation iverilog unit cpu synth

clean:
	rm -rf build rom.hex
