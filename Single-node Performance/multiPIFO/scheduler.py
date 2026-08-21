from packet import Pkt
from algorithms import SchedulingAlgorithm
from dataclasses import dataclass, field
import heapq
from collections import deque, defaultdict
from typing import List, Dict, Optional, Tuple
from sortedcontainers import SortedList



class Scheduler:
    def __init__(self) -> None:
        pass

    def enqueue(self, pkt: Pkt) -> None:
        raise NotImplementedError("Subclasses should implement this method.")

    def dequeue(self):
        raise NotImplementedError("Subclasses should implement this method.")

    def is_empty(self) -> bool:
        raise NotImplementedError("Subclasses should implement this method.")


@dataclass
class Element:
    rank: float
    pkt: Pkt
    delay: float = field(default=0.0)
    queue_index: int = field(default=0)

    def __lt__(self, other: 'Element') -> bool:
        if self.rank != other.rank:
            return self.rank < other.rank


        return self.pkt.pktid < other.pkt.pktid
    


class IdealPIFOScheduler(Scheduler):
    def __init__(self, SchAlgorithm: SchedulingAlgorithm, buffer_size: int = 12.5 * 1024 * 1024,return_mode='basic') -> None:
        super().__init__()
        self.SchAlgorithm = SchAlgorithm

        self.queue = SortedList()
        self.buffer_size = buffer_size
        self.pifo_size = 0.0


        self.total_pkt_length = 0.0
        self.max_total_length = 0.0


        self.return_mode = return_mode
    def enqueue(self, pkt: Pkt) -> None:
        rank = self.SchAlgorithm.rank_cal(pkt)

        element = Element(rank=rank, pkt=pkt)
        required_size = self.pifo_size + pkt.length
        element.delay=0

        while required_size > self.buffer_size and self.queue:

            removed_element = self.queue.pop()
            self.pifo_size -= removed_element.pkt.length
            required_size = self.pifo_size + pkt.length

            self.total_pkt_length -= removed_element.pkt.length

        self.total_pkt_length+= pkt.length
        if self.total_pkt_length > self.max_total_length:
            self.max_total_length = self.total_pkt_length


        self.queue.add(element)
        self.pifo_size += pkt.length

    def dequeue(self):
        if not self.queue:

            if self.return_mode == 'with_delay':
                return None, -1, -1, -1
            else:
                return None, -1, -1
        

        element = self.queue.pop(0)
        current_rank = element.rank
        self.pifo_size -= element.pkt.length
        
        self.SchAlgorithm.post_dequeue(element.pkt, current_rank)

        

        rank_error = self.queue.bisect_left(element)
    

        self.total_pkt_length -= element.pkt.length


        if self.return_mode == 'with_delay':
            self.update_queue_delays(current_rank=element.rank)

            return element.pkt, current_rank, rank_error, element.delay
        else:

            return element.pkt, current_rank, rank_error

    def is_empty(self) -> bool:
        return not self.queue
    
    def reset(self) -> None:
        self.queue.clear()
        self.pifo_size = 0.0

        if hasattr(self.SchAlgorithm, 'reset'):
            self.SchAlgorithm.reset()

    def print_max_total_length(self) -> None:
        print(f"Maximum queued bytes: {self.max_total_length}")

        print(f"({self.max_total_length / (1024 * 1024):.2f} MB)")
    
    def update_queue_delays(self, current_rank):

        for elem in self.queue:

            if elem.rank < current_rank:
                elem.delay += 1



