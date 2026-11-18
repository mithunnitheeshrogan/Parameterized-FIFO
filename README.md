# Parameterized Synchronous FIFO (Verilog)

A single-clock, parameterized FIFO in Verilog-2005 with **full DEPTH capacity**, an occupancy counter, and overflow/underflow flags. It is verified with a self-checking testbench that compares the DUT against a cycle-accurate reference model.

The repo also includes a deliberately buggy "naive" FIFO that shows why the usual `wr_ptr + 1 == rd_ptr` full-flag trick fails.

## Features

- Parameterized data width (`DATA_W`) and depth (`DEPTH`, power of 2, >= 2)
- Uses all `DEPTH` entries, using (ADDR_W+1)-bit pointers with a "lap" bit
- Occupancy `count` output (0 .. DEPTH) from `wr_ptr - rd_ptr`, with no separate counter
- `full`, `empty`, `overflow` and `underflow` flags
- Synchronous active-low reset
- Registered read data (standard, non-FWFT): `rd_data` is valid the cycle after an accepted read
- Elaboration-time check that rejects an invalid `DEPTH` with a clear message
- Lints clean in Verilator

## Interface

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock |
| `rst_n` | in | 1 | Active-low synchronous reset |
| `wr_en` | in | 1 | Write request (ignored when full) |
| `wr_data` | in | `DATA_W` | Write data |
| `full` | out | 1 | FIFO holds `DEPTH` words |
| `rd_en` | in | 1 | Read request (ignored when empty) |
| `rd_data` | out | `DATA_W` | Read data, valid one cycle after accepted `rd_en` |
| `empty` | out | 1 | FIFO holds no words |
| `count` | out | `$clog2(DEPTH)+1` | Current occupancy |
| `overflow` | out | 1 | One-cycle pulse: write attempted while full |
| `underflow` | out | 1 | One-cycle pulse: read attempted while empty |

| Parameter | Default | Notes |
|---|---|---|
| `DATA_W` | 8 | Data width in bits |
| `DEPTH` | 16 | Number of entries, must be a power of 2 and >= 2 |

## How full/empty detection works

Each pointer has one extra MSB, the lap bit, which flips every time the pointer wraps.

```
empty : wr_ptr == rd_ptr                               (same address, same lap)
full  : wr_ptr[MSB] != rd_ptr[MSB]
        && wr_ptr[ADDR_W-1:0] == rd_ptr[ADDR_W-1:0]    (same address, writer one lap ahead)
count : wr_ptr - rd_ptr                                (modular subtraction)
```

### Why the naive version fails

`sync_fifo_naive.v` uses ADDR_W-bit pointers and `full = (wr_ptr + 1 == rd_ptr)`. It has two bugs:

1. **Width bug.** The literal `1` is a 32-bit integer, so `wr_ptr + 1` is evaluated at 32 bits. At `wr_ptr = DEPTH-1` the sum is `DEPTH`, not 0, so `full` never asserts on the wrap. The next write is accepted, the pointers collide, and the FIFO reports **empty while holding DEPTH words**.
2. **Capacity bug.** Even with the width fixed (`1'b1`), the scheme can hold only `DEPTH-1` entries.

With `DEPTH=8` the testbench reports **9,050 errors** on the naive design and **0** on the lap-bit design.

## Repository structure

```
.
├── sync_fifo.v          # Correct parameterized FIFO (lap-bit pointers)
├── sync_fifo_naive.v    # Intentionally buggy version, for comparison
├── tb_sync_fifo.v       # Self-checking testbench with reference model
├── run.do               # ModelSim/Questa run script
└── docs/
    ├── waveform.png     # ModelSim waveform screenshot
    └── transcript.png   # ModelSim transcript screenshot
```

## Verification

The testbench mirrors what the DUT accepts (`wr_en && !full`, `rd_en && !empty`) in an independent model, and checks every cycle that:

- `full` equals (model occupancy == DEPTH)
- `empty` equals (model occupancy == 0)
- `count` equals model occupancy
- `rd_data` matches the expected word, in order

| Test | What it covers |
|---|---|
| T1 | Fill from reset, flag behaviour on every write, extra writes must be rejected |
| T2 | Fill/drain with pointers wrapping at every starting offset |
| T3 | Simultaneous read and write at full and at empty |
| T4 | 5000 cycles of random read/write traffic |

**Results:** all four tests pass with 0 errors (`DEPTH=8`, `DATA_W=8`). A parameter sweep over `DATA_W` in {1, 8, 32} and `DEPTH` in {2, 4, 16, 32, 64} also passes.

### Waveform

![ModelSim waveform](docs/waveform.png)

The DUT `count` tracks the model `q_cnt` exactly. `full` asserts at 8 words, `overflow` pulses for the rejected writes, and `rd_data` returns the words in write order.

### Simulation transcript

![ModelSim transcript](docs/transcript.png)

## How to run

### ModelSim / Questa

```tcl
cd C:/path/to/this/folder
do run.do            ;# correct FIFO
do run.do NAIVE      ;# buggy FIFO (expect failures)
```

Batch mode, no GUI:

```
vsim -c -do "do run.do; quit -f"
```

### Icarus Verilog

```
iverilog -g2005 -o sim tb_sync_fifo.v sync_fifo.v
vvp sim

# buggy version
iverilog -g2005 -DNAIVE -o sim_naive tb_sync_fifo.v sync_fifo_naive.v
vvp sim_naive

# other sizes
iverilog -g2005 -Ptb_sync_fifo.DEPTH=32 -Ptb_sync_fifo.DATA_W=16 -o sim tb_sync_fifo.v sync_fifo.v
vvp sim
```

The testbench writes `fifo.vcd`, which you can open with GTKWave.

### Lint

```
verilator --lint-only -Wall -Wno-DECLFILENAME sync_fifo.v
```

## Limitations and future work

- Single clock domain only. An asynchronous FIFO needs Gray-code pointer synchronisers.
- Read data is registered (non-FWFT). A first-word-fall-through mode would be a useful option.
- Functional simulation only. No synthesis or timing results are included.
- Possible extensions: `almost_full` / `almost_empty` thresholds, SystemVerilog assertions, a UVM testbench, and formal checks of the full/empty invariants.

## Tools

Verilog-2005, ModelSim, Icarus Verilog, Verilator (lint)

## Author

**Mithun**, M.Tech VLSI Design, Vellore Institute of Technology
[LinkedIn](https://www.linkedin.com/in/your-profile) · [GitHub](https://github.com/your-username)
