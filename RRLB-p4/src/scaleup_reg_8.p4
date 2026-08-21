/* -*- P4_16 -*- */
#include <core.p4>
#if __TARGET_TOFINO__ == 2
#include <t2na.p4>
#else
#include <tna.p4>
#endif

#include "includes/headers.p4"
#include "includes/parser.p4"

struct bucket_state_t {
    bit<16> border;
    bit<16> counter;
}

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
    Register<bucket_state_t, bit<1>>(1) bucket_0;
    Register<bucket_state_t, bit<1>>(1) bucket_1;
    Register<bucket_state_t, bit<1>>(1) bucket_2;
    Register<bucket_state_t, bit<1>>(1) bucket_3;
    Register<bucket_state_t, bit<1>>(1) bucket_4;
    Register<bucket_state_t, bit<1>>(1) bucket_5;
    Register<bucket_state_t, bit<1>>(1) bucket_6;
    Register<bucket_state_t, bit<1>>(1) bucket_7;

    RegisterAction<bucket_state_t, bit<1>, bit<2>>(bucket_0) inc_bucket_0 = {
        void apply(inout bucket_state_t value, out bit<2> result) {
            value.counter = value.counter + 1;
            result = value.counter[1:0];
        }
    };
    RegisterAction<bucket_state_t, bit<1>, bit<2>>(bucket_1) inc_bucket_1 = {
        void apply(inout bucket_state_t value, out bit<2> result) {
            value.counter = value.counter + 1;
            result = value.counter[1:0];
        }
    };
    RegisterAction<bucket_state_t, bit<1>, bit<2>>(bucket_2) inc_bucket_2 = {
        void apply(inout bucket_state_t value, out bit<2> result) {
            value.counter = value.counter + 1;
            result = value.counter[1:0];
        }
    };
    RegisterAction<bucket_state_t, bit<1>, bit<2>>(bucket_3) inc_bucket_3 = {
        void apply(inout bucket_state_t value, out bit<2> result) {
            value.counter = value.counter + 1;
            result = value.counter[1:0];
        }
    };
    RegisterAction<bucket_state_t, bit<1>, bit<2>>(bucket_4) inc_bucket_4 = {
        void apply(inout bucket_state_t value, out bit<2> result) {
            value.counter = value.counter + 1;
            result = value.counter[1:0];
        }
    };
    RegisterAction<bucket_state_t, bit<1>, bit<2>>(bucket_5) inc_bucket_5 = {
        void apply(inout bucket_state_t value, out bit<2> result) {
            value.counter = value.counter + 1;
            result = value.counter[1:0];
        }
    };
    RegisterAction<bucket_state_t, bit<1>, bit<2>>(bucket_6) inc_bucket_6 = {
        void apply(inout bucket_state_t value, out bit<2> result) {
            value.counter = value.counter + 1;
            result = value.counter[1:0];
        }
    };
    RegisterAction<bucket_state_t, bit<1>, bit<2>>(bucket_7) inc_bucket_7 = {
        void apply(inout bucket_state_t value, out bit<2> result) {
            value.counter = value.counter + 1;
            result = value.counter[1:0];
        }
    };

    RegisterAction<bucket_state_t, bit<1>, bit<1>>(bucket_0) check_bucket_0 = {
        void apply(inout bucket_state_t value, out bit<1> result) {
            result = 0;
            if (hdr.normal.rank >= value.border) { result = 1; }
        }
    };
    RegisterAction<bucket_state_t, bit<1>, bit<1>>(bucket_1) check_bucket_1 = {
        void apply(inout bucket_state_t value, out bit<1> result) {
            result = 0;
            if (hdr.normal.rank >= value.border) { result = 1; }
        }
    };
    RegisterAction<bucket_state_t, bit<1>, bit<1>>(bucket_2) check_bucket_2 = {
        void apply(inout bucket_state_t value, out bit<1> result) {
            result = 0;
            if (hdr.normal.rank >= value.border) { result = 1; }
        }
    };
    RegisterAction<bucket_state_t, bit<1>, bit<1>>(bucket_3) check_bucket_3 = {
        void apply(inout bucket_state_t value, out bit<1> result) {
            result = 0;
            if (hdr.normal.rank >= value.border) { result = 1; }
        }
    };
    RegisterAction<bucket_state_t, bit<1>, bit<1>>(bucket_4) check_bucket_4 = {
        void apply(inout bucket_state_t value, out bit<1> result) {
            result = 0;
            if (hdr.normal.rank >= value.border) { result = 1; }
        }
    };
    RegisterAction<bucket_state_t, bit<1>, bit<1>>(bucket_5) check_bucket_5 = {
        void apply(inout bucket_state_t value, out bit<1> result) {
            result = 0;
            if (hdr.normal.rank >= value.border) { result = 1; }
        }
    };
    RegisterAction<bucket_state_t, bit<1>, bit<1>>(bucket_6) check_bucket_6 = {
        void apply(inout bucket_state_t value, out bit<1> result) {
            result = 0;
            if (hdr.normal.rank >= value.border) { result = 1; }
        }
    };
    RegisterAction<bucket_state_t, bit<1>, bit<1>>(bucket_7) check_bucket_7 = {
        void apply(inout bucket_state_t value, out bit<1> result) {
            result = 0;
            if (hdr.normal.rank >= value.border) { result = 1; }
        }
    };

    RegisterAction<bucket_state_t, bit<1>, void>(bucket_0) update_bucket_0 = {
        void apply(inout bucket_state_t value) {
            value.border = hdr.update.border_0;
        }
    };
    RegisterAction<bucket_state_t, bit<1>, void>(bucket_1) update_bucket_1 = {
        void apply(inout bucket_state_t value) {
            value.border = hdr.update.border_1;
        }
    };
    RegisterAction<bucket_state_t, bit<1>, void>(bucket_2) update_bucket_2 = {
        void apply(inout bucket_state_t value) {
            value.border = hdr.update.border_2;
        }
    };
    RegisterAction<bucket_state_t, bit<1>, void>(bucket_3) update_bucket_3 = {
        void apply(inout bucket_state_t value) {
            value.border = hdr.update.border_3;
        }
    };
    RegisterAction<bucket_state_t, bit<1>, void>(bucket_4) update_bucket_4 = {
        void apply(inout bucket_state_t value) {
            value.border = hdr.update.border_4;
        }
    };
    RegisterAction<bucket_state_t, bit<1>, void>(bucket_5) update_bucket_5 = {
        void apply(inout bucket_state_t value) {
            value.border = hdr.update.border_5;
        }
    };
    RegisterAction<bucket_state_t, bit<1>, void>(bucket_6) update_bucket_6 = {
        void apply(inout bucket_state_t value) {
            value.border = hdr.update.border_6;
        }
    };
    RegisterAction<bucket_state_t, bit<1>, void>(bucket_7) update_bucket_7 = {
        void apply(inout bucket_state_t value) {
            value.border = hdr.update.border_7;
        }
    };

    RegisterAction<bucket_state_t, bit<1>, Counter_t>(bucket_0) read_bucket_0 = {
        void apply(inout bucket_state_t value, out Counter_t result) {
            result = value.counter;
            value.counter = value.counter & 3;
        }
    };
    RegisterAction<bucket_state_t, bit<1>, Counter_t>(bucket_1) read_bucket_1 = {
        void apply(inout bucket_state_t value, out Counter_t result) {
            result = value.counter;
            value.counter = value.counter & 3;
        }
    };
    RegisterAction<bucket_state_t, bit<1>, Counter_t>(bucket_2) read_bucket_2 = {
        void apply(inout bucket_state_t value, out Counter_t result) {
            result = value.counter;
            value.counter = value.counter & 3;
        }
    };
    RegisterAction<bucket_state_t, bit<1>, Counter_t>(bucket_3) read_bucket_3 = {
        void apply(inout bucket_state_t value, out Counter_t result) {
            result = value.counter;
            value.counter = value.counter & 3;
        }
    };
    RegisterAction<bucket_state_t, bit<1>, Counter_t>(bucket_4) read_bucket_4 = {
        void apply(inout bucket_state_t value, out Counter_t result) {
            result = value.counter;
            value.counter = value.counter & 3;
        }
    };
    RegisterAction<bucket_state_t, bit<1>, Counter_t>(bucket_5) read_bucket_5 = {
        void apply(inout bucket_state_t value, out Counter_t result) {
            result = value.counter;
            value.counter = value.counter & 3;
        }
    };
    RegisterAction<bucket_state_t, bit<1>, Counter_t>(bucket_6) read_bucket_6 = {
        void apply(inout bucket_state_t value, out Counter_t result) {
            result = value.counter;
            value.counter = value.counter & 3;
        }
    };
    RegisterAction<bucket_state_t, bit<1>, Counter_t>(bucket_7) read_bucket_7 = {
        void apply(inout bucket_state_t value, out Counter_t result) {
            result = value.counter;
            value.counter = value.counter & 3;
        }
    };

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
        bit<1> bucket_hit;
        bit<8> bucket_count;

        hdr.ethernet.dst_addr = ig_prsr_md.global_tstamp;
        if (ig_intr_md.resubmit_flag == 1) {
            hdr.scaleup.result = 0;
            if (hdr.resubmit.counter_index == 0) { hdr.scaleup.result = inc_bucket_0.execute(0); }
            if (hdr.resubmit.counter_index == 1) { hdr.scaleup.result = inc_bucket_1.execute(0); }
            if (hdr.resubmit.counter_index == 2) { hdr.scaleup.result = inc_bucket_2.execute(0); }
            if (hdr.resubmit.counter_index == 3) { hdr.scaleup.result = inc_bucket_3.execute(0); }
            if (hdr.resubmit.counter_index == 4) { hdr.scaleup.result = inc_bucket_4.execute(0); }
            if (hdr.resubmit.counter_index == 5) { hdr.scaleup.result = inc_bucket_5.execute(0); }
            if (hdr.resubmit.counter_index == 6) { hdr.scaleup.result = inc_bucket_6.execute(0); }
            if (hdr.resubmit.counter_index == 7) { hdr.scaleup.result = inc_bucket_7.execute(0); }
            hdr.resubmit.setInvalid();
            hdr.ethernet.dst_addr = hdr.resubmit.enter_time;
        } else if (hdr.scaleup.type == 0) {
            bucket_count = 0;
            bucket_hit = check_bucket_0.execute(0);
            bucket_count = bucket_count + (bit<8>)bucket_hit;
            bucket_hit = check_bucket_1.execute(0);
            bucket_count = bucket_count + (bit<8>)bucket_hit;
            bucket_hit = check_bucket_2.execute(0);
            bucket_count = bucket_count + (bit<8>)bucket_hit;
            bucket_hit = check_bucket_3.execute(0);
            bucket_count = bucket_count + (bit<8>)bucket_hit;
            bucket_hit = check_bucket_4.execute(0);
            bucket_count = bucket_count + (bit<8>)bucket_hit;
            bucket_hit = check_bucket_5.execute(0);
            bucket_count = bucket_count + (bit<8>)bucket_hit;
            bucket_hit = check_bucket_6.execute(0);
            bucket_count = bucket_count + (bit<8>)bucket_hit;
            bucket_hit = check_bucket_7.execute(0);
            bucket_count = bucket_count + (bit<8>)bucket_hit;

            meta.counter_index = 16;
            if (bucket_count != 0) {
                meta.counter_index = bucket_count - 1;
            }

            hdr.resubmit.counter_index = meta.counter_index;
            hdr.resubmit.enter_time = hdr.ethernet.dst_addr;
            ig_dprsr_md.resubmit_type = 1;
        } else if (hdr.scaleup.type == 1) {
            update_bucket_0.execute(0);
            update_bucket_1.execute(0);
            update_bucket_2.execute(0);
            update_bucket_3.execute(0);
            update_bucket_4.execute(0);
            update_bucket_5.execute(0);
            update_bucket_6.execute(0);
            update_bucket_7.execute(0);
        } else if (hdr.scaleup.type == 2) {
            hdr.upload.counter_0 = read_bucket_0.execute(0);
            hdr.upload.counter_1 = read_bucket_1.execute(0);
            hdr.upload.counter_2 = read_bucket_2.execute(0);
            hdr.upload.counter_3 = read_bucket_3.execute(0);
            hdr.upload.counter_4 = read_bucket_4.execute(0);
            hdr.upload.counter_5 = read_bucket_5.execute(0);
            hdr.upload.counter_6 = read_bucket_6.execute(0);
            hdr.upload.counter_7 = read_bucket_7.execute(0);
            hdr.upload.counter_8 = 0;
            hdr.upload.counter_9 = 0;
            hdr.upload.counter_10 = 0;
            hdr.upload.counter_11 = 0;
            hdr.upload.counter_12 = 0;
            hdr.upload.counter_13 = 0;
            hdr.upload.counter_14 = 0;
            hdr.upload.counter_15 = 0;
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
