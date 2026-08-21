`timescale 1ns/1ps

// =============================================================================
// frequency_test_top.v (version 2 using an XOR checksum)
// Wrapper for measuring the maximum frequency of the interval_border_adjuster core.
// It removes I/O bottlenecks by generating inputs and consuming outputs inside the FPGA.
// The XOR checksum prevents the output logic from being optimized away.
// =============================================================================

module top_border_adjuster (
    input  logic clk,    // FPGA global clock
    input  logic rst_n,  // Active-low FPGA reset
    output logic o_check_sum     // Drives the LED with the output-bus checksum
);

    // --- DUT parameters ---
    localparam NUM_LB          = 1;
    localparam NUM_PIFO        = 1;
    localparam MAX_INTERVALS   = 8;
    localparam COUNT_W         = 4;
    localparam BORDER_W        = 4;

    // --- Internal signals ---
    logic  dut_start;
    logic dut_busy;
    logic dut_done;
    logic [COUNT_W-1:0] dut_cnt_in_data;
    logic [BORDER_W-1:0] dut_border_out;
    logic                dut_border_out_valid;
    
    // Register that holds the checksum result
    logic [BORDER_W-1:0] check_sum_reg;


    // =========================================================================
    // 1. Instantiate the DUT.
    // =========================================================================
    interval_border_adjuster #(
        .NUM_LB        (NUM_LB),
        .NUM_PIFO      (NUM_PIFO),
        .MAX_INTERVALS (MAX_INTERVALS),
        .COUNT_W       (COUNT_W),
        .BORDER_W      (BORDER_W)
    ) dut_inst (
        .clk               (clk),
        .rst_n             (rst_n),
        .start             (dut_start),
        .cnt_in_data       (dut_cnt_in_data),
        .border_out       (dut_border_out),
        .border_out_valid (dut_border_out_valid),
        .busy              (dut_busy),
        .done              (dut_done)
    );

    // =========================================================================
    // 2. Generate input stimulus internally.
    // =========================================================================

    // 2.1 Automatic start-signal generator
    logic [1:0] start_sm_state;
    localparam S_IDLE  = 2'b00, S_START = 2'b01, S_WAIT  = 2'b10;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_sm_state <= S_IDLE;
            dut_start      <= 1'b0;
        end else begin
            dut_start <= 1'b0;
            case (start_sm_state)
                S_IDLE:  start_sm_state <= S_START;
                S_START: begin dut_start <= 1'b1; start_sm_state <= S_WAIT; end
                S_WAIT:  if (dut_done) start_sm_state <= S_IDLE;
                default: start_sm_state <= S_IDLE;
            endcase
        end
    end

    // 2.2 Pseudorandom data generator (64-bit LFSR) for cnt_in_data
    logic [COUNT_W-1:0] lfsr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) lfsr <= {COUNT_W{1'b1}}; // Initialize to all ones.
        else if (dut_busy) begin // Generate data continuously while the DUT is busy.
            // Simple 16-bit LFSR feedback logic
            lfsr <= {lfsr[COUNT_W-2:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        end
    end
    assign dut_cnt_in_data = lfsr;


    // =========================================================================
    // 3. Consume outputs internally.
    // =========================================================================
    
    // 3.1 Accumulate an XOR checksum while the DUT's streaming output is valid.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            check_sum_reg <= '0;
        end else begin
            // Clear the checksum after each completed task to prepare for the next run.
            if (dut_done) begin
                check_sum_reg <= '0;
            // Accumulate the XOR while border_out_valid is asserted.
            end else if (dut_border_out_valid) begin
                check_sum_reg <= check_sum_reg ^ dut_border_out; 
            end
        end
    end

    // 3.2 Connect the final checksum result to the physical LED pin.
    assign o_check_sum = |check_sum_reg;

endmodule
