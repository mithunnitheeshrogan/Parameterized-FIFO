// ============================================================================
// tb_sync_fifo.v  -  Self-checking testbench with a reference model.
//
//   iverilog -g2005 -o sim tb_sync_fifo.v sync_fifo.v              && vvp sim
//   iverilog -g2005 -DNAIVE -o sim tb_sync_fifo.v sync_fifo_naive.v && vvp sim
//   iverilog -g2005 -Ptb_sync_fifo.DEPTH=32 -Ptb_sync_fifo.DATA_W=16 ...   (other sizes)
//
// The model mirrors what the DUT accepts (wr_en && !full, rd_en && !empty)
// and independently checks, every cycle:
//   * full  == (model occupancy == DEPTH)
//   * empty == (model occupancy == 0)
//   * count == model occupancy
//   * rd_data matches the expected word, in order
// ============================================================================
`timescale 1ns/1ps

module tb_sync_fifo;

    parameter  DATA_W = 8;                    // override: iverilog -Ptb_sync_fifo.DEPTH=16
    parameter  DEPTH  = 8;                    // must be a power of 2, >= 2
    localparam ADDR_W = $clog2(DEPTH);

    reg                 clk = 0;
    reg                 rst_n = 0;
    reg                 wr_en = 0, rd_en = 0;
    reg  [DATA_W-1:0]   wr_data = 0;
    wire [DATA_W-1:0]   rd_data;
    wire                full, empty, overflow, underflow;
    wire [ADDR_W:0]     count;

`ifdef NAIVE
    sync_fifo_naive #(.DATA_W(DATA_W), .DEPTH(DEPTH)) dut (
`else
    sync_fifo       #(.DATA_W(DATA_W), .DEPTH(DEPTH)) dut (
`endif
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_data(wr_data), .full(full),
        .rd_en(rd_en), .rd_data(rd_data), .empty(empty),
        .count(count), .overflow(overflow), .underflow(underflow)
    );

    always #5 clk = ~clk;

    // ---------------- reference model ----------------
    reg [DATA_W-1:0] q [0:DEPTH-1];          // model storage (circular)
    integer          q_head = 0, q_tail = 0, q_cnt = 0;
    reg [DATA_W-1:0] exp_data;
    reg              chk_rd = 0;
    integer          errors = 0, test_errors = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            q_head = 0; q_tail = 0; q_cnt = 0; chk_rd = 0;
        end else begin
            chk_rd = 0;
            if (rd_en && !empty) begin            // DUT accepts the read
                if (q_cnt == 0) begin
                    report("read accepted but model is empty");
                end else begin
                    exp_data = q[q_head];
                    q_head   = (q_head + 1) % DEPTH;
                    q_cnt    = q_cnt - 1;
                    chk_rd   = 1;
                end
            end
            if (wr_en && !full) begin             // DUT accepts the write
                if (q_cnt == DEPTH) begin
                    report("write accepted while model holds DEPTH words (overwrite!)");
                end else begin
                    q[q_tail] = wr_data;
                    q_tail    = (q_tail + 1) % DEPTH;
                    q_cnt     = q_cnt + 1;
                end
            end
        end
    end

    // Check outputs mid-cycle, after the DUT has settled
    always @(negedge clk) if (rst_n) begin
        if (chk_rd && rd_data !== exp_data) begin
            report2("rd_data mismatch", rd_data, exp_data);
        end
        if (full !== (q_cnt == DEPTH))
            report2("full flag wrong  (full, model count)", full, q_cnt);
        if (empty !== (q_cnt == 0))
            report2("empty flag wrong (empty, model count)", empty, q_cnt);
        if (count !== q_cnt)
            report2("count wrong      (count, model count)", count, q_cnt);
    end

    task report(input [8*64-1:0] msg);
        begin
            errors = errors + 1; test_errors = test_errors + 1;
            if (test_errors <= 4) $display("    ERROR @%0t: %0s", $time, msg);
        end
    endtask

    task report2(input [8*64-1:0] msg, input integer got, input integer exp);
        begin
            errors = errors + 1; test_errors = test_errors + 1;
            if (test_errors <= 4) $display("    ERROR @%0t: %0s : got %0d, expected %0d",
                                           $time, msg, got, exp);
        end
    endtask

    // ---------------- stimulus helpers ----------------
    task cycle(input w, input [DATA_W-1:0] d, input r);
        begin
            wr_en = w; wr_data = d; rd_en = r;
            @(negedge clk);
            wr_en = 0; rd_en = 0;
        end
    endtask

    task begin_test(input [8*64-1:0] name);
        begin
            do_reset;              // each test starts clean
            test_errors = 0;
            $display("\n[%0s]", name);
        end
    endtask

    task end_test;
        begin
            if (test_errors == 0) $display("    PASS");
            else                  $display("    FAIL (%0d errors)", test_errors);
        end
    endtask

    task do_reset;
        begin
            rst_n = 0; wr_en = 0; rd_en = 0;
            repeat (2) @(negedge clk);
            rst_n = 1;
            @(negedge clk);
        end
    endtask

    integer i, accepted, seed;
    reg [DATA_W-1:0] wr_byte;

    initial begin
        $dumpfile("fifo.vcd");
        $dumpvars(0, tb_sync_fifo);
