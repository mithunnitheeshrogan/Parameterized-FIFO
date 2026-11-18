// ============================================================================
// sync_fifo_naive.v  -  The full/empty logic most people write first.
//                       !!! BUGGY ON PURPOSE - do not use !!!
//
// Pointers are only ADDR_W bits wide, so "pointers equal" is ambiguous:
// it means EMPTY after a reset/drain, but also FULL after DEPTH writes.
// The usual patch is to call it full one slot early:
//
//      assign empty = (wr_ptr == rd_ptr);
//      assign full  = (wr_ptr + 1 == rd_ptr);      // <-- looks right...
//
// Two problems hide in that one line:
//
//  BUG 1 (functional, silent data loss)
//    `1` is a 32-bit integer, so Verilog evaluates `wr_ptr + 1` at 32 bits
//    inside the comparison. When wr_ptr = DEPTH-1 the sum is DEPTH, not 0,
//    so the compare against rd_ptr = 0 FAILS and full never asserts on the
//    wrap. The next write is accepted, wr_ptr wraps to rd_ptr, and the FIFO
//    now reports EMPTY while holding DEPTH valid words. Everything is lost.
//    It only fails when the wrap lines up with rd_ptr = 0, e.g. the very
//    first fill after reset, which is exactly the test people tend to skip.
//
//  BUG 2 (capacity)
//    Even with the width fixed (wr_ptr + 1'b1), this scheme holds only
//    DEPTH-1 entries. A "16-deep" FIFO is really 15-deep. Size a buffer
//    for a burst of exactly DEPTH and you back-pressure/drop the last word.
//
// The fix is in sync_fifo.v: an extra lap bit on each pointer.
// ============================================================================
`timescale 1ns/1ps

module sync_fifo_naive #(
    parameter DATA_W = 8,
    parameter DEPTH  = 16
)(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    wr_en,
    input  wire [DATA_W-1:0]       wr_data,
    output wire                    full,

    input  wire                    rd_en,
    output reg  [DATA_W-1:0]       rd_data,
    output wire                    empty,

    output wire [$clog2(DEPTH):0]  count,
    output reg                     overflow,
    output reg                     underflow
);

    localparam ADDR_W = $clog2(DEPTH);

    reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg [ADDR_W-1:0] wr_ptr, rd_ptr;          // no lap bit

    wire wr_fire = wr_en && !full;
    wire rd_fire = rd_en && !empty;

    always @(posedge clk) begin
        if (!rst_n)
            wr_ptr <= 0;
        else if (wr_fire) begin
            mem[wr_ptr] <= wr_data;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr  <= 0;
            rd_data <= 0;
        end else if (rd_fire) begin
            rd_data <= mem[rd_ptr];
            rd_ptr  <= rd_ptr + 1'b1;
        end
    end

    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr + 1 == rd_ptr);    // BUG: 32-bit add, never wraps
    assign count = {1'b0, wr_ptr - rd_ptr};   // can never report DEPTH either

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
