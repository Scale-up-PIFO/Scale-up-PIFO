`timescale 1ns/1ps
`include "typedefs.svh"

module RR_LB #(
  parameter int unsigned B     = 16,  // Number of buckets (16 or 32 recommended)
  parameter int unsigned CNTW  = 16,  // Counter width
  parameter int unsigned FIFO_NUM     = 4
) (
  input  logic  i_clk,
  input  logic  i_rstn,

  // Inputs
  input  logic  i_push,
  input  push_data_t  i_push_data,

  input logic i_update_borders,
  input logic [RKW-1:0] i_borders,

  input logic  i_upload_cnt,

  // Outputs
  output logic  o_push,
  output push_data_t o_push_data,
  
  output logic [CNTW-1:0] o_cnt,

  output logic [$clog2(FIFO_NUM)-1:0] o_fifo_id
);

  // ------------------------------------------
  // Dynamically updatable borders
  // ------------------------------------------
  logic [RKW-1:0] borders_q [2][B]; // Two border-register banks, indexed by 0 and 1
  logic           active_set_q;   // Selects the active borders_q bank

  enum logic {IDLE, UP} update_state_q, upload_state_q;
  logic [$clog2(B)-1:0]     update_idx_q, upload_idx_q;

  // Initialize on reset and support run-time updates.
  always_ff @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
      // Initialize both border-register banks.
      for (int unsigned set = 0; set < 2; set++) begin
        for (int unsigned i = 0; i < B; i++) begin
          if (i < B - 1) begin
            borders_q[set][i] <= (i << 12) | 32'hFFF;
          end else begin
            borders_q[set][i] <= 32'h0fff_ffff;
          end
        end
      end
      // Reset the active-bank pointer and update state machine.
      active_set_q   <= 1'b0; // Bank 0 is active by default.
      update_state_q <= IDLE;
      update_idx_q   <= '0;

    end else begin
      // State-machine-driven serial update logic.
      case (update_state_q)
        IDLE: begin
          // Start a B-cycle update when i_update_borders is asserted.
          if (i_update_borders) begin
            update_state_q <= UP;
            update_idx_q   <= 0;
          end
        end
        UP: begin
          // Always write to the inactive bank (!active_set_q).
          borders_q[!active_set_q][update_idx_q] <= i_borders;
          if (update_idx_q == B - 1) begin
            update_state_q <= IDLE;
            update_idx_q   <= '0;
            // Atomically activate the bank that has just been updated.
            active_set_q   <= !active_set_q; 
          end else begin
            update_idx_q <= update_idx_q + 1;
          end
        end
      endcase
    end
  end

  // ------------------------------------------
  // Counter-upload logic
  // ------------------------------------------

  logic [CNTW-1:0] cnt_q [B];

  always_ff @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
      upload_state_q <= IDLE;
      upload_idx_q   <= '0;
    end else begin
      case (upload_state_q)
        IDLE: begin
          if (i_upload_cnt) begin
            upload_state_q <= UP;
            upload_idx_q   <= '0;
          end
        end
        UP: begin
          // Clear the reported counter's high bits while preserving its low bits.
          if (upload_idx_q == B - 1) begin
            upload_state_q <= IDLE;
          end else begin
            upload_idx_q <= upload_idx_q + 1;
          end
        end
      endcase
    end
  end

  // ------------------------------------------
  // S0a: parallel comparators and pipeline registers
  // ------------------------------------------
  logic [B-1:0] cmp_hit;
  logic [B-1:0] cmp_hit_q;
  push_data_t data_s0_q;
  logic vld_s0_q;
  logic [RKW-1:0] active_borders [B];

  assign active_borders = borders_q[active_set_q];

  genvar k;
  generate
    for (k=0; k<B; k++) begin : g_cmp
      assign cmp_hit[k] = (i_push_data.rank_data <= active_borders[k]);
    end
  endgenerate

  always_ff @(posedge i_clk or negedge i_rstn) begin
      if (!i_rstn) begin
          cmp_hit_q <= '0;
          data_s0_q <= '0;
          vld_s0_q  <= 1'b0;
      end else begin
          cmp_hit_q <= cmp_hit;
          data_s0_q <= i_push_data;
          vld_s0_q  <= i_push;
      end
  end

  // ------------------------------------------
  // S0b: priority encoder and pipeline registers
  // ------------------------------------------
  logic [$clog2(B)-1:0] idx_pe;
  logic [$clog2(B)-1:0] idx_s0_q;
  push_data_t data_s0b_q;
  logic vld_s0b_q;

  always_comb begin
      idx_pe = B-1;
      for (int unsigned j=0; j<B; j++) begin
          if (cmp_hit_q[j]) begin
              idx_pe = j[$clog2(B)-1:0];
              break;
          end
      end
  end

  always_ff @(posedge i_clk or negedge i_rstn) begin
      if (!i_rstn) begin
          idx_s0_q   <= '0;
          data_s0b_q <= '0;
          vld_s0b_q  <= 1'b0;
      end else begin
          idx_s0_q   <= idx_pe;
          data_s0b_q <= data_s0_q;
          vld_s0b_q  <= vld_s0_q;
      end
  end

  // ------------------------------------------
  // S1: counter read and forwarding
  // ------------------------------------------
  logic vld_s1_q;
  push_data_t data_s1_q;
  logic [$clog2(B)-1:0] idx_s1_q;
  logic [CNTW-1:0]      cnt_rd_s1;

  // Forward the previous cycle's writeback value.
  logic wb_vld_q;
  logic [$clog2(B)-1:0] wb_idx_q;
  logic [CNTW-1:0]      wb_val_q;

  always_comb begin
      cnt_rd_s1 = cnt_q[idx_s1_q];
      if (wb_vld_q && (idx_s1_q == wb_idx_q)) begin
          cnt_rd_s1 = wb_val_q; // RAW forwarding
      end
  end

  always_ff @(posedge i_clk or negedge i_rstn) begin
      if (!i_rstn) begin
          vld_s1_q  <= 1'b0;
          data_s1_q <= '0;
          idx_s1_q  <= '0;
      end else begin
          vld_s1_q  <= vld_s0b_q;
          data_s1_q <= data_s0b_q;
          idx_s1_q  <= idx_s0_q;
      end
  end

  // ------------------------------------------
  // S2: generate the FIFO ID and write back the counter
  // ------------------------------------------
  logic vld_s2_q;
  push_data_t data_s2_q;
  logic [$clog2(FIFO_NUM)-1:0]         id_s2;

  always_ff @(posedge i_clk or negedge i_rstn) begin
      if (!i_rstn) begin
          vld_s2_q  <= 1'b0;
          data_s2_q <= '0;
          id_s2     <= '0;
          wb_vld_q  <= '0;
          wb_idx_q  <= '0;
          wb_val_q  <= '0;
      end else begin
          vld_s2_q  <= vld_s1_q;
          data_s2_q <= data_s1_q;

          if (vld_s1_q) begin
              id_s2           <= cnt_rd_s1[$clog2(FIFO_NUM)-1:0];

              wb_vld_q        <= 1'b1;
              wb_idx_q        <= idx_s1_q;
              wb_val_q        <= cnt_rd_s1 + 1'b1;
          end else begin
              wb_vld_q        <= '0;
          end
      end
  end

  // ------------------------------------------
  // Counter array with unified write logic
  // ------------------------------------------
  always_ff @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
      for (integer i = 0; i < B; i++) begin
        cnt_q[i] <= '0;
      end
    end else begin
      if (upload_state_q == UP && vld_s1_q) begin
        if(idx_s1_q == upload_idx_q) begin
          cnt_q[upload_idx_q] <= cnt_q[upload_idx_q][$clog2(FIFO_NUM)-1:0] + 1;
        end else begin
          cnt_q[upload_idx_q] <= cnt_q[upload_idx_q][$clog2(FIFO_NUM)-1:0];
          cnt_q[idx_s1_q] <= cnt_rd_s1 + 1'b1;
        end
      end else if (upload_state_q == UP) begin
        cnt_q[upload_idx_q] <= cnt_q[upload_idx_q][$clog2(FIFO_NUM)-1:0];
      end else if (vld_s1_q) begin
        cnt_q[idx_s1_q] <= cnt_rd_s1 + 1'b1;
      end
    end
  end

  // ------------------------------------------
  // Outputs
  // ------------------------------------------
  assign o_push      = vld_s2_q;
  assign o_push_data = data_s2_q;
  assign o_fifo_id   = id_s2;
  assign o_cnt       = (upload_state_q == UP) ? {cnt_q[upload_idx_q][CNTW-1:$clog2(FIFO_NUM)], {$clog2(FIFO_NUM){1'b0}}} : '0;

endmodule
