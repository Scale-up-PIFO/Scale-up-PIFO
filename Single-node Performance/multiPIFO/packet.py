
class Pkt:
    def __init__(self, pktid, flowid, length, flow_size):
        self.pktid = pktid


        self.flowid = flowid
        self.length = length
        self.flow_size = flow_size


        self.oid = flowid