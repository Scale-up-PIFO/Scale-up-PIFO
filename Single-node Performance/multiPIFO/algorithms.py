from packet import Pkt
import math
class SchedulingAlgorithm:
    def __init__(self, *args, **kwargs):
        pass

    def rank_cal(self, pkt: Pkt) -> float:
        raise NotImplementedError("Subclasses should implement this method.")

    def post_dequeue(self, pkt: Pkt, rank: float):
        pass

class FifoAlgorithm(SchedulingAlgorithm):
    def __init__(self):
        super().__init__()

        self.time = 0

    def rank_cal(self, pkt: Pkt) -> float:

        self.time += 1
        return self.time

    def post_dequeue(self, pkt: Pkt, rank: float):

        pass

class SpAlgorithm(SchedulingAlgorithm):
    def __init__(self, flowid2pri: dict):
        super().__init__()
        self.flowid2pri = flowid2pri


    def rank_cal(self, pkt: Pkt) -> float:

        flowid = pkt.flowid
        if flowid not in self.flowid2pri:
            raise KeyError(f"Unknown flow id: {flowid}")
        return self.flowid2pri[flowid]

    def post_dequeue(self, pkt: Pkt, rank: float):
        pass

class pFabricAlgorithm(SchedulingAlgorithm):
    def __init__(self):
        super().__init__()
    
    def rank_cal(self, pkt: Pkt) -> float:
        return pkt.flow_size
    
    def post_dequeue(self, pkt: Pkt, rank: float):
        pass

class WFQAlgorithm(SchedulingAlgorithm):
    def __init__(self, flowid2weight):
        super().__init__()
        self.flowid2weight = flowid2weight
        self.virtual_time = 0
        self.flowid2finish = {flow_id: 0 for flow_id in self.flowid2weight.keys()}
    
    def rank_cal(self, pkt: Pkt) -> float:
        flowid = pkt.flowid
        if flowid not in self.flowid2weight:
            raise KeyError(f"Unknown flow id: {flowid}")
        self.flowid2finish[flowid] = max(self.flowid2finish[flowid], self.virtual_time) + pkt.length / self.flowid2weight[flowid]
        return self.flowid2finish[flowid]
    
    def post_dequeue(self, pkt: Pkt, rank: float):



        self.virtual_time = max(self.virtual_time, rank)
        
    def reset(self) -> None:
        self.virtual_time = 0

        for flow_id in self.flowid2finish:
            self.flowid2finish[flow_id] = 0



class WFQPCQAlgorithm(SchedulingAlgorithm):
    def __init__(self, flowid2weight, BpR: int = 10000):
        self.flowid2weight = flowid2weight
        self.BpR = BpR
        self.flowid2bytes = {flow_id: 0.0 for flow_id in flowid2weight.keys()}


    def rank_cal(self, pkt: Pkt, current_round: int) -> int:
        flowid = pkt.flowid
        if flowid not in self.flowid2weight:
            raise KeyError(f"Unknown flow id: {flowid}")
        
        weight = self.flowid2weight[flowid]

        round_baseline = current_round * self.BpR * weight
        

        self.flowid2bytes[flowid] = max(self.flowid2bytes[flowid], round_baseline)
        
        

        numerator = self.flowid2bytes[flowid] + pkt.length
        denominator = self.BpR * weight
        n_float = numerator / denominator - current_round


        n = max(0, math.floor(n_float))
        

        self.flowid2bytes[flowid] += pkt.length
        
        return n
