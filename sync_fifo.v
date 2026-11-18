// ============================================================================
// sync_fifo.v  -  Parameterized synchronous FIFO (single clock)
//
//  * DATA_W : data width in bits
//  * DEPTH  : number of entries (must be a power of 2)
//
// Full/empty detection uses (ADDR_W+1)-bit pointers. The extra MSB is a
// "lap" bit that flips each time a pointer wraps around the buffer:
//
//      empty : pointers identical, including the lap bit (same lap)
//      full  : address bits equal, lap bits differ        (writer is one lap ahead)
//
// This uses all DEPTH entries, needs no separate counter, and gives the
// occupancy count for free as (wr_ptr - rd_ptr).
//
// Read latency: rd_data is registered and valid the cycle AFTER rd_en is
// accepted (standard, non-FWFT). Writes to a full FIFO and reads from an
// empty FIFO are ignored, and flagged on overflow/underflow for one cycle.
// ============================================================================
`timescale 1ns/1ps

module sync_fifo #(
    parameter DATA_W = 8,
    parameter DEPTH  = 16,
    // Derived - do not override. Clamped to 1 so a bad DEPTH (e.g. 1) reaches
    // the friendly error below instead of failing with a part-select error.
    parameter ADDR_W = (DEPTH < 2) ? 1 : $clog2(DEPTH)
)(
    input  wire                    clk,
    input  wire                    rst_n,     // active-low synchronous reset

    input  wire                    wr_en,
    input  wire [DATA_W-1:0]       wr_data,
    output wire                    full,

    input  wire                    rd_en,
    output reg  [DATA_W-1:0]       rd_data,
    output wire                    empty,

    output wire [ADDR_W:0]         count,     // 0 .. DEPTH
    output reg                     overflow,  // write attempted while full
    output reg                     underflow  // read attempted while empty
);

    // Elaboration-time sanity check: the lap-bit trick needs a power-of-2 depth.
    // Simulation only - synthesis tools ignore the translate_off region.
    // synthesis translate_off
    initial begin
        if (DEPTH < 2 || (1 << ADDR_W) != DEPTH) begin
            $display("ERROR: sync_fifo DEPTH=%0d must be a power of 2 and >= 2", DEPTH);
            $finish;
        end
    end
    // synthesis translate_on

    reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg [ADDR_W:0]   wr_ptr, rd_ptr;          // note: one extra bit

    wire wr_fire = wr_en && !full;
    wire rd_fire = rd_en && !empty;

    // ---------------- write side ----------------
    always @(posedge clk) begin
        if (!rst_n)
            wr_ptr <= {(ADDR_W+1){1'b0}};
        else if (wr_fire) begin
            mem[wr_ptr[ADDR_W-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // ---------------- read side -----------------
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr  <= {(ADDR_W+1){1'b0}};
            rd_data <= {DATA_W{1'b0}};
        end else if (rd_fire) begin
            rd_data <= mem[rd_ptr[ADDR_W-1:0]];
            rd_ptr  <= rd_ptr + 1'b1;
        end
    end

    // ---------------- status --------------------
    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[ADDR_W]     != rd_ptr[ADDR_W]) &&
                   (wr_ptr[ADDR_W-1:0] == rd_ptr[ADDR_W-1:0]);
    assign count = wr_ptr - rd_ptr;           // modular subtraction, ADDR_W+1 bits

    always @(posedge clk) begin
        if (!rst_n) begin
            overflow  <= 1'b0;
            underflow <= 1'b0;
        end else begin
            overflow  <= wr_en && full;
            underflow <= rd_en && empty;
        end
    end

endmodule
