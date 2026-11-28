# 65816X - comandi principali
PY ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yosys
# varianti controllate da "make synth" (A = 45F, B = 85F); vedi docs/VERIFICATION.md
BUDGET ?= B

RTL := $(filter %.v,$(shell cat rtl/files.f))

.PHONY: test mutation cpu-mutation cpu-int rom iverilog unit ppu-unit ppu ppu-update ppu-mutation synth-ppu cpu cpu-run cpu-update cpu-public ref-public tables tables-check synth manual manual-check check clean

# Collaudo con il mini simulatore Python (nessuna dipendenza esterna)
test:
	$(PY) sim/run_tests.py

# Verifica che il collaudo scopra guasti introdotti di proposito nell'RTL
mutation:
	$(PY) sim/mutation_check.py

# Interrupts: reset, NMI, IRQ, BRK, RTI, WAI, STP in the core, and the NMI of the system
# (directed tests; the public vectors do not cover the interrupt inputs)
cpu-int: rom.hex
	mkdir -p build
	$(IVERILOG) -g2012 -s tb_cpu_int -o build/tb_cpu_int.vvp $(RTL) tb/tb_cpu_int.v
	$(VVP) -n build/tb_cpu_int.vvp
	$(IVERILOG) -g2012 -s tb_snes_nmi -o build/tb_snes_nmi.vvp $(RTL) tb/tb_snes_nmi.v
	$(VVP) -n build/tb_snes_nmi.vvp

# Faults in the new core: the CPU test bench must find each one (needs iverilog)
cpu-mutation: rom.hex
	$(PY) sim/mutation_check.py --cpu

# Assembla il programma di collaudo in rom.hex (letto da cart_rom.v con $$readmemh)
rom: rom.hex
rom.hex: tests/test_program.asm sim/asm.py
	$(PY) sim/asm.py tests/test_program.asm rom.hex

build/checks.vh: tests/test_program.expect tests/test_program.asm sim/gen_tb.py sim/run_tests.py
	$(PY) sim/gen_tb.py build/checks.vh

# Simulazione con Icarus Verilog: stessi controlli di "make test"
iverilog: rom.hex build/checks.vh
	$(IVERILOG) -g2012 -I build -s tb_snes_plus -o build/sim.vvp $(RTL) tb/tb_snes_plus.v
	$(VVP) -n build/sim.vvp

# Test per modulo con Icarus Verilog (confronto con i modelli di riferimento in tb/)
unit: ppu-unit
	mkdir -p build
	$(IVERILOG) -g2012 -o build/tb_wram.vvp rtl/wram.v tb/wram_ref.v tb/tb_wram.v
	$(VVP) -n build/tb_wram.vvp
	$(IVERILOG) -g2012 -s tb_c816_ext -o build/tb_c816_ext.vvp rtl/cpu/c816_ext.v tb/tb_c816_ext.v
	$(VVP) -n build/tb_c816_ext.vvp

# Unit tests of the PPU (needs iverilog): the timing against the description in its bench, and
# random register accesses against the reference model
ppu-unit:
	mkdir -p build
	$(IVERILOG) -g2012 -s tb_ppu_timing -o build/tb_ppu_timing.vvp rtl/ppu/ppu_timing.v tb/tb_ppu_timing.v
	$(VVP) -n build/tb_ppu_timing.vvp
	$(PY) sim/ppu_regs_run.py

# Scenes of the PPU: the RTL against the reference model, pictures in build/ppu (needs iverilog)
ppu:
	$(PY) sim/ppu_run.py

# writes the CRC lists of the scenes from the model: check the difference before you keep it
ppu-update:
	$(PY) sim/ppu_run.py --update

# Faults in the PPU: its benches must find each one (needs iverilog)
ppu-mutation:
	$(PY) sim/mutation_check.py --ppu

# Banco di prova della sola CPU: pagella in build/cpu_score.txt (vedi docs/VERIFICATION.md)
build/cpu_vectors.txt: sim/cpu_vectors.py sim/cpu_ref.py
	$(PY) sim/cpu_vectors.py $@

CPU_VVP := build/tb_cpu.vvp
CPU_PASS := tests/cpu_pass.txt
CPU_RES := build/cpu_results.txt
CPU_SCORE := build/cpu_score.txt

$(CPU_VVP): $(RTL) rtl/files.f tb/tb_cpu.v tb/cpu_adapt_c816.vh
	mkdir -p build
	$(IVERILOG) -g2012 -s tb_cpu -I tb -o $@ $(RTL) tb/tb_cpu.v

cpu-run: build/cpu_vectors.txt $(CPU_VVP)
	$(VVP) -n $(CPU_VVP) +vec=build/cpu_vectors.txt +out=$(CPU_RES)

cpu: cpu-run
	$(PY) sim/cpu_score.py $(CPU_RES) $(CPU_SCORE) --passlist $(CPU_PASS)

# riscrive l'elenco di cio' che passa: guardare la differenza prima di tenerla
cpu-update: cpu-run
	$(PY) sim/cpu_score.py $(CPU_RES) $(CPU_SCORE) --passlist $(CPU_PASS) --update

# Vettori pubblici SingleStepTests/65816, tenuti fuori dal repository (vedi docs/VERIFICATION.md)
# SST = cartella che contiene v1/; SST_FLAGS: --limit N, --d0, --page1, --bus
SST ?=
SST_FLAGS ?=

cpu-public: $(CPU_VVP)
	@test -n "$(SST)" || { echo "manca SST=<cartella dei vettori>"; exit 1; }
	$(PY) -I sim/cpu_sst.py convert "$(SST)" build/sst_vectors.txt $(SST_FLAGS)
	$(VVP) -n $(CPU_VVP) +vec=build/sst_vectors.txt +out=build/sst_results.txt
	$(PY) sim/cpu_score.py build/sst_results.txt build/cpu_public_score.txt --report-only

ref-public:
	@test -n "$(SST)" || { echo "manca SST=<cartella dei vettori>"; exit 1; }
	$(PY) -I sim/cpu_sst.py check-ref "$(SST)" $(SST_FLAGS)

# Decode and sequence tables of the new CPU core: rtl/cpu/c816_tables.txt is the only source
tables:
	$(PY) sim/gen_c816_tables.py

tables-check:
	$(PY) sim/gen_c816_tables.py --check

# Sintesi ECP5 con yosys: conteggio reale delle celle e controllo del budget
synth: rom.hex
	mkdir -p build
	$(YOSYS) -q -l build/synth.log -p "read_verilog $(RTL); synth_ecp5 -top snes_plus_top; tee -q -o build/stat.json stat -json"
	$(PY) syn/budget.py build/stat.json $(BUDGET)

# Resources of the PPU alone (information for each step of docs/design/ppu-plan.md)
synth-ppu:
	mkdir -p build
	$(YOSYS) -q -l build/synth_ppu.log -p "read_verilog $(filter rtl/ppu/%,$(RTL)); synth_ecp5 -top ppu_top; tee -q -o build/stat_ppu.json stat -json"
	$(PY) syn/budget.py build/stat_ppu.json $(BUDGET)

# The manual in manuals/pdf (needs reportlab). manual-check fails if its sources changed.
manual:
	$(PY) manuals/tools/manuals.py build

manual-check:
	$(PY) manuals/tools/manuals.py check

# Tutto quello che esegue la CI
check: tables-check test mutation iverilog unit cpu cpu-int cpu-mutation ppu ppu-mutation synth manual-check

clean:
	rm -rf build rom.hex
