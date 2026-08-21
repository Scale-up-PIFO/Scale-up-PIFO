`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// interval_adjuster_min.v  (patched: DECAY/STATS INIT + last_word_now
//                           + merge_with_nxt + fixed S_SPLIT_SHIFTB/SHIFTC)
// Pure Verilog-2001, synthesizable, minimal I/O
// -----------------------------------------------------------------------------

module interval_border_adjuster #(
    parameter integer NUM_LB        = 2,
    parameter integer NUM_PIFO      = 3,
    parameter integer MAX_INTERVALS = 16,
    parameter integer COUNT_W       = 64,
    parameter integer BORDER_W      = 64
)(
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        start,
    input  wire [COUNT_W-1:0]          cnt_in_data,
    output reg [BORDER_W-1:0]          border_out,
    output reg                         border_out_valid,
    output reg                         busy,
    output reg                         done
);

    localparam [31:0] INIT_NUM_INTERVALS = 8;

    localparam [BORDER_W-1:0] INIT_BORDER0  = 64'd0;
    localparam [BORDER_W-1:0] INIT_BORDER1  = 64'd100;
    localparam [BORDER_W-1:0] INIT_BORDER2  = 64'd200;
    localparam [BORDER_W-1:0] INIT_BORDER3  = 64'd300;
    localparam [BORDER_W-1:0] INIT_BORDER4  = 64'd400;
    localparam [BORDER_W-1:0] INIT_BORDER5  = 64'd500;
    localparam [BORDER_W-1:0] INIT_BORDER6  = 64'd600;
    localparam [BORDER_W-1:0] INIT_BORDER7  = 64'd700;


    localparam [BORDER_W-1:0] INIT_BCNT0 = 64'd30;
    localparam [BORDER_W-1:0] INIT_BCNT1 = 64'd0;
    localparam [BORDER_W-1:0] INIT_BCNT2 = 64'd10;
    localparam [BORDER_W-1:0] INIT_BCNT3 = 64'd20;
    localparam [BORDER_W-1:0] INIT_BCNT4 = 64'd1130;
    localparam [BORDER_W-1:0] INIT_BCNT5 = 64'd20;
    localparam [BORDER_W-1:0] INIT_BCNT6 = 64'd20;
    localparam [BORDER_W-1:0] INIT_BCNT7 = 64'd20;

    reg [31:0]             num_intervals;
    reg [BORDER_W-1:0]     borders   [0:MAX_INTERVALS];
    reg [BORDER_W-1:0]     bcnt      [0:MAX_INTERVALS-1];
    reg [BORDER_W-1:0]     curr      [0:MAX_INTERVALS-1];

    integer i;
    reg [31:0] lb_idx, pf_idx, iv_idx;
    reg [31:0] out_idx, shift_idx;

    reg [BORDER_W-1:0] total_sum, max_val, min_val;
    reg [31:0]         max_idx,  min_idx;

    reg [31:0] act_num_intervals;
    reg [31:0] merge_with, merge_start, merge_end, max2_idx;
    reg [BORDER_W-1:0] mid_bdr, split_left, split_right;

    // Combinational merge-neighbor selection and associated interval bounds
    reg [31:0] merge_with_nxt, merge_start_nxt, merge_end_nxt;

    localparam S_WAIT_START    = 0,
               S_CLR_CURR      = 1,
               S_ACCUM         = 2,
               S_DECAY_UPDATE  = 3,
               S_STATS         = 4,
               S_CHECK         = 5,
               S_MERGE_PREP    = 6,
               S_MERGE_SHIFTB  = 7,
               S_MERGE_SHIFTC  = 8,
               S_SPLIT_FINDMAX = 9,
               S_SPLIT_SHIFTB  = 10,
               S_SPLIT_SHIFTC  = 11,
               S_PACK_OUT      = 12,
               S_DONE          = 13,
               S_DECAY_INIT    = 14,
               S_STATS_INIT    = 15,
               S_STREAM_OUT    = 16;

    reg [4:0] state, nstate;

    wire last_word_now =
        (iv_idx == (num_intervals - 1)) &&
        (pf_idx == (NUM_PIFO   - 1)) &&
        (lb_idx == (NUM_LB     - 1));

    // --- Select the neighboring interval to merge ---
    always @(*) begin
      merge_with_nxt  = 32'hFFFF_FFFF;
      merge_start_nxt = 32'd0;
      merge_end_nxt   = 32'd0;

      if (num_intervals >= 2) begin
        if (min_idx > 0 && (min_idx + 1) < act_num_intervals) begin
          merge_with_nxt = (bcnt[min_idx-1] <= bcnt[min_idx+1]) ? (min_idx-1) : (min_idx+1);
        end else if (min_idx > 0) begin
          merge_with_nxt = min_idx - 1;
        end else if ((min_idx + 1) < act_num_intervals) begin
          merge_with_nxt = min_idx + 1;
        end

        if (merge_with_nxt != 32'hFFFF_FFFF) begin
          if (min_idx < merge_with_nxt) begin
            merge_start_nxt = min_idx;
            merge_end_nxt   = merge_with_nxt;
          end else begin
            merge_start_nxt = merge_with_nxt;
            merge_end_nxt   = min_idx;
          end
        end
      end
    end

    // --- Sequential state and data-path logic ---
    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        num_intervals <= (INIT_NUM_INTERVALS < 2) ? 2 :
                         ((INIT_NUM_INTERVALS > MAX_INTERVALS) ? MAX_INTERVALS : INIT_NUM_INTERVALS);

        for (i=0;i<MAX_INTERVALS;i=i+1) begin
          case (i)
            0: borders[i] <= INIT_BORDER0;
            1: borders[i] <= INIT_BORDER1;
            2: borders[i] <= INIT_BORDER2;
            3: borders[i] <= INIT_BORDER3;
            4: borders[i] <= INIT_BORDER4;
            5: borders[i] <= INIT_BORDER5;
            6: borders[i] <= INIT_BORDER6;
            7: borders[i] <= INIT_BORDER7;
            default: borders[i] <= {BORDER_W{1'b0}};
          endcase
        end

        for (i=0;i<MAX_INTERVALS;i=i+1) begin
          case (i)
            0: bcnt[i] <= INIT_BCNT0;
            1: bcnt[i] <= INIT_BCNT1;
            2: bcnt[i] <= INIT_BCNT2;
            3: bcnt[i] <= INIT_BCNT3;
            4: bcnt[i] <= INIT_BCNT4;
            5: bcnt[i] <= INIT_BCNT5;
            6: bcnt[i] <= INIT_BCNT6;
            7: bcnt[i] <= INIT_BCNT7;
            default: bcnt[i] <= {BORDER_W{1'b0}};
          endcase
          curr[i] <= {BORDER_W{1'b0}};
        end

        lb_idx <= 0; pf_idx <= 0; iv_idx <= 0; out_idx <= 0; shift_idx <= 0;
        total_sum <= 0; max_val <= 0; min_val <= {BORDER_W{1'b1}}; max_idx <= 0; min_idx <= 0;
        act_num_intervals <= 0; merge_with <= 32'hFFFF_FFFF; merge_start <= 0; merge_end <= 0; max2_idx <= 0;
        mid_bdr <= 0; split_left <= 0; split_right <= 0;
        state <= S_WAIT_START;
        border_out       <= {BORDER_W{1'b0}};
        border_out_valid <= 1'b0;
        busy <= 1'b0; done <= 1'b0;

      end else begin
        state <= nstate;
        done  <= 1'b0;

        case (state)
          S_WAIT_START: begin
            busy <= 1'b0;
            out_idx <= 0;
          end

          S_CLR_CURR: begin
            busy <= 1'b1;
            for (i=0;i<MAX_INTERVALS;i=i+1) curr[i] <= {BORDER_W{1'b0}};
            lb_idx <= 0; pf_idx <= 0; iv_idx <= 0;
          end

          S_ACCUM: begin
            curr[iv_idx] <= curr[iv_idx] + cnt_in_data;
            if (iv_idx + 1 < num_intervals) begin
              iv_idx <= iv_idx + 1;
            end else begin
              iv_idx <= 0;
              if (pf_idx + 1 < NUM_PIFO) begin
                pf_idx <= pf_idx + 1;
              end else begin
                pf_idx <= 0;
                if (lb_idx + 1 < NUM_LB) lb_idx <= lb_idx + 1; else lb_idx <= NUM_LB;
              end
            end
          end

          S_DECAY_INIT: begin
            iv_idx <= 0;
          end

          S_DECAY_UPDATE: begin
            if (iv_idx < num_intervals) begin
              bcnt[iv_idx] <= (bcnt[iv_idx] >> 1) + curr[iv_idx];
              iv_idx <= iv_idx + 1;
            end
          end

          S_STATS_INIT: begin
            total_sum <= 0;
            max_val   <= 0;
            min_val   <= {BORDER_W{1'b1}};
            max_idx   <= 0;
            min_idx   <= 0;
            iv_idx    <= 0;
          end

          S_STATS: begin
            if (iv_idx < num_intervals) begin
              total_sum <= total_sum + bcnt[iv_idx];
              if (bcnt[iv_idx] > max_val) begin max_val <= bcnt[iv_idx]; max_idx <= iv_idx; end
              if (bcnt[iv_idx] < min_val) begin min_val <= bcnt[iv_idx]; min_idx <= iv_idx; end
              iv_idx <= iv_idx + 1;
            end
          end

          S_CHECK: begin
            act_num_intervals <= num_intervals;
          end

          S_MERGE_PREP: begin
            merge_with  <= merge_with_nxt;
            merge_start <= merge_start_nxt;
            merge_end   <= merge_end_nxt;
            if (merge_with_nxt != 32'hFFFF_FFFF) begin
              bcnt[merge_start_nxt] <= bcnt[merge_start_nxt] + bcnt[merge_end_nxt];
              shift_idx <= merge_end_nxt; // Start removing the right boundary.
            end
          end

          S_MERGE_SHIFTB: begin
            if (shift_idx < act_num_intervals) begin
              borders[shift_idx] <= borders[shift_idx + 1];
              shift_idx <= shift_idx + 1;
            end else begin
              shift_idx <= merge_end; // Then remove bcnt[merge_end].
            end
          end

          S_MERGE_SHIFTC: begin
            if (shift_idx < (act_num_intervals - 1)) begin
              bcnt[shift_idx] <= bcnt[shift_idx + 1];
              shift_idx <= shift_idx + 1;
            end else begin
              act_num_intervals <= act_num_intervals - 1;
              iv_idx <= 0; max2_idx <= 0; max_val <= 0;
            end
          end

          S_SPLIT_FINDMAX: begin
            if (iv_idx < act_num_intervals) begin
              if (bcnt[iv_idx] >= max_val) begin max_val <= bcnt[iv_idx]; max2_idx <= iv_idx; end
              iv_idx <= iv_idx + 1;
            end else begin
              mid_bdr     <= (borders[max2_idx] + borders[max2_idx + 1]) >> 1;
              split_left  <= bcnt[max2_idx] >> 1;
              split_right <= bcnt[max2_idx] - (bcnt[max2_idx] >> 1);
              shift_idx   <= act_num_intervals + 1; // Start shifting borders to the right.
            end
          end

          // Wait until the right shift reaches max2_idx + 1 before inserting the border.
          S_SPLIT_SHIFTB: begin
            if (shift_idx > (max2_idx + 1)) begin
              borders[shift_idx] <= borders[shift_idx - 1];
              shift_idx <= shift_idx - 1;
            end else begin
              borders[max2_idx + 1] <= mid_bdr;
              shift_idx <= act_num_intervals; // Prepare to shift bcnt to the right.
            end
          end

          // Likewise, stay in this state until the counter shift is complete.
          S_SPLIT_SHIFTC: begin
            if (shift_idx > (max2_idx + 1)) begin
              bcnt[shift_idx] <= bcnt[shift_idx - 1];
              shift_idx <= shift_idx - 1;
            end else begin
              bcnt[max2_idx]     <= split_left;
              bcnt[max2_idx + 1] <= split_right;
              act_num_intervals  <= act_num_intervals + 1;
            end
          end

          S_PACK_OUT: begin
            // for (i=0;i<=MAX_INTERVALS;i=i+1)
            //   borders_out_bus[i*BORDER_W +: BORDER_W] <= borders[i];
            out_idx <= 1;
            border_out_valid <= 1'b0;
          end

          S_STREAM_OUT: begin
            if (out_idx <= MAX_INTERVALS) begin // Use MAX_INTERVALS instead of num_intervals.
                border_out <= borders[out_idx];
                out_idx <= out_idx + 1;
                border_out_valid <= 1'b1;
            end else begin
                border_out_valid <= 1'b0;
            end
        end

          S_DONE: begin
            busy <= 1'b0; done <= 1'b1;
          end
        endcase
      end
    end

    // --- Next-state logic: wait conditions for S_SPLIT_SHIFTB and S_SPLIT_SHIFTC
    always @(*) begin
      nstate = state;
      case (state)
        S_WAIT_START:    nstate = (start ? S_CLR_CURR : S_WAIT_START);
        S_CLR_CURR:      nstate = S_ACCUM;
        S_ACCUM:         nstate = last_word_now               ? S_DECAY_INIT   : S_ACCUM;
        S_DECAY_INIT:    nstate = S_DECAY_UPDATE;
        S_DECAY_UPDATE:  nstate = (iv_idx == num_intervals)   ? S_STATS_INIT   : S_DECAY_UPDATE;
        S_STATS_INIT:    nstate = S_STATS;
        S_STATS:         nstate = (iv_idx == num_intervals)   ? S_CHECK        : S_STATS;

        S_CHECK: begin
          if (num_intervals < 2)
            nstate = S_PACK_OUT;
          else if ((max_val > 100 && (max_val * num_intervals > (total_sum << 1))) ||
                   (((min_val << 1) * num_intervals) < total_sum))
            nstate = S_MERGE_PREP;
          else
            nstate = S_PACK_OUT;
        end

        S_MERGE_PREP:    nstate = (merge_with_nxt == 32'hFFFF_FFFF) ? S_PACK_OUT    : S_MERGE_SHIFTB;
        S_MERGE_SHIFTB:  nstate = (shift_idx == act_num_intervals)        ? S_MERGE_SHIFTC  : S_MERGE_SHIFTB;
        S_MERGE_SHIFTC:  nstate = (shift_idx == (act_num_intervals - 1))  ? S_SPLIT_FINDMAX : S_MERGE_SHIFTC;
        S_SPLIT_FINDMAX: nstate = (iv_idx == act_num_intervals)           ? S_SPLIT_SHIFTB  : S_SPLIT_FINDMAX;

        // Wait until shift_idx reaches the insertion position before advancing.
        S_SPLIT_SHIFTB:  nstate = (shift_idx == (max2_idx + 1))           ? S_SPLIT_SHIFTC  : S_SPLIT_SHIFTB;

        // Wait until shift_idx reaches the insertion position and the count shift is complete.
        S_SPLIT_SHIFTC:  nstate = (shift_idx == (max2_idx + 1))           ? S_PACK_OUT      : S_SPLIT_SHIFTC;

        S_PACK_OUT:      nstate = S_STREAM_OUT;
        S_STREAM_OUT:    nstate = (out_idx > MAX_INTERVALS) ? S_DONE : S_STREAM_OUT;
        S_DONE:          nstate = S_WAIT_START;
        default:         nstate = S_WAIT_START;
      endcase
    end

endmodule