class RRInterleavingPIFOScheduler(Scheduler):
    def __init__(self, SchAlgorithm: SchedulingAlgorithm, PIFO_num: int, buffer_size: int = 12.5 * 1024 * 1024,return_mode='basic') -> None:
        super().__init__()
        self.SchAlgorithm = SchAlgorithm
        self.input_pointer = 0
        self.output_pointer = 0
        self.PIFO_num = PIFO_num
        self.buffer_size = buffer_size
        self.buffer_per_pifo = buffer_size / PIFO_num



        self.queues: list[SortedList[Element]] = [SortedList() for _ in range(PIFO_num)]
        self.pifo_sizes: List[float] = [0.0 for _ in range(PIFO_num)]
        
        self.queue = SortedList()

        self.return_mode = return_mode

    def enqueue(self, pkt: Pkt) -> None:

        rank = self.SchAlgorithm.rank_cal(pkt)

        element = Element(rank=rank, pkt=pkt)
        element.delay=0


        queue_index = self.input_pointer % self.PIFO_num

        required_size = self.pifo_sizes[queue_index] + pkt.length



        while required_size > self.buffer_per_pifo and self.queues[queue_index]:

            removed_element = self.queues[queue_index].pop()
            self.queue.remove(removed_element)

            self.pifo_sizes[queue_index] -= removed_element.pkt.length

            required_size = self.pifo_sizes[queue_index] + pkt.length
            

        self.queue.add(element)

        self.queues[queue_index].add(element)
        self.pifo_sizes[queue_index] += pkt.length
        self.input_pointer += 1


    def dequeue(self):

        for _ in range(self.PIFO_num):
            queue_index = self.output_pointer % self.PIFO_num
            current_queue = self.queues[queue_index]
            
            if current_queue:

                element = current_queue.pop(0)
                pkt, rank = element.pkt, element.rank

                self.SchAlgorithm.post_dequeue(element.pkt, element.rank)

                self.output_pointer += 1

                self.pifo_sizes[queue_index] -= pkt.length



                rank_error = self.queue.bisect_left(element)

                self.queue.remove(element)


                if self.return_mode == 'with_delay':
                    self.update_queue_delays(current_rank=element.rank)

                    return element.pkt, element.rank, rank_error, element.delay
                else:

                    return element.pkt, element.rank, rank_error
        
            else:

                self.output_pointer += 1
        


        if self.return_mode == 'with_delay':
            return None, -1, -1, -1
        else:
            return None, -1, -1
    
    
    def is_empty(self) -> bool:
        for q in self.queues:
            if q:
                return False
        return True
    
    def update_queue_delays(self, current_rank):

        for elem in self.queue:

            if elem.rank < current_rank:
                elem.delay += 1


