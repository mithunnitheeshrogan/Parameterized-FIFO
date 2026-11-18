# Parameterized-FIFO
Parameterized synchronous FIFO in Verilog with full-depth capacity, lap-bit pointers, occupancy count and overflow/underflow flags. Includes a self-checking testbench with a reference model, a ModelSim run script, and a deliberately buggy naive FIFO to show why wr_ptr + 1 == rd_ptr fails.
