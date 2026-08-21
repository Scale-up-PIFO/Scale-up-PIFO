`ifndef TYPEDEFS_SVH
`define TYPEDEFS_SVH

parameter MTW = 16;
parameter RKW = 16;

typedef struct packed {
  logic [MTW-1:0] meta_data;
  logic [RKW-1:0] rank_data;
} push_data_t;

`endif // TYPEDEFS_SVH