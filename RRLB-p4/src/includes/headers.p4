#pragma once
/* for random number generation */

#define EXPERT_CAPACITY 65536 // Capacity of the expert 
#define PORT_COUNT 4
#define COUNTER_WIDE 32	// wide for a couter register
#define MAX_EXPERT_COUNT 256
#define FOUR_WAY_MCAST_GROUP 777; 
#define LOOPBACK_PORT 64


typedef bit<16> Rank_t;
typedef bit<16> Counter_t;
typedef bit<16> Border_t;




header ethernet_h {
    bit<48>   dst_addr;
    bit<48>   src_addr;
    bit<16>   ether_type;
}

header vlan_tag_h {
    bit<3>   pcp;
    bit<1>   cfi;
    bit<12>  vid;
    bit<16>  ether_type;
}

header ipv4_h {
    bit<4>   version;
    bit<4>   ihl;
    bit<8>   diffserv;
    bit<16>  total_len;
    bit<16>  identification;
    bit<3>   flags;
    bit<13>  frag_offset;
    bit<8>   ttl;
    bit<8>   protocol;
    bit<16>  hdr_checksum;
    bit<32>  src_addr;
    bit<32>  dst_addr;
}

header udp_h {
    bit<16>  src_port;
    bit<16>  dst_port;
    bit<16>  len;
    bit<16>  checksum;
}

header resubmit_h {
    bit<48> enter_time;
    bit<8> counter_index;
    bit<8> padding;
}

header scaleup_h{
    bit<2> type;
    bit<2> result;
    bit<4> padding;
}

header normal_h{
    Rank_t rank;
}

header update_h{
    Border_t border_0;
    Border_t border_1;
    Border_t border_2;
    Border_t border_3;
    Border_t border_4;
    Border_t border_5;
    Border_t border_6;
    Border_t border_7;
    Border_t border_8;
    Border_t border_9;
    Border_t border_10;
    Border_t border_11;
    Border_t border_12;
    Border_t border_13;
    Border_t border_14;
    Border_t border_15;
}

header upload_h{
    Counter_t counter_0;
    Counter_t counter_1;
    Counter_t counter_2;
    Counter_t counter_3;
    Counter_t counter_4;
    Counter_t counter_5;
    Counter_t counter_6;
    Counter_t counter_7;
    Counter_t counter_8;
    Counter_t counter_9;
    Counter_t counter_10;
    Counter_t counter_11;
    Counter_t counter_12;
    Counter_t counter_13;
    Counter_t counter_14;
    Counter_t counter_15;
}

    /***********************  H E A D E R S  ************************/
struct headers_t {
    resubmit_h   resubmit;
    ethernet_h   ethernet;
    vlan_tag_h   vlan_tag; 
    ipv4_h       ipv4;
    udp_h        udp;
    scaleup_h scaleup;
    normal_h normal;
    update_h update;
    upload_h upload;
}


    /******  G L O B A L   I N G R E S S   M E T A D A T A  *********/

struct metadata_t {
    Rank_t rank;
    bit<8> counter_index;
}
