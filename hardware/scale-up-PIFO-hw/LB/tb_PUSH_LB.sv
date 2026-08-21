`timescale 1ns/1ps
`include "typedefs.svh"

//
// Testbench for PUSH_LB module
//
module tb_PUSH_LB;

    // --- Parameters ---
    // These parameters should match the PUSH_LB module defaults.
    localparam int B           = 16;
    localparam int CNTW        = 16;
    localparam int FIFO_NUM    = 4;
    localparam int FIFO_SIZE   = 8;
    localparam int CLK_PERIOD  = 10; // Clock period: 10 ns (100 MHz)

    localparam logic [RKW-1:0] bounds [B] = '{
      32'h0000_0fff,
      32'h0000_1fff,
      32'h0000_2fff,
      32'h0000_3fff,
      32'h0000_4fff,
      32'h0000_5fff,
      32'h0000_6fff,
      32'h0000_7fff,
      32'h0000_8fff,
      32'h0000_9fff,
      32'h0000_afff,
      32'h0000_bfff,
      32'h0000_cfff,
      32'h0000_dfff,
      32'h0000_efff,
      32'h0fff_ffff
  };

    // --- Signal declarations ---
    logic clk;
    logic rstn;

    // DUT interface signals
    logic i_push;
    push_data_t i_push_data;
    logic o_push;
    push_data_t o_push_data;

    // Signals connected to the DUT debug ports
    logic debug_fifo_id_valid;
    logic [$clog2(FIFO_NUM)-1:0] debug_fifo_id;
    push_data_t debug_push_data;


    // --- Scoreboard and verification logic ---
    // Use an associative-array scoreboard to handle packet reordering.
    // Key: push_data_t (the complete packet)
    // Value: int (the expected count for that packet)
    int scoreboard[push_data_t];
    integer push_count = 0;
    integer pop_count = 0;

    // --- DUT instance ---
    PUSH_LB #(
        .B(B),
        .CNTW(CNTW),
        .FIFO_NUM(FIFO_NUM),
        .FIFO_SIZE(FIFO_SIZE)
    ) dut (
        .i_clk(clk),
        .i_rstn(rstn),
        .i_push(i_push),
        .i_push_data(i_push_data),
`ifndef SYNTHESIS
        .o_debug_fifo_id_valid(debug_fifo_id_valid),
        .o_debug_fifo_id(debug_fifo_id),
        .o_debug_push_data(debug_push_data),
`endif
        .o_push(o_push),
        .o_push_data(o_push_data)
    );

    // --- Clock generation ---
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // --- Main test sequence ---
    initial begin
        // 1. Initialize and reset.
        initialize_signals();
        apply_reset();
        
        $display("[%0t] INFO: Test sequence started.", $time);

        // // --- Scenario 1: basic distribution test ---
        // // Purpose: send FIFO_NUM packets with the same rank_data.
        // // Expected: RR_LB increments its counter and distributes the four packets to FIFOs 0, 1, 2, and 3.
        // //           Because read arbitration starts at 0, they should be read in FIFO order 0, 1, 2, and 3.
        // $display("[%0t] INFO: Starting Scenario 1: Basic Distribution", $time);
        // for (int i = 0; i < FIFO_NUM; i++) begin
        //     // rank_data = 0x100 maps to bucket 0; meta_data distinguishes the packets.
        //     push_packet(16'(i), 32'h0000_0100);
        // end
        // wait_cycles(FIFO_NUM * 2);

        // // --- Scenario 2: random traffic with gaps ---
        // // Purpose: model more realistic traffic with random rank_data values and transmission gaps.
        // // Expected: every transmitted packet should eventually be received correctly at the output.
        // $display("[%0t] INFO: Starting Scenario 2: Randomized Traffic with Gaps", $time);
        // for (int i = 0; i < 2 * FIFO_NUM * 16; i++) begin
        //     push_packet(16'(i+100), $urandom_range(32'h00ff_ffff, 0));
        //     wait_cycles($urandom_range(4, 0)); // Wait for a random 0 to 4 cycles.
        // end
        // wait_cycles(10);

        // // --- Scenario 3: stress test that fills every FIFO ---
        // // Purpose: send many consecutive packets to one bucket to test the system under high load.
        // // Expected: RR_LB's round-robin distribution spreads the packets evenly across all FIFOs.
        // //           Send enough packets to fill every FIFO.
        // $display("[%0t] INFO: Starting Scenario 3: Stress Test (Fill all FIFOs)", $time);
        // for (int i = 0; i < FIFO_NUM * FIFO_SIZE; i++) begin
        //     // rank_data = 0x2888 maps to bucket 2.
        //     push_packet(16'(i+200), 32'h0000_2888);
        // end

        // --- Scenario 4: generate packets for every priority interval ---
        $display("[%0t] INFO: Starting Scenario 4: Per-Bucket Packet Generation", $time);
        begin
            logic [RKW-1:0] min_rank, max_rank;
            automatic int packet_meta_counter = 400; // Use a new meta_data base to avoid duplicates from earlier scenarios.

            for (int i = 0; i < B; i = i + 1) begin
                // Determine the rank_data range for the current bucket.
                max_rank = bounds[i];
                min_rank = (i == 0) ? 0 : bounds[i-1] + 1;

                $display("[%0t] INFO:   Testing Bucket %0d (rank_data range: [%h : %h])", $time, i, min_rank, max_rank);

                // Generate 4 * FIFO_NUM packets for the current bucket.
                for (int j = 0; j < 4 * FIFO_NUM; j = j + 1) begin
                    logic [RKW-1:0] random_rank;
                    // Generate a random rank_data value within the current bucket.
                    random_rank = $urandom_range(max_rank, min_rank);
                    push_packet(16'(packet_meta_counter), random_rank);
                    packet_meta_counter++;
                end
            end
        end
        
        // 2. Wait for all data to be processed.
        $display("[%0t] INFO: All stimulus sent. Draining the DUT for 200 cycles.", $time);
        wait_cycles(200); // Allow enough time for all packets to drain.

        // 3. Run the final checks.
        check_results();
        
        $display("[%0t] INFO: Test sequence finished.", $time);
        $finish;
    end

    // --- Task definitions ---

    // Initialize signals.
    task automatic initialize_signals;
        i_push = 0;
        i_push_data = '0;
        rstn = 1; // Reset is deasserted by default.
    endtask

    // Apply reset.
    task automatic apply_reset;
        rstn = 0; // Active-low reset
        repeat(5) @(posedge clk);
        rstn = 1;
        @(posedge clk);
        $display("[%0t] INFO: System reset released.", $time);
    endtask

    // Wait for the specified number of clock cycles.
    task automatic wait_cycles(input int num_cycles);
        if (num_cycles > 0) begin
            repeat(num_cycles) @(posedge clk);
        end
    endtask

    // Send one packet.
    task automatic push_packet(input logic [MTW-1:0] meta, input logic [RKW-1:0] rank);
        @(negedge clk);
        i_push = 1;
        i_push_data = {meta, rank};
        
        // Print the input packet.
        $display("[%0t] INFO: --> Pushing packet: meta=%0d, rank=%h", $time, meta, rank);
        
        scoreboard[i_push_data]++;
        push_count++;
        
        @(negedge clk);
        i_push = 0;
    endtask

    // --- Monitors and checkers ---

    // Monitor the DUT output.
    // Monitor which FIFO receives each packet.
    always @(posedge clk) begin
        if (debug_fifo_id_valid) begin
            $display("[%0t] INFO:     internal write to FIFO #%0d, meta=%0d, rank=%h, data=%h", $time, debug_fifo_id, debug_push_data.meta_data, debug_push_data.rank_data, debug_push_data);
        end
    end

    // Monitor the DUT output.
    always @(posedge clk) begin
        if (o_push) begin
            // Print the output packet.
            $display("[%0t] INFO: <-- Popping packet:  meta=%0d, rank=%h", $time, o_push_data.meta_data, o_push_data.rank_data);
            pop_count++;
            if (scoreboard.exists(o_push_data) && scoreboard[o_push_data] > 0) begin
                scoreboard[o_push_data]--;
            end else begin
                $error("[%0t] FATAL: Popped an unexpected or duplicate packet! Data: %p", $time, o_push_data);
            end
        end
    end

    // Final result checks
    task automatic check_results;
        logic test_passed = 1;
        int remaining_packets = 0;
        
        $display("--- FINAL CHECK ---");
        $display("Total packets pushed: %0d", push_count);
        $display("Total packets popped: %0d", pop_count);

        if (push_count != pop_count) begin
            $error("Packet count mismatch! Pushed %0d, but only popped %0d.", push_count, pop_count);
            test_passed = 0;
        end

        // Scan the scoreboard for packets that were never matched.
        foreach (scoreboard[data]) begin
            if (scoreboard[data] != 0) begin
                remaining_packets += scoreboard[data];
                $error("Packet was pushed but never popped (or popped wrong number of times). Data: %p, Remaining Count: %0d", data, scoreboard[data]);
                test_passed = 0;
            end
        end
        
        if (remaining_packets > 0) begin
            $error("%0d packets in total were lost.", remaining_packets);
        end

        if (test_passed) begin
            $display("--- TEST PASSED ---");
        end else begin
            $display("--- TEST FAILED ---");
        end
    endtask

endmodule