class DynamicIntervalRRPIFOScheduler:
    def __init__(self, SchAlgorithm: SchedulingAlgorithm, num_load_balancers: int=1, num_pifos: int=4, num_intervals: int=16, interval_total_length: int=5000000,
                refill_batch_size: int = 4, adjust_period: int = 100000,pifo_buffer_size: int = 12.5 * 1024 * 1024,return_mode='basic',Attenuation='always'):

        self.SchAlgorithm = SchAlgorithm
        self.num_load_balancers = num_load_balancers
        self.num_pifos = num_pifos
        self.num_intervals = num_intervals
        self.interval_total_length = interval_total_length
        self.interval_length = interval_total_length / num_intervals
        self.refill_batch_size = refill_batch_size
        self.adjust_period = adjust_period
        self.fifo_buffer_size = max(num_intervals*num_load_balancers*num_pifos*1500,num_pifos*3000)
        self.fifo_buffer_usage = [0 for _ in range(num_pifos)]
        self.per_fifo_buffer_limit = self.fifo_buffer_size / num_pifos
        self.Attenuation=Attenuation

        self.pifo_buffer_size = pifo_buffer_size / num_pifos
        self.pifo_current_sizes = [0 for _ in range(num_pifos)]


        self.shared_interval_borders = [i * self.interval_length for i in range(num_intervals)] + [interval_total_length]

       

        self.interval_counters = []
        
        self.load_balancer_index = 0
        self.dequeue_lb_index = 0
        self.pifo_index = 0
        self.adjust_counter = 0


        self.pifos: list[SortedList[Element]] = [SortedList() for _ in range(num_pifos)]
        self.fifos: list[deque[Element]] = [deque() for _ in range(num_pifos)]


        self.border_counts = [0.0 for _ in range(num_intervals)]

        self.queue = SortedList()
        self.enqueue_max_rank_error = False


        self.return_mode = return_mode


        self.interval_counters = self._init_interval_counters_with_pattern()

    def _init_interval_counters_with_pattern(self) -> List[List[List[int]]]:

        base_pattern = []

        base_pattern.append([0] * self.num_pifos)

        for active_count in range(1, self.num_pifos):
            pattern = [1 if idx < active_count else 0 for idx in range(self.num_pifos)]
            base_pattern.append(pattern)
        pattern_length = len(base_pattern)


        interval_counters = []
        for _ in range(self.num_load_balancers):
            lb_counters = []
            for pifo_idx in range(self.num_pifos):
                pifo_counters = [
                    base_pattern[interval_idx % pattern_length][pifo_idx]
                    for interval_idx in range(self.num_intervals)
                ]
                lb_counters.append(pifo_counters)
            interval_counters.append(lb_counters)
        
    


        return interval_counters
    
    def _get_interval_index(self, rank: float) -> int:
        for i in range(self.num_intervals):
            if self.shared_interval_borders[i] <= rank < self.shared_interval_borders[i + 1]:
                return i


        self.shared_interval_borders[-1] = rank
        return self.num_intervals - 1

    def _select_best_pifo(self, lb_id: int, interval_index: int) -> int:
        min_count = float('inf')
        best_pifo = 0
        for pifo_id in range(self.num_pifos):
            count = self.interval_counters[lb_id][pifo_id][interval_index]
            if count < min_count:
                min_count = count
                best_pifo = pifo_id
        return best_pifo

    def _refill_from_fifo(self, pifo_id: int) -> None:
   

        for _ in range(self.refill_batch_size):
            if not self.fifos[pifo_id]:
                break
            element = self.fifos[pifo_id].popleft()
            self.pifos[pifo_id].add(element)
            self.fifo_buffer_usage[pifo_id] -= element.pkt.length
            self.pifo_current_sizes[pifo_id] += element.pkt.length
        

        while self.pifo_current_sizes[pifo_id] > self.pifo_buffer_size and self.pifos[pifo_id]:

            removed_element = self.pifos[pifo_id].pop()
            self.queue.remove(removed_element)
            self.pifo_current_sizes[pifo_id] -= removed_element.pkt.length
        
    def enqueue(self, pkt: 'Pkt') -> None:
        
        rank = self.SchAlgorithm.rank_cal(pkt)
        element = Element(rank=rank, pkt=pkt)
        element.delay=0
        

        interval_index = self._get_interval_index(rank)


        lb_id = self.load_balancer_index
        self.load_balancer_index = (self.load_balancer_index + 1) % self.num_load_balancers

        best_pifo = self._select_best_pifo(lb_id, interval_index)
        element.queue_index = best_pifo
        

        if self.fifo_buffer_usage[best_pifo] + pkt.length < self.per_fifo_buffer_limit:

            self.fifos[best_pifo].append(element)
            self.interval_counters[lb_id][best_pifo][interval_index] += 1
            self.fifo_buffer_usage[best_pifo] += pkt.length

            self.queue.add(element)

        else:
            print(f"FIFO {best_pifo} is full")
            return

        self.adjust_counter += 1
        if self.adjust_counter % self.adjust_period == 0:
            self._adjust_intervals()

    def update_queue_delays(self, current_rank):

        for elem in self.queue:

            if elem.rank < current_rank:
                elem.delay += 1

    def dequeue(self):
        pifo_id = self.pifo_index
        self.pifo_index = (self.pifo_index + 1) % self.num_pifos


        if self.pifos[pifo_id]:
            element = self.pifos[pifo_id].pop(0)

            self.SchAlgorithm.post_dequeue(element.pkt, element.rank)
            self.pifo_current_sizes[pifo_id] -= element.pkt.length

            self._refill_from_fifo(pifo_id)


            rank_error = self.queue.bisect_left(element)

            self.queue.remove(element)


            if self.return_mode == 'with_delay':
                self.update_queue_delays(current_rank=element.rank)

                return element.pkt, element.rank, rank_error, element.delay
            else:

                return element.pkt, element.rank, rank_error


        elif self.fifos[pifo_id]:
            self._refill_from_fifo(pifo_id)
            if self.pifos[pifo_id]:
                element = self.pifos[pifo_id].pop(0)

                self.SchAlgorithm.post_dequeue(element.pkt, element.rank)
                self.pifo_current_sizes[pifo_id] -= element.pkt.length
                

                rank_error = self.queue.bisect_left(element)

                self.queue.remove(element)


                if self.return_mode == 'with_delay':
                    self.update_queue_delays(current_rank=element.rank)

                    return element.pkt, element.rank, rank_error, element.delay
                else:

                    return element.pkt, element.rank, rank_error
            
        else:



            if self.return_mode == 'with_delay':
                return None, -1, -1, -1
            else:
                return None, -1, -1
            
    def _print_fifo_lengths(self, action: str) -> None:
        print(f"Action: {action}")

        for i in range(self.num_pifos):


            usage_ratio = (self.fifo_buffer_usage[i] / self.per_fifo_buffer_limit) * 100 if self.per_fifo_buffer_limit > 0 else 0
            

            print(f"  FIFO {i}: "
                f"used_bytes = {self.fifo_buffer_usage[i]}, "
                f"usage_ratio = {usage_ratio:.2f}%")
        

    def _calculate_current_counts(self) -> list[int]:
        current_counts = [0] * self.num_intervals
        

        for lb_id in range(self.num_load_balancers):
            for pifo_id in range(self.num_pifos):
                for interval_idx in range(self.num_intervals):
                    current_counts[interval_idx] += self.interval_counters[lb_id][pifo_id][interval_idx]
                    
        return current_counts

    
    def _adjust_intervals(self):
        if self.num_intervals < 2:
            return
 

        current_counts = self._calculate_current_counts()


        for lb_id in range(self.num_load_balancers):
                for interval_idx in range(self.num_intervals):

                    pifo_counts = [
                        self.interval_counters[lb_id][pifo_id][interval_idx]
                        for pifo_id in range(self.num_pifos)
                    ]

                    min_count = min(pifo_counts)

                    for pifo_id in range(self.num_pifos):
                        self.interval_counters[lb_id][pifo_id][interval_idx] -= min_count


        if self.Attenuation=="always":
            self.border_counts = [
                prev * 0.5 + current 
                for prev, current in zip(self.border_counts, current_counts)
            ]
        else:
            if sum(self.border_counts)  > self.pifo_buffer_size/1480:

                self.border_counts = [
                    prev * 0.5 + current 
                    for prev, current in zip(self.border_counts, current_counts)
                ]
            else:
                self.border_counts = [
                    prev  + current 
                    for prev, current in zip(self.border_counts, current_counts)
                ]
            

        total = sum(self.border_counts)
        if total == 0:
            print("No elements available; interval adjustment skipped")
            return
        mean_count = total / self.num_intervals
        max_count = max(self.border_counts)
        min_count = min(self.border_counts)


        if not ((max_count > 100 and max_count > 2 * mean_count) or min_count < 0.5 * mean_count):
            return


        min_index = self.border_counts.index(min_count)

        left_neighbor = min_index - 1 if min_index > 0 else None
        right_neighbor = min_index + 1 if min_index < self.num_intervals - 1 else None

        merge_with = None
        if left_neighbor is not None and right_neighbor is not None:

            if self.border_counts[left_neighbor] <= self.border_counts[right_neighbor]:
                merge_with = left_neighbor
            else:
                merge_with = right_neighbor
        elif left_neighbor is not None:
            merge_with = left_neighbor
        elif right_neighbor is not None:
            merge_with = right_neighbor

        if merge_with is not None:

            merge_start = min(min_index, merge_with)
            merge_end = max(min_index, merge_with)

            self.shared_interval_borders.pop(merge_end)

            merged_count = self.border_counts[merge_start] + self.border_counts[merge_end]
            self.border_counts.pop(merge_end)
            self.border_counts.pop(merge_start)
            self.border_counts.insert(merge_start, merged_count)
            self.num_intervals -= 1



        max_count_after_merge = max(self.border_counts)
        max_index_after_merge = self.border_counts.index(max_count_after_merge)

        left = self.shared_interval_borders[max_index_after_merge]
        right = self.shared_interval_borders[max_index_after_merge + 1]
        mid = (left + right) / 2

        self.shared_interval_borders.insert(max_index_after_merge + 1, mid)

        split_count = self.border_counts[max_index_after_merge] / 2
        self.border_counts.pop(max_index_after_merge)
        self.border_counts.insert(max_index_after_merge, split_count)
        self.border_counts.insert(max_index_after_merge + 1, split_count)
        self.num_intervals += 1





























































    def is_empty(self) -> bool:

        for pifo in self.pifos:
            if pifo:
                return False

        for fifo in self.fifos:
            if fifo:
                return False

        return True







