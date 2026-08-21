`timescale 1ns/1ps
`include "typedefs.svh"
// Ensure that PUSH_LB.sv is also added to the Vivado project's source list.
// `include` performs only textual inclusion and does not replace adding a source file to the project.

module top_PUSH_LB (
    input  logic i_clk,
    input  logic i_rstn,
    // Single-bit output used to prevent the logic from being optimized away
    output logic o_check
);

    // --- Parameters ---
    localparam int unsigned B         = 8;
    localparam int unsigned CNTW      = 6;
    localparam int unsigned FIFO_NUM  = 16;
    localparam int unsigned FIFO_SIZE = 8;
    
    // --- Internal signals ---
    logic         dut_push;
    push_data_t   dut_push_data;
    logic         dut_o_push;
    push_data_t   dut_o_push_data;

    logic                 dut_update_borders;
    logic [RKW - 1:0]     dut_borders;
    logic                 dut_upload_cnt;
    logic [CNTW-1:0]      dut_o_cnt;

    // --- 1. Efficiently generate 8-bit input data with an LFSR ---
    logic [7:0] lfsr_reg; // 8-bit LFSR state register

    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            dut_push   <= 1'b0;
            lfsr_reg   <= 8'hA5; // Nonzero 8-bit initial value
        end else begin
            dut_push   <= 1'b1;
            // Shift and calculate the new feedback bit from the taps.
            // Taps [7, 6, 5, 4] are a common choice for a maximal-length 8-bit LFSR.
            lfsr_reg <= {lfsr_reg[6:0], lfsr_reg[7] ^ lfsr_reg[6] ^ lfsr_reg[5] ^ lfsr_reg[4]};
        end
    end

    // Drive the 8-bit dut_push_data from the LFSR output.
    assign dut_push_data = lfsr_reg;

    logic [7:0] stimulus_cnt;
    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            stimulus_cnt       <= '0;
            dut_borders        <= '0;
            dut_update_borders <= 1'b0;
            dut_upload_cnt     <= 1'b0;
        end else begin
            stimulus_cnt       <= stimulus_cnt + 1;
            dut_borders        <= dut_borders + 1; // Keep changing the value to exercise the logic.
            dut_update_borders <= (stimulus_cnt == 8'd10); // Generate a periodic one-cycle pulse.
            dut_upload_cnt     <= (stimulus_cnt == 8'd50); // Generate another periodic pulse at a different offset.
        end
    end

    // --- 2. Instantiate the PUSH_LB DUT ---
    PUSH_LB #(
        .B         (B),
        .CNTW      (CNTW),
        .FIFO_NUM  (FIFO_NUM),
        .FIFO_SIZE (FIFO_SIZE)
    ) dut_inst (
        .i_clk       (i_clk),
        .i_rstn      (i_rstn),
        .i_push      (dut_push),
        .i_push_data (dut_push_data),

        .i_update_borders (dut_update_borders),
        .i_borders        (dut_borders),
        .i_upload_cnt     (dut_upload_cnt),
        .o_cnt            (dut_o_cnt),

        .o_push      (dut_o_push),
        .o_push_data (dut_o_push_data)
    );

    // --- 3. Output-data consumer ---
    // Continuously XOR output data into a register to form a checksum.
    // This makes every output-data bit affect the register and preserves all related logic.
    push_data_t   checksum_reg;

    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            checksum_reg <= '0;
        end else begin
            // Accumulate the XOR when the DUT output is valid.
            if (dut_o_push) begin
                checksum_reg <= checksum_reg ^ dut_o_push_data;
            end
        end
    end

    logic [CNTW-1:0] cnt_checksum_reg;
    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            cnt_checksum_reg <= '0;
        end else begin
            // o_cnt has no accompanying valid signal, so accumulate it directly.
            // Its nonzero value during uploads changes the checksum.
            cnt_checksum_reg <= cnt_checksum_reg ^ dut_o_cnt;
        end
    end

    // --- 4. Connect the top-level output ---
     // Reduce and XOR both checksums so that both major DUT output paths are preserved.
    assign o_check = |checksum_reg ^ |cnt_checksum_reg;

endmodule
