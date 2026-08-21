`timescale 1ns/1ps
`include "typedefs.svh"

module tb_PUSH_FIFO;

    // Testbench Parameters
    localparam FIFO_SIZE = 8;
    localparam CLK_PERIOD = 10; // 10ns clock period

    // Testbench signals
    logic clk;
    logic rst;
    logic wr_en;
    logic rd_en;
    push_data_t buf_in;
    push_data_t buf_out;
    logic buf_empty;
    logic buf_full;
    logic [$clog2(FIFO_SIZE):0] fifo_counter;

    // Scoreboard for data verification
    push_data_t scoreboard[$];

    // Instantiate the DUT (Design Under Test)
    PUSH_FIFO #(
        .FIFO_SIZE(FIFO_SIZE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .buf_in(buf_in),
        .buf_out(buf_out),
        .buf_empty(buf_empty),
        .buf_full(buf_full),
        .o_fifo_counter(fifo_counter)
    );

    // Clock generation
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Task for applying reset
    task apply_reset;
        rst = 1;
        wr_en <= 0;
        rd_en <= 0;
        buf_in <= '0;
        scoreboard.delete();
        @(negedge clk);
        rst = 0;
        @(negedge clk);
        $display("[%0t] INFO: Reset applied.", $time);
    endtask

    // Task for a single write operation
    task write_fifo(input push_data_t data);
        @(negedge clk);
        wr_en <= 1;
        buf_in <= data;
        if (!buf_full || (buf_full && rd_en && !buf_empty)) begin
            scoreboard.push_back(data);
            $display("[%0t] INFO: Writing data: %p. Scoreboard size: %0d", $time, data, scoreboard.size());
        end else begin
            $display("[%0t] INFO: Attempting to write to FULL FIFO. Data: %p", $time, data);
        end
        @(negedge clk);
        wr_en <= 0;
    endtask

    // Task for a single read operation
    task read_fifo;
        @(negedge clk);
        rd_en <= 1;
        $display("[%0t] INFO: Asserting rd_en.", $time);
        @(negedge clk);
        rd_en <= 0;
    endtask

    // *** Task for simultaneous reads and writes ***
    task rw_fifo(input push_data_t data);
        @(negedge clk);
        wr_en <= 1;
        rd_en <= 1;
        buf_in <= data;
        // Model the expected FIFO behavior: the write should always succeed.
        scoreboard.push_back(data);
        $display("[%0t] INFO: Simultaneous R/W. Writing %p", $time, data);
        @(negedge clk);
        wr_en <= 0;
        rd_en <= 0;
    endtask

    // Main test sequence
    initial begin
        // Initialization
        clk = 0;
        apply_reset();

        // --- TEST 1 to 4: unchanged ---
        $display("\n--- TEST 1: Basic Write and Read ---");
        for (int i = 0; i < 4; i++) write_fifo(push_data_t'{rank_data: i, default:'0});
        repeat(2) @(negedge clk);
        for (int i = 0; i < 4; i++) read_fifo();
        repeat(5) @(negedge clk);

        $display("\n--- TEST 2: Fill FIFO to Full ---");
        for (int i = 0; i < FIFO_SIZE; i++) write_fifo(push_data_t'{rank_data: 10+i, default:'0});
        repeat(2) @(negedge clk);
        assert(buf_full) else $error("TEST 2 FAILED: FIFO should be full.");
        $display("TEST 2 PASSED: FIFO is full as expected.");

        $display("\n--- TEST 3: Attempt to write to a full FIFO ---");
        write_fifo(push_data_t'{rank_data: 99, default:'0});
        assert(fifo_counter == FIFO_SIZE) else $error("TEST 3 FAILED: Counter should not change.");
        $display("TEST 3 PASSED: Write to full FIFO was correctly ignored.");
        repeat(2) @(negedge clk);

        $display("\n--- TEST 4: Read FIFO until empty ---");
        for (int i = 0; i < FIFO_SIZE; i++) read_fifo();
        repeat(5) @(negedge clk);
        assert(buf_empty) else $error("TEST 4 FAILED: FIFO should be empty.");
        $display("TEST 4 PASSED: FIFO is empty as expected.");

        // --- TEST 5: Simultaneous Read/Write on a partially full FIFO ---
        $display("\n--- TEST 5: Simultaneous Read/Write (Refactored) ---");
        for (int i = 0; i < 4; i++) write_fifo(push_data_t'{rank_data: 20+i, default:'0});
        rw_fifo(push_data_t'{rank_data: 98, default:'0}); // Invoke the new task.
        assert(fifo_counter == 4) else $error("TEST 5 FAILED: Counter should remain at 4.");
        $display("TEST 5 PASSED: Simultaneous R/W kept counter stable.");
        repeat(5) @(negedge clk);
        for (int i=0; i<4; i++) read_fifo();
        repeat(5) @(negedge clk);

        // --- TEST 6: CRITICAL - Simultaneous R/W on a FULL FIFO ---
        $display("\n--- TEST 6: Simultaneous R/W on a FULL FIFO (Refactored) ---");
        for (int i=0; i<FIFO_SIZE; i++) write_fifo(push_data_t'{rank_data: 30+i, default:'0});
        @(negedge clk);
        assert(buf_full);
        rw_fifo(push_data_t'{rank_data: 97, default:'0}); // Invoke the new task.
        repeat(2) @(negedge clk);
        assert(buf_full) else $error("TEST 6 FAILED: FIFO should remain full.");
        $display("TEST 6 PASSED: FIFO remained full after R/W on full.");
        for (int i=0; i<FIFO_SIZE; i++) read_fifo();
        repeat(5) @(negedge clk);

        // --- TEST 7: CRITICAL - Simultaneous R/W on an EMPTY FIFO ---
        $display("\n--- TEST 7: Simultaneous R/W on an EMPTY FIFO (Refactored) ---");
        assert(buf_empty);
        rw_fifo(push_data_t'{rank_data: 96, default:'0}); // Invoke the new task.
        repeat(5) @(negedge clk);
        assert(buf_empty) else $error("TEST 7 FAILED: FIFO should be empty again.");
        $display("TEST 7 PASSED: FIFO is empty after R/W on empty.");
        repeat(10) @(negedge clk);

        // --- Final Check ---
        $display("\nAll tests complete. Final check...");
        if (scoreboard.size() != 0) $error("FINAL CHECK FAILED: Scoreboard is not empty! Size: %0d", scoreboard.size());
        else $display("FINAL CHECK PASSED: Scoreboard is empty.");
        $finish;
    end

    // Data-checking logic (unchanged)
    logic rd_en_d1, wr_en_d1, buf_empty_d1;
    always_ff @(posedge clk) begin
        rd_en_d1 <= rd_en;
        wr_en_d1 <= wr_en;
        buf_empty_d1 <= buf_empty;
    end

    always @(posedge clk) begin
        if (rd_en_d1 && (!buf_empty_d1 || (buf_empty_d1 && wr_en_d1))) begin
            if (scoreboard.size() == 0) begin
                $error("[%0t] FATAL: Read from DUT, but scoreboard is empty!", $time);
            end else begin
                automatic push_data_t expected_data = scoreboard.pop_front();
                assert(buf_out == expected_data)
                    else $error("[%0t] MISMATCH! Expected: %p, Got: %p", $time, expected_data, buf_out);
                $display("[%0t] INFO: Correctly read data: %p", $time, buf_out);
            end
        end
    end

endmodule