class GearboxScheduler(Scheduler):
    def __init__(
        self, 
        SchAlgorithm: SchedulingAlgorithm,
        num_levels: int = 3,
        fifos_per_level: List[int] = [10, 10, 10],
        granularities: List[int] = [1, 10, 100] ,
        buffer_size: int = 12.5 * 1024 * 1024
    ) -> None:
        super().__init__()
        self.SchAlgorithm = SchAlgorithm
        self.num_levels = num_levels
        

        assert len(fifos_per_level) == num_levels, "fifos_per_level must match num_levels"
        assert len(granularities) == num_levels, "granularities must match num_levels"
        

        self.buffer_size = buffer_size
        total_fifos = sum(fifos_per_level)
        self.buffer_per_fifo = buffer_size / total_fifos
        

        self.fifo_sizes: List[List[float]] = []

        self.levels: List[List[deque[Element]]] = []
        for l in range(num_levels):
            self.levels.append([deque() for _ in range(fifos_per_level[l])])

            self.fifo_sizes.append([0.0 for _ in range(fifos_per_level[l])])

        self.fifos_per_level = fifos_per_level
        self.granularities = granularities
        

        self.base_times: List[float] = [0.0 for _ in range(num_levels)]
        
        self.ts: int = 0

        self.flow_last_level: Dict[int, int] = defaultdict(int)


        self.max_range = max(g * m for g, m in zip(granularities, fifos_per_level))

        self.ready_queue: deque[Element] = deque()


        self.queue = SortedList()









        


            





            



        


    def _get_compound_fifo(self) -> List[Tuple[int, int]]:
        compound = []
        ts_mod = self.ts % self.max_range

        for l in range(self.num_levels):
            g = self.granularities[l]
            m = self.fifos_per_level[l]
            idx = (ts_mod // g) % m
            compound.append((l, int(idx)))

        return compound

    def enqueue(self, pkt: Pkt) -> None:
        flow_id = pkt.flowid
        n = self.SchAlgorithm.rank_cal(pkt, self.ts)

        level = None
        fifo_index = -1

        for l in range(self.num_levels):
            g = self.granularities[l]
            m = self.fifos_per_level[l]

            if n < g * m:
                base = self.ts // g
                f = base + n // g
                f %= m
                level = l
                fifo_index = f
                break

        if level is None:
            return


        if self.fifo_sizes[level][fifo_index] + pkt.length > self.buffer_per_fifo:
            return
        
        element = Element(
            rank=n,
            pkt=pkt,
            queue_index=fifo_index
        )
        self.levels[level][fifo_index].append(element)
        self.fifo_sizes[level][fifo_index] += pkt.length
        self.flow_last_level[flow_id] = level


        self.queue.add(element)
        
    
    def GearboxServe(self) -> None:
        compound = self._get_compound_fifo()

        for level, fifo_idx in sorted(compound, key=lambda x: x[0]):
            fifo = self.levels[level][fifo_idx]
            if not fifo:
                continue

            g = self.granularities[level]
            count = len(fifo) if level == 0 else max(1, len(fifo) // g)

            for _ in range(count):
                if fifo:
                    element = fifo.popleft()

                    self.fifo_sizes[level][fifo_idx] -= element.pkt.length
                    self.ready_queue.append(element)


    def updateGearBoxSysTime(self) -> None:
        max_search_limit = self.ts + self.max_range

        while self.ts < max_search_limit:
            compound = self._get_compound_fifo()


            found_non_empty = False
            for level, fifo_idx in compound:
                if self.levels[level][fifo_idx]:
                    found_non_empty = True
                    break

            if found_non_empty:
                break
            else:
                self.ts += 1

    def dequeue(self) :

        if self.is_empty():
            return None,-1,-1
        
        if not self.ready_queue:
            self.updateGearBoxSysTime()
            self.GearboxServe()
            self.ts += 1

        if not self.ready_queue:
            return None,-1,-1
        
        element = self.ready_queue.popleft()


        rank_error = self.queue.bisect_left(element)

        self.queue.remove(element)
        
        return element.pkt, element.rank,rank_error
    
    
    def is_empty(self) -> bool:
        for level in self.levels:
            for fifo in level:
                if fifo:
                    return False
        return True
    


class SPPIFOScheduler(Scheduler):
    def __init__(self, SchAlgorithm: SchedulingAlgorithm, fifo_num: int,buffer_size: int = 12.5 * 1024 * 1024):
        super().__init__()
        self.SchAlgorithm = SchAlgorithm
        self.fifo_num = fifo_num
        self.fifos: list[list[Element]] = [[] for _ in range(fifo_num)]
        self.borders: list[float] = [0.0] * fifo_num


        self.buffer_size = buffer_size
        self.per_fifo_buffer = self.buffer_size / fifo_num
        self.fifo_sizes: list[float] = [0.0 for _ in range(fifo_num)]


        self.total_pkt_length = 0.0
        self.max_total_length = 0.0

        self.queue = SortedList()

    def enqueue(self, pkt: Pkt) -> None:
        rank = self.SchAlgorithm.rank_cal(pkt)
        element = Element(rank=rank, pkt=pkt)

        inserted = False

        for i in reversed(range(self.fifo_num)):

            if rank >= self.borders[i]:
                if (self.fifo_sizes[i] + pkt.length) <= self.per_fifo_buffer:
                    self.borders[i] = rank
                    self.fifos[i].append(element)
                    self.fifo_sizes[i] += pkt.length


                    self.queue.add(element)

                    self.total_pkt_length+= pkt.length
                    if self.total_pkt_length > self.max_total_length:
                        self.max_total_length = self.total_pkt_length

                    inserted = True
                    break
                else:
                    return

        if not inserted:

            delta = self.borders[0] - rank
            for i in range(self.fifo_num):
                self.borders[i] -= delta

            if (self.fifo_sizes[0] + pkt.length) <= self.per_fifo_buffer:
                self.fifos[0].append(element)
                self.fifo_sizes[0] += pkt.length


                self.queue.add(element)

                self.total_pkt_length+= pkt.length
                if self.total_pkt_length > self.max_total_length:
                    self.max_total_length = self.total_pkt_length

            else:

                return
            
    def dequeue(self):

        for i in range(self.fifo_num):
            fifo = self.fifos[i]
            if fifo:
                element = fifo.pop(0)
                pkt, rank = element.pkt, element.rank

                self.fifo_sizes[i] -= pkt.length

                self.total_pkt_length -= pkt.length

                

                rank_error = self.queue.bisect_left(element)

                self.queue.remove(element)



                self.SchAlgorithm.post_dequeue(pkt, rank)
                return pkt, rank,rank_error

        return None, -1,-1

    def is_empty(self) -> bool:
        return all(len(fifo) == 0 for fifo in self.fifos)

    def print_max_total_length(self) -> None:
        print(f"Maximum queued bytes: {self.max_total_length}")

        print(f"({self.max_total_length / (1024 * 1024):.2f} MB)")




class AIFOScheduler(Scheduler):
    def __init__(self, SchAlgorithm: SchedulingAlgorithm, window_size: int = 1000, buffer_size: int = 12.5 * 1024 * 1024, k: float = 1/6) -> None:
        super().__init__()
        self.SchAlgorithm = SchAlgorithm
        self.window_size = window_size
        self.buffer_size = buffer_size
        self.k = k
        self.sliding_window = [0.0] * window_size
        self.window_pointer = 0
        self.fifo_queue: List[Element] = []
        self.current_buffer_usage = 0

        self.queue = SortedList()


        self.total_pkt_length = 0.0
        self.max_total_length = 0.0
    def enqueue(self, pkt: Pkt) -> None:

        rank = self.SchAlgorithm.rank_cal(pkt)
        

        self.sliding_window[self.window_pointer % self.window_size] = rank
        self.window_pointer += 1
        

        smaller_count = sum(1 for r in self.sliding_window if r < rank)
        quantile = smaller_count / self.window_size
        


        c=self.current_buffer_usage
        if c < self.k * self.buffer_size:

            element = Element(rank=rank, pkt=pkt)
            self.fifo_queue.append(element)
            self.current_buffer_usage += pkt.length


            self.queue.add(element)

            self.total_pkt_length+= pkt.length
            if self.total_pkt_length > self.max_total_length:
                self.max_total_length = self.total_pkt_length

        else:

            threshold = (self.buffer_size - c) / (self.buffer_size * (1 - self.k))
            if quantile < threshold:
                if self.current_buffer_usage + pkt.length < self.buffer_size:
                    element = Element(rank=rank, pkt=pkt)
                    self.fifo_queue.append(element)
                    self.current_buffer_usage += pkt.length


                    self.queue.add(element)

                    self.total_pkt_length+= pkt.length
                    if self.total_pkt_length > self.max_total_length:
                        self.max_total_length = self.total_pkt_length
                else:
                    return
            else:
                return


    def dequeue(self):

        if not self.fifo_queue:
            return None, -1,-1
        
        element = self.fifo_queue.pop(0)
        pkt, rank = element.pkt, element.rank

        self.current_buffer_usage -= pkt.length

        self.SchAlgorithm.post_dequeue(element.pkt, element.rank)
        

        self.total_pkt_length -= pkt.length


        rank_error = self.queue.bisect_left(element)

        self.queue.remove(element)
        
        return pkt, rank,rank_error


    def is_empty(self) -> bool:
        return len(self.fifo_queue) == 0

    def print_max_total_length(self) -> None:
        print(f"Maximum queued bytes: {self.max_total_length}")

        print(f"({self.max_total_length / (1024 * 1024):.2f} MB)")

class PacksScheduler(Scheduler):
    def __init__(self, SchAlgorithm: SchedulingAlgorithm, fifo_num: int = 10,  window_size: int = 1000, k: float = 1/6,buffer_size: int = 12.5 * 1024 * 1024):
        super().__init__()
        self.SchAlgorithm = SchAlgorithm
        self.fifo_num = fifo_num
        self.buffer_size = buffer_size
        self.buffer_per_queue = buffer_size / fifo_num

        self.k = k
        self.window_size = window_size


        self.sliding_window = [0.0] * window_size
        self.window_pointer = 0


        self.fifos: list[list[Element]] = [[] for _ in range(fifo_num)]
        self.fifo_sizes: list[float] = [0.0 for _ in range(fifo_num)]

        self.queue = SortedList()


        self.total_pkt_length = 0.0
        self.max_total_length = 0.0
        
    def enqueue(self, pkt: Pkt) -> None:

        rank = self.SchAlgorithm.rank_cal(pkt)
        element = Element(rank=rank, pkt=pkt)


        self.sliding_window[self.window_pointer % self.window_size] = rank
        self.window_pointer += 1


        smaller_count = sum(1 for r in self.sliding_window if r < rank)
        quantile = smaller_count / self.window_size


        B = self.buffer_size


        for i in range(self.fifo_num):

            remaining_sum = 0
            for j in range(i + 1):
                used = self.fifo_sizes[j]
                remaining = self.buffer_per_queue - used
                remaining_sum += remaining
            if remaining_sum<0:
                 remaining_sum=0

            threshold = remaining_sum / (B * (1 - self.k))


            if quantile <= threshold:
                if self.fifo_sizes[i] < self.buffer_per_queue:
                    self.fifos[i].append(element)
                    self.fifo_sizes[i] += pkt.length

                    self.queue.add(element)
                    self.total_pkt_length+= pkt.length
                    if self.total_pkt_length > self.max_total_length:
                        self.max_total_length = self.total_pkt_length
                else:
                    print("threshold: ", threshold)
                    print("quantile: ", quantile)
                    print("No elements available; interval adjustment skipped")
                    exit(0)

                return


        return

    def dequeue(self):

        for i in range(self.fifo_num):
            fifo = self.fifos[i]
            if fifo:
                element = fifo.pop(0)
                pkt, rank = element.pkt, element.rank

                self.fifo_sizes[i] -= pkt.length
                self.SchAlgorithm.post_dequeue(pkt, rank)


                rank_error = self.queue.bisect_left(element)

                self.queue.remove(element)

                self.total_pkt_length -= pkt.length
                return pkt, rank,rank_error

        return None, -1,-1

    def is_empty(self) -> bool:
        return all(len(fifo) == 0 for fifo in self.fifos)

    def print_max_total_length(self) -> None:
        print(f"Maximum queued bytes: {self.max_total_length}")

        print(f"({self.max_total_length / (1024 * 1024):.2f} MB)")







class WFQPCQScheduler:
    def __init__(self, algorithm: 'SchedulingAlgorithm', fifo_num: int = 56, buffer_size: int = 12.5 * 1024 * 1024):
        self.algorithm = algorithm
        self.fifo_num = fifo_num
        self.buffer_size = buffer_size
        self.buffer_per_queue = buffer_size / fifo_num
        self.fifos: List[List[Element]] = [[] for _ in range(fifo_num)]
        self.current_round = 0
        self.fifo_sizes: List[float] = [0.0 for _ in range(fifo_num)]

        self.queue = SortedList()

    def enqueue(self, pkt: Pkt) -> None:


        n = self.algorithm.rank_cal(pkt, self.current_round)

        if n >= self.fifo_num:
            return


        if self.fifo_sizes[n] + pkt.length > self.buffer_per_queue:
            return
        
        element = Element(rank=n, pkt=pkt, queue_index=n)
        self.fifo_sizes[n] += pkt.length
        self.fifos[n].append(element)

        self.queue.add(element)

    def dequeue(self) -> Optional[Pkt]:

        if self.is_empty():
            return None, -1.0,-1
        

        while not self.fifos[0]:
            self._rotate_queues()


        element = self.fifos[0].pop(0)

        pkt, rank = element.pkt, element.rank



        self.fifo_sizes[0] -= pkt.length


        rank_error = self.queue.bisect_left(element)

        self.queue.remove(element)
        
        return pkt, rank,rank_error

    def _rotate_queues(self):
        if self.fifos:
            first_queue = self.fifos.pop(0)
            self.fifos.append(first_queue)
        self.current_round += 1

    def is_empty(self) -> bool:
        return all(len(q) == 0 for q in self.fifos)
    



class SPPCQScheduler(Scheduler):
    def __init__(self, SchAlgorithm: SchedulingAlgorithm, fifo_num: int, buffer_size: int = 12.5 * 1024 * 1024):
        super().__init__()
        self.SchAlgorithm = SchAlgorithm
        self.fifo_num = fifo_num
        self.fifos: list[list[Element]] = [[] for _ in range(fifo_num)]
        self.buffer_size = buffer_size
        self.buffer_per_queue = buffer_size / fifo_num
        self.fifo_sizes: list[float] = [0.0 for _ in range(fifo_num)]
        self.queue = SortedList()

    def enqueue(self, pkt: Pkt) -> None:

        rank = self.SchAlgorithm.rank_cal(pkt)

        rank_int = int(round(rank))
        

        queue_idx = rank_int if rank_int < self.fifo_num else self.fifo_num - 1


        if self.fifo_sizes[queue_idx] + pkt.length > self.buffer_per_queue:
            return
        
        element = Element(rank=rank, pkt=pkt, queue_index=queue_idx)

        self.queue.add(element)
        self.fifos[queue_idx].append(element)
        self.fifo_sizes[queue_idx] += pkt.length

    def dequeue(self):

        for queue_idx in range(self.fifo_num):
            fifo = self.fifos[queue_idx]
            if fifo:

                element = fifo.pop(0)
                pkt, rank = element.pkt, element.rank

                self.fifo_sizes[queue_idx] -= pkt.length
                self.SchAlgorithm.post_dequeue(pkt, rank)

                rank_error = self.queue.bisect_left(element)

                self.queue.remove(element)
                return pkt, rank,rank_error


        return None, -1, -1

    def is_empty(self) -> bool:
        return all(len(fifo) == 0 for fifo in self.fifos)

