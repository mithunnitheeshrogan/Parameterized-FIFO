# ============================================================================
# run.do  -  ModelSim / Questa script for the sync FIFO testbench
#
#   In the ModelSim transcript (cd to the folder with the .v files first):
#       do run.do          ;# correct FIFO   (sync_fifo.v)
#       do run.do NAIVE    ;# buggy FIFO     (sync_fifo_naive.v)
#
#   Batch mode, no GUI:
#       vsim -c -do "do run.do; quit -f"
#       vsim -c -do "do run.do NAIVE; quit -f"
# ============================================================================

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# Recompile the testbench every time, because the NAIVE define changes it
if {$argc > 0 && [string equal $1 "NAIVE"]} {
    echo ">>> Compiling NAIVE (buggy) FIFO"
    vlog -work work +define+NAIVE sync_fifo_naive.v tb_sync_fifo.v
} else {
    echo ">>> Compiling correct FIFO"
    vlog -work work sync_fifo.v tb_sync_fifo.v
}

# +acc keeps internal signals visible; -onfinish stop keeps the GUI open at $finish
vsim -voptargs=+acc -onfinish stop work.tb_sync_fifo

# ---------------- waveform ----------------
add wave -divider "Clock / reset"
add wave          /tb_sync_fifo/clk
add wave          /tb_sync_fifo/rst_n

add wave -divider "Write port"
add wave          /tb_sync_fifo/wr_en
add wave -radix hex /tb_sync_fifo/wr_data
add wave          /tb_sync_fifo/full
add wave          /tb_sync_fifo/overflow

add wave -divider "Read port"
add wave          /tb_sync_fifo/rd_en
add wave -radix hex /tb_sync_fifo/rd_data
add wave          /tb_sync_fifo/empty
add wave          /tb_sync_fifo/underflow

add wave -divider "Occupancy: DUT vs model"
add wave -radix unsigned /tb_sync_fifo/count
add wave -radix unsigned /tb_sync_fifo/q_cnt

add wave -divider "DUT pointers"
add wave -radix unsigned /tb_sync_fifo/dut/wr_ptr
add wave -radix unsigned /tb_sync_fifo/dut/rd_ptr

add wave -divider "Errors"
add wave -radix unsigned /tb_sync_fifo/errors

run -all
# wave window only exists in GUI mode; don't fail in vsim -c
catch {wave zoom range 0ns 300ns}
