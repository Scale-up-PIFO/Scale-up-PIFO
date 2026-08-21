/* -*- P4_16 -*- */
#include <core.p4>
#if __TARGET_TOFINO__ == 2
#include <t2na.p4>
#else
#include <tna.p4>
#endif

#include "includes/headers.p4"
#include "includes/parser.p4"

control SwitchIngress(
    /* User */
    inout headers_t                       hdr,
    inout metadata_t                      meta,
    /* Intrinsic */
    in    ingress_intrinsic_metadata_t               ig_intr_md,
    in    ingress_intrinsic_metadata_from_parser_t   ig_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t  ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t        ig_intr_md_for_tm)
{
    Register<Counter_t, bit<8>>(16) counters;

    RegisterAction<Counter_t, bit<8>, bit<2>>(counters) update_counter = {
        void apply(inout Counter_t value, out bit<2> result) {
            value = value + 1;
            result = value[1:0];
        }
    };

    action set_counter_index(bit<8> index) {
        meta.counter_index = index;
    }

    table rank_to_counter_table {
        key = {
            hdr.normal.rank: range;
        }
        actions = {
            set_counter_index;
            NoAction;
        }
        size = 64;
        default_action = NoAction();
    }

    action ipv4_forward(PortId_t port) {
        ig_intr_md_for_tm.ucast_egress_port = port;
    }

    table forward_table {
        key = {
            hdr.ipv4.dst_addr: exact;
        }
        actions = {
            ipv4_forward;
        }
        size = 512;
    }

    apply {
        hdr.ethernet.dst_addr = ig_prsr_md.global_tstamp;

        if (ig_intr_md.resubmit_flag == 1) {
            hdr.scaleup.result = 0;
            if (hdr.resubmit.counter_index < 16) {
                hdr.scaleup.result = update_counter.execute(hdr.resubmit.counter_index);
            }
            hdr.resubmit.setInvalid();
            hdr.ethernet.dst_addr = hdr.resubmit.enter_time;
        } else if (hdr.scaleup.type == 0) {
            meta.counter_index = 16;
            rank_to_counter_table.apply();

            hdr.resubmit.counter_index = meta.counter_index;
            hdr.resubmit.enter_time = hdr.ethernet.dst_addr;
            ig_dprsr_md.resubmit_type = 1;
        } else if (hdr.scaleup.type == 2) {
        }

        forward_table.apply();
    }
}

/*******************
 * Egress Pipeline *
 * *****************/

control SwitchEgress(
    inout headers_t hdr,
    inout metadata_t meta,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr,
    inout egress_intrinsic_metadata_for_deparser_t eg_intr_md_for_dprsr,
    inout egress_intrinsic_metadata_for_output_port_t eg_intr_md_for_oport)
{
    apply {
        hdr.ethernet.src_addr = eg_intr_md_from_prsr.global_tstamp;
    }
}

Pipeline(SwitchIngressParser(),
         SwitchIngress(),
         SwitchIngressDeparser(),
         SwitchEgressParser(),
         SwitchEgress(),
         SwitchEgressDeparser()
         ) pipe;

Switch(pipe) main;
