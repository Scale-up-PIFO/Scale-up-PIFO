`timescale 1ns/1ps
`include "typedefs.svh"

module PUSH_FIFO#(
    parameter FIFO_SIZE = 8
)(
    input  logic                  rst, clk, wr_en, rd_en,
    // reset, system clock, write enable, and read enable.

    // Define the data structure for the FIFO element
    // Using a packed struct makes the data fields clear and easy to access.
    input  push_data_t            buf_in,
    // Data input of type push_data_t to be pushed into the buffer.

    output push_data_t            buf_out,
    // Data output of type push_data_t popped from the buffer.

    output logic                  buf_empty, buf_full,
    // Buffer empty and full indication flags.

    output logic [$clog2(FIFO_SIZE):0]    o_fifo_counter
    // Number of elements currently stored in the buffer.
);


    // Internal registers and wires
    logic [$clog2(FIFO_SIZE):0]  fifo_counter, fifo_counter_next;      // Counts the number of elements in FIFO
    logic [$clog2(FIFO_SIZE)-1:0] rd_ptr, wr_ptr, rd_ptr_nxt, wr_ptr_nxt;   // Pointers for read and write addresses

    // The memory array now stores elements of type 'push_data_t'
    push_data_t          buf_mem [FIFO_SIZE-1 : 0];
    push_data_t          buf_rd;            // Register to hold the read data

    // --- FIFO Status Logic ---
    // The FIFO is empty if the counter is zero.
    assign buf_empty = (fifo_counter == 0);
    // The FIFO is full if the counter equals its maximum size.
    assign buf_full = (fifo_counter == FIFO_SIZE);
    // Output the current element count.
    assign o_fifo_counter = fifo_counter;


    // --- FIFO Counter Logic ---
    // This logic determines the next value of the counter based on read/write operations.
    always_comb begin
        // If writing and reading simultaneously, the count doesn't change.
        if (wr_en && rd_en)
            fifo_counter_next = fifo_counter;
        // If only writing and not full, increment the counter.
        else if (wr_en && !buf_full)
            fifo_counter_next = fifo_counter + 1;
        // If only reading and not empty, decrement the counter.
        else if (rd_en && !buf_empty)
            fifo_counter_next = fifo_counter - 1;
        // Otherwise, the counter remains unchanged.
        else
            fifo_counter_next = fifo_counter;
    end

    // Update the counter on the positive clock edge.
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            fifo_counter <= 0; // Reset the counter to zero.
        else
            fifo_counter <= fifo_counter_next;
    end

   

    always_ff @(posedge clk) begin
        if( wr_en && ((!buf_full) | rd_en) )
            buf_mem[ wr_ptr ] <= buf_in;		//Writing data input to buffer location indicated by write pointer
    end

    always_comb begin
        if( wr_en && ((!buf_full) | rd_en) )    
            wr_ptr_nxt = wr_ptr + 1;		// On write operation, Write pointer points to next location
        else  
            wr_ptr_nxt = wr_ptr;   
    end

    always_ff @(posedge clk) begin
        if( rd_en && (!buf_empty) )
            buf_rd <= buf_mem[ rd_ptr ];
        else if(rd_en && buf_empty && wr_en)
            buf_rd <= buf_in;
        else
            buf_rd <= '0;
    end

    assign buf_out = buf_rd; // An empty FIFO with simultaneous read and write needs forwarding; a full FIFO correctly returns the old data.

    always_comb begin
        if( rd_en && ((!buf_empty) | wr_en) )   
            rd_ptr_nxt = rd_ptr + 1;		// On read operation, read pointer points to next location to be read
        else 
            rd_ptr_nxt = rd_ptr;
    end

    always_ff @(posedge clk or posedge rst) begin
        if( rst ) begin
            wr_ptr <= 0;		// Initializing write pointer
            rd_ptr <= 0;		//Initializing read pointer
        end else begin
            wr_ptr <= wr_ptr_nxt;
            rd_ptr <= rd_ptr_nxt;
        end
    end

endmodule