`ifdef NAIVE
        $display("=== DUT: sync_fifo_naive  (DEPTH=%0d) ===", DEPTH);
`else
        $display("=== DUT: sync_fifo        (DEPTH=%0d) ===", DEPTH);
`endif
        @(negedge clk);

        // ------------------------------------------------------------------
        begin_test("T1: fill from reset, watch the flags on every write");
        $display("    wr#  data | full empty count");
        accepted = 0;
        for (i = 0; i < DEPTH + 2; i = i + 1) begin
            if (!full) accepted = accepted + 1;
            wr_byte = 8'hA0 + i;
            cycle(1, wr_byte, 0);
            $display("    %3d   %h  |  %b     %b    %0d%0s", i, wr_byte, full, empty, count,
                     (i >= DEPTH) ? "   <- extra write, must be rejected" : "");
        end
        $display("    writes accepted: %0d (expected %0d)", accepted, DEPTH);
        if (accepted != DEPTH) begin errors = errors + 1; test_errors = test_errors + 1; end
        $display("    draining...");
        for (i = 0; i < DEPTH + 1; i = i + 1) cycle(0, 0, 1);
        if (q_cnt != 0) report2("words stranded in FIFO", q_cnt, 0);
        end_test;

        // ------------------------------------------------------------------
        begin_test("T2: fill/drain with pointers wrapping at every offset");
        for (seed = 1; seed < DEPTH; seed = seed + 1) begin
            for (i = 0; i < seed; i = i + 1) cycle(1, i, 0);   // move pointers
            for (i = 0; i < seed; i = i + 1) cycle(0, 0, 1);
            for (i = 0; i < DEPTH + 1; i = i + 1) cycle(1, 8'h40 + i, 0); // to full
            for (i = 0; i < DEPTH + 1; i = i + 1) cycle(0, 0, 1);         // drain
        end
        end_test;

        // ------------------------------------------------------------------
        begin_test("T3: simultaneous read+write at full and at empty");
        for (i = 0; i < DEPTH; i = i + 1) cycle(1, 8'hC0 + i, 0);
        cycle(1, 8'hEE, 1);          // at full: read accepted, write rejected
        cycle(1, 8'hEF, 1);          // now not full: both accepted
        for (i = 0; i < DEPTH + 1; i = i + 1) cycle(0, 0, 1);
        cycle(1, 8'h11, 1);          // at empty: write accepted, read rejected
        cycle(0, 0, 1);
        end_test;

        // ------------------------------------------------------------------
        begin_test("T4: 5000 cycles random traffic");
        seed = 32'h1234_5678;
        for (i = 0; i < 5000; i = i + 1)
            cycle(($random(seed) & 3) != 0, $random(seed), ($random(seed) & 3) != 0);
        for (i = 0; i < DEPTH + 1; i = i + 1) cycle(0, 0, 1);
        end_test;

        // ------------------------------------------------------------------
        $display("\n=== %0s: %0d total errors ===\n",
                 (errors == 0) ? "ALL TESTS PASSED" : "FAILED", errors);
        $finish;
    end

endmodule
