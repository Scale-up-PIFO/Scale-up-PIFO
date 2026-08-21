#!/usr/bin/env python3
from scapy.all import *
from scapy.fields import *
from scapy.packet import Packet
import struct

# Define the Scaleup header.
class ScaleupHeader(Packet):
    name = "ScaleupHeader"
    fields_desc = [
        BitField("type", 0, 2),      # 2-bit type field
        BitField("result", 0, 2),    # 2-bit result field
        BitField("padding", 0, 4)    # 4-bit padding field
    ]

# Define the normal-packet header.
class NormalHeader(Packet):
    name = "NormalHeader"
    fields_desc = [
        ShortField("rank", 0)        # 16-bit rank field
    ]

# Define the update-packet header.
class UpdateHeader(Packet):
    name = "UpdateHeader"
    fields_desc = [
        ShortField("border_0", 0),
        ShortField("border_1", 0),
        ShortField("border_2", 0),
        ShortField("border_3", 0),
        ShortField("border_4", 0),
        ShortField("border_5", 0),
        ShortField("border_6", 0),
        ShortField("border_7", 0),
        ShortField("border_8", 0),
        ShortField("border_9", 0),
        ShortField("border_10", 0),
        ShortField("border_11", 0),
        ShortField("border_12", 0),
        ShortField("border_13", 0),
        ShortField("border_14", 0),
        ShortField("border_15", 0)
    ]

# Define the upload-packet header.
class UploadHeader(Packet):
    name = "UploadHeader"
    fields_desc = [
        ShortField("counter_0", 0),
        ShortField("counter_1", 0),
        ShortField("counter_2", 0),
        ShortField("counter_3", 0),
        ShortField("counter_4", 0),
        ShortField("counter_5", 0),
        ShortField("counter_6", 0),
        ShortField("counter_7", 0),
        ShortField("counter_8", 0),
        ShortField("counter_9", 0),
        ShortField("counter_10", 0),
        ShortField("counter_11", 0),
        ShortField("counter_12", 0),
        ShortField("counter_13", 0),
        ShortField("counter_14", 0),
        ShortField("counter_15", 0)
    ]

class CustomPacketSender:
    def __init__(self, dst_ip="127.0.0.1", dst_port=12345, src_port=54321, enth = None):
        self.dst_ip = dst_ip
        self.dst_port = dst_port
        self.src_port = src_port
        self.enth = enth

    def send_normal_packet(self, rank=1000, result=0):
        """Send a normal packet (type=0)."""
        # Build the protocol headers.
        scaleup_hdr = ScaleupHeader(type=0, result=result, padding=0)
        normal_hdr = NormalHeader(rank=rank)
        
        # Build the complete packet.
        packet = (IP(dst=self.dst_ip) / 
                 UDP(sport=self.src_port, dport=self.dst_port) /
                 scaleup_hdr / normal_hdr)
        
        print(f"Sending normal packet: rank={rank}, result={result}")
        sendp(Ether()/packet, iface=self.enth, verbose=0)
        return packet

    def send_update_packet(self, borders, result=0):
        """Send an update packet (type=1).
        borders: List containing 16 border values.
        """
        if len(borders) != 16:
            raise ValueError("borders list must contain exactly 16 elements")
            
        # Build the protocol headers.
        scaleup_hdr = ScaleupHeader(type=1, result=result, padding=0)
        update_hdr = UpdateHeader(
            border_0=borders[0], border_1=borders[1], border_2=borders[2], border_3=borders[3],
            border_4=borders[4], border_5=borders[5], border_6=borders[6], border_7=borders[7],
            border_8=borders[8], border_9=borders[9], border_10=borders[10], border_11=borders[11],
            border_12=borders[12], border_13=borders[13], border_14=borders[14], border_15=borders[15]
        )
        
        # Build the complete packet.
        packet = (IP(dst=self.dst_ip) / 
                 UDP(sport=self.src_port, dport=self.dst_port) /
                 scaleup_hdr / update_hdr)
        
        print(f"Sending update packet: borders={borders}, result={result}")
        sendp(Ether()/packet,iface=self.enth, verbose=0)
        return packet

    def send_upload_packet(self, counters, result=0):
        """Send an upload packet (type=2).
        counters: List containing 16 counter values.
        """
        if len(counters) != 16:
            raise ValueError("counters list must contain exactly 16 elements")
            
        # Build the protocol headers.
        scaleup_hdr = ScaleupHeader(type=2, result=result, padding=0)
        upload_hdr = UploadHeader(
            counter_0=counters[0], counter_1=counters[1], counter_2=counters[2], counter_3=counters[3],
            counter_4=counters[4], counter_5=counters[5], counter_6=counters[6], counter_7=counters[7],
            counter_8=counters[8], counter_9=counters[9], counter_10=counters[10], counter_11=counters[11],
            counter_12=counters[12], counter_13=counters[13], counter_14=counters[14], counter_15=counters[15]
        )
        
        # Build the complete packet.
        packet = (IP(dst=self.dst_ip) / 
                 UDP(sport=self.src_port, dport=self.dst_port) /
                 scaleup_hdr / upload_hdr)
        
        print(f"Sending upload packet: counters={counters}, result={result}")
        sendp(Ether()/packet,iface=self.enth,verbose=0)
        return packet

def main():
    """Run a packet-sending demonstration."""
    sender = CustomPacketSender(dst_ip="127.0.0.1", dst_port=50000,enth='veth20')
    
    # Send a normal packet.
    print("=== Sending Normal Packet ===")
    sender.send_normal_packet(rank=2048, result=0)
    
    # # Send an update packet.
    # print("\n=== Sending Update Packet ===")
    # borders = [i * 100 for i in range(16)]  # Generate 16 border values.
    # sender.send_update_packet(borders=borders, result=0)
    
    # # Send an upload packet.
    # print("\n=== Sending Upload Packet ===")
    # counters = [0 for i in range(16)]  # Generate 16 counter values.
    # sender.send_upload_packet(counters=counters, result=0)

# Convenience function for interactive use.
def send_custom_packet(packet_type, dst_ip="127.0.0.1", dst_port=12345, **kwargs):
    """
    Convenience function for sending packets.
    packet_type: "normal", "update", "upload"
    """
    sender = CustomPacketSender(dst_ip=dst_ip, dst_port=dst_port)
    
    if packet_type == "normal":
        rank = kwargs.get("rank", 1000)
        result = kwargs.get("result", 0)
        return sender.send_normal_packet(rank=rank, result=result)
    
    elif packet_type == "update":
        borders = kwargs.get("borders", list(range(16)))
        result = kwargs.get("result", 0)
        return sender.send_update_packet(borders=borders, result=result)
    
    elif packet_type == "upload":
        counters = kwargs.get("counters", list(range(16)))
        result = kwargs.get("result", 0)
        return sender.send_upload_packet(counters=counters, result=result)
    
    else:
        raise ValueError("packet_type must be 'normal', 'update', or 'upload'")

if __name__ == "__main__":
    main()
