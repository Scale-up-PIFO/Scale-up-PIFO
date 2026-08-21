`timescale 1ns/1ps
`include "typedefs.svh"

module PUSH_LB #(
    // RR_LB parameters
    parameter int unsigned B          = 16,  // Number of buckets
    parameter int unsigned CNTW       = 16,  // Counter width

    // PUSH_LB parameters
    parameter int unsigned FIFO_NUM   = 4,   // Number of internal FIFOs; must be a power of two
    parameter int unsigned FIFO_SIZE  = 16    // Depth of each FIFO
) (
    input  logic         i_clk,
    input  logic         i_rstn,

    // Input interface
    input  logic         i_push,
    input  push_data_t   i_push_data,

    input  logic               i_update_borders,
    input  logic [RKW - 1:0] i_borders,

    input  logic               i_upload_cnt,

`ifndef SYNTHESIS
    output logic         o_debug_fifo_id_valid,
    output logic [$clog2(FIFO_NUM)-1:0] o_debug_fifo_id,
    output push_data_t   o_debug_push_data,  
`endif

    // Output interface (two-cycle latency from read arbitration)
    output logic         o_push,
    output push_data_t   o_push_data,

    output logic [CNTW-1:0]      o_cnt
);

    // Check at elaboration time that FIFO_NUM is a power of two.
    initial begin
        if ((FIFO_NUM & (FIFO_NUM - 1)) != 0) begin
            $fatal(0, "PUSH_LB Error: FIFO_NUM parameter must be a power of 2.");
        end
    end

    // --- Internal signals ---

    // RR_LB outputs
    logic                           rrlb_push;
    push_data_t                     rrlb_push_data;
    logic [$clog2(FIFO_NUM)-1:0]    rrlb_fifo_id;

    // FIFO-array control and status signals
    logic [FIFO_NUM-1:0]            fifo_wr_en;
    logic [FIFO_NUM-1:0]            fifo_rd_en;
    logic [FIFO_NUM-1:0]            fifo_empty;
    logic [FIFO_NUM-1:0]            fifo_full; // Available for RR_LB backpressure, which is not implemented here
    push_data_t [FIFO_NUM-1:0]      fifo_buf_out;

    // Read-arbiter signals
    logic [$clog2(FIFO_NUM)-1:0]    pop_ptr;
    logic [FIFO_NUM-1:0]            pop_grant;      // One-hot read request from the arbiter
    logic                           pop_valid;      // Indicates that the selected read is valid

    // Output pipeline registers for the two-cycle latency
    logic                           pop_valid_d1;
    logic [FIFO_NUM-1:0]            pop_grant_d1;
    push_data_t                     o_push_data_d1, selected_data;


    // --- 1. RR_LB instance ---
    // Distribute input data among FIFO IDs.
    RR_LB #(
        .B          (B),
        .CNTW       (CNTW),
        .FIFO_NUM   (FIFO_NUM)
    ) inst_RR_LB (
        .i_clk        (i_clk),
        .i_rstn       (i_rstn),
        .i_push       (i_push),
        .i_push_data  (i_push_data),

        .i_update_borders (i_update_borders),
        .i_borders        (i_borders),
        .i_upload_cnt     (i_upload_cnt),
        .o_cnt            (o_cnt),

        .o_push       (rrlb_push),
        .o_push_data  (rrlb_push_data),
        .o_fifo_id    (rrlb_fifo_id)
    );


    // --- 2. FIFO write logic ---
    // Decode RR_LB's fifo_id output into one-hot write enables.
    // RR_LB has a two-cycle latency, so rrlb_push, rrlb_push_data, and rrlb_fifo_id are aligned.
    assign fifo_wr_en = (1'b1 << rrlb_fifo_id) & {FIFO_NUM{rrlb_push}};


    // --- 3. FIFO-array instances ---
    // Generate FIFO_NUM PUSH_FIFO instances.
    genvar i;
    generate
        for (i = 0; i < FIFO_NUM; i = i + 1) begin : gen_fifos
            PUSH_FIFO #(
                .FIFO_SIZE(FIFO_SIZE)
            ) inst_PUSH_FIFO (
                .clk          (i_clk),
                .rst          (~i_rstn), // PUSH_FIFO uses an active-high reset.
                .wr_en        (fifo_wr_en[i]),
                .rd_en        (fifo_rd_en[i]),
                .buf_in       (rrlb_push_data),
                .buf_out      (fifo_buf_out[i]),
                .buf_empty    (fifo_empty[i]),
                .buf_full     (fifo_full[i])
            );
        end
    endgenerate


    // --- 4. Simplified FIFO read arbiter ---
    // By design, when data is available, the FIFO selected by round robin is nonempty.
    // No search is needed; select and check the FIFO addressed by pop_ptr.
    assign pop_grant = 1'b1 << pop_ptr;
    assign pop_valid = (!fifo_empty[pop_ptr]) || (fifo_wr_en[pop_ptr]); // Valid when the selected FIFO is nonempty or is being written.
    assign fifo_rd_en = pop_grant; // Drive the read enables from the arbiter grant.

    // Update the round-robin pointer.
    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            pop_ptr <= '0;
        end else begin // Advance to the next FIFO every cycle.
            pop_ptr <= pop_ptr + 1; // FIFO_NUM is a power of two, so the pointer wraps automatically.
        end
    end


    // --- 5. Output pipeline ---
    // The read path has a fixed two-cycle latency to meet timing:
    // 1. FIFO read latency (one cycle) from rd_en to valid fifo_buf_out data.
    // 2. Data selection and registration (one cycle) from fifo_buf_out to the output port.



    // Cycle 1: register the arbitration result to align it with the next cycle's FIFO output.
    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            pop_valid_d1 <= 1'b0;
            pop_grant_d1 <= '0;
        end else begin
            pop_valid_d1 <= pop_valid;
            pop_grant_d1 <= pop_grant;
        end
    end

    // Cycle 2, step A: select data combinationally.
    // Use the one-cycle-delayed grant to select from the ready fifo_buf_out data.
    // pop_grant_d1 and fifo_buf_out are aligned here.
    always_comb begin
        selected_data = '0; // Default value
        for (int k=0; k<FIFO_NUM; k=k+1) begin
            if(pop_grant_d1[k]) begin
                selected_data = fifo_buf_out[k];
            end
        end
    end

    // Cycle 2, step B: register the selected data and valid bit at the outputs.
    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            o_push      <= 1'b0;
            o_push_data <= '0;
        end else begin
            o_push      <= pop_valid_d1;
            o_push_data <= selected_data;
        end
    end

`ifndef SYNTHESIS
    // --- Debug-port connections ---
    assign o_debug_fifo_id_valid = rrlb_push;
    assign o_debug_fifo_id       = rrlb_fifo_id;
    assign o_debug_push_data     = rrlb_push_data;
`endif

endmodule
