`timescale 1ns/1ps

module tb;
  // Clock and reset
  reg clk = 0;
  always #5 clk = ~clk;   // 100MHz
  reg rst_n = 0;

  // DUT ports
  reg         start = 0;
  reg [63:0]  cnt_in_data = 64'd0;
  wire [64*(16+1)-1:0] borders_out_bus;
  wire        busy, done;

  // Instantiate the DUT with its defaults: NUM_LB=2, NUM_PIFO=3, and INIT_NUM_INTERVALS=8.
  interval_border_adjuster dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .cnt_in_data(cnt_in_data),
    .borders_out_bus(borders_out_bus),
    .busy(busy),
    .done(done)
  );

  integer i;

  initial begin
    // Reset the DUT.
    repeat(5) @(negedge clk);
    rst_n = 1;
    repeat(2) @(negedge clk);

    // Start one adjustment round.
    @(negedge clk); start = 1;
    @(negedge clk); start = 0;

    // Feed 2*3*8 = 48 count words continuously, each with a value of 10.
    // The interval index changes fastest, followed by the PIFO and load-balancer indices.
    for (i = 0; i < 2*3*8; i = i + 1) begin
      @(negedge clk);
      cnt_in_data = 64'd10;
    end

    // Wait for the adjustment round to finish.
    @(posedge done);
    @(negedge clk);

    for (i = 0; i < 8; i = i + 1) begin
      $display("i=%0d  curr=%0d  bcnt=%0d", i, dut.curr[i], dut.bcnt[i]);
    end
    
    for (i = 0; i < 8; i = i + 1) begin
      $display("border[%0d] = %0d", i, borders_out_bus[i*64 +: 64]);
    end
    

    // Finish the simulation.
    repeat(5) @(negedge clk);
    $finish;
  end
endmodule
