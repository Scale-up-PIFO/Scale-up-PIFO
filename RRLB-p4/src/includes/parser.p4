#pragma once

//#define IG_MIRRORING_ENABLED

enum bit<16> ether_type_t {
    IPV4 = 0x0800,
    ARP  = 0x0806,
    PFC  = 0x8808,
    TPID = 0x8100
}

enum bit<8> ipv4_proto_t {
    TCP = 6,
    UDP = 17,
    ICMP = 1
}

enum bit<16> udp_port_t {
    ROCE_V2 = 4791
}


// ---------------------------------------------------------------------------
// Ingress parser
// ---------------------------------------------------------------------------
parser SwitchIngressParser(packet_in pkt,
    out headers_t hdr,
    out metadata_t meta,
    out ingress_intrinsic_metadata_t  ig_intr_md)
{
    state start {  
        pkt.extract(ig_intr_md);  
        transition select(ig_intr_md.resubmit_flag) {  
            1: parse_resubmit;  
            0: parse_port_metadata; 
        }  
    }  

    state parse_resubmit {  
        hdr.resubmit = pkt.lookahead<resubmit_h>();
        pkt.advance(PORT_METADATA_SIZE);  
        transition parse_ethernet;  
    } 


    state parse_port_metadata {  
        pkt.advance(PORT_METADATA_SIZE);  
        transition parse_ethernet;  
    } 

    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ether_type_t.TPID:  parse_vlan_tag;
            ether_type_t.IPV4:  parse_ipv4;
            default: accept;
        }
    }

    state parse_vlan_tag {
        pkt.extract(hdr.vlan_tag);
        transition select(hdr.vlan_tag.ether_type) {
            ether_type_t.IPV4:  parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol){
            17: parse_udp;
            default: accept;
        }
    }

    state parse_udp{
        pkt.extract(hdr.udp);
        transition select(hdr.udp.dst_port){
            50000: parse_scaleup;
            default: accept;
        }
    }

    state parse_scaleup{
        pkt.extract(hdr.scaleup);
        transition select(hdr.scaleup.type){
            0:parse_normal;
            1:parse_update;
            2:parse_upload;
            default: accept;
        }
    }

    state parse_normal {
        pkt.extract(hdr.normal);
        transition accept;
    }

    state parse_update {
        pkt.extract(hdr.update);
        transition accept;
    }

    state parse_upload {
        pkt.extract(hdr.upload);
        transition accept;
    }

}

// ---------------------------------------------------------------------------
// Ingress Deparser
// ---------------------------------------------------------------------------
control SwitchIngressDeparser(packet_out pkt,
    /* User */
    inout headers_t                       hdr,
    in    metadata_t                      meta,
    /* Intrinsic */
    in    ingress_intrinsic_metadata_for_deparser_t  ig_dprsr_md)
{
    Resubmit() resubmit;
    apply {
        if(ig_dprsr_md.resubmit_type == 1){
            resubmit.emit(hdr.resubmit);
        }
        pkt.emit(hdr);
    }
}


// ---------------------------------------------------------------------------
// Egress parser
// ---------------------------------------------------------------------------
parser SwitchEgressParser(
    packet_in pkt,
    out headers_t hdr,
    out metadata_t meta,
    out egress_intrinsic_metadata_t eg_intr_md,
    out egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr){

    // internal_hdr_h internal_hdr;
    state start {  
        pkt.extract(eg_intr_md);  
        transition parse_ethernet;
    }  

    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ether_type_t.TPID:  parse_vlan_tag;
            ether_type_t.IPV4:  parse_ipv4;
            default: accept;
        }
    }

    state parse_vlan_tag {
        pkt.extract(hdr.vlan_tag);
        transition select(hdr.vlan_tag.ether_type) {
            ether_type_t.IPV4:  parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol){
            17: parse_udp;
            default: accept;
        }
    }

    state parse_udp{
        pkt.extract(hdr.udp);
        transition select(hdr.udp.dst_port){
            50000: parse_scaleup;
            default: accept;
        }
    }

    state parse_scaleup{
        pkt.extract(hdr.scaleup);
        transition select(hdr.scaleup.type){
            0:parse_normal;
            1:parse_update;
            2:parse_upload;
            default: accept;
        }
    }

    state parse_normal {
        pkt.extract(hdr.normal);
        transition accept;
    }

    state parse_update {
        pkt.extract(hdr.update);
        transition accept;
    }

    state parse_upload {
        pkt.extract(hdr.upload);
        transition accept;
    }
}

// ---------------------------------------------------------------------------
// Egress Deparser
// ---------------------------------------------------------------------------
control SwitchEgressDeparser(
    packet_out pkt,
    inout headers_t hdr,
    in metadata_t meta,
    in egress_intrinsic_metadata_for_deparser_t eg_intr_md_for_dprsr,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr){

	apply{
        pkt.emit(hdr);
    }
}
