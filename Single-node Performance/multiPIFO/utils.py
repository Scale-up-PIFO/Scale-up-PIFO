import ast
import math
import re
from typing import Iterable

from algorithms import FifoAlgorithm, SpAlgorithm, pFabricAlgorithm, WFQAlgorithm, WFQPCQAlgorithm
from packet import Pkt


def load_trace_from_file(filename, max_flow_num=None):
    packets = []
    with open(filename, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split()
            if not parts:
                continue
            if len(parts) != 4:
                raise ValueError(f"Invalid trace line in {filename}: {line!r}")
            pktid = int(parts[0])
            flowid = int(parts[1])
            length = int(parts[2])
            flow_size = round(float(parts[3]))
            if max_flow_num is not None and max_flow_num > 0:
                flowid = (flowid % max_flow_num) + 1
            packets.append(Pkt(pktid, flowid, length, flow_size))
    return packets


def string_to_algorithm(algorithm_str):
    algorithm_str = algorithm_str.strip()
    if algorithm_str == "FifoAlgorithm()":
        return FifoAlgorithm()
    if algorithm_str == "pFabricAlgorithm()":
        return pFabricAlgorithm()
    if algorithm_str.startswith("WFQAlgorithm("):
        value = algorithm_str[len("WFQAlgorithm("):-1]
        return WFQAlgorithm(ast.literal_eval(value))
    if algorithm_str.startswith("SpAlgorithm("):
        value = algorithm_str[len("SpAlgorithm("):-1]
        return SpAlgorithm(ast.literal_eval(value))
    if algorithm_str.startswith("WFQPCQAlgorithm"):
        match = re.match(r"WFQPCQAlgorithm(\d+)\((.*)\)$", algorithm_str)
        if not match:
            raise ValueError(f"Invalid WFQPCQAlgorithm format: {algorithm_str}")
        bpr = int(match.group(1))
        weights = ast.literal_eval(match.group(2))
        return WFQPCQAlgorithm(weights, BpR=bpr)
    raise ValueError(f"Cannot parse scheduling algorithm: {algorithm_str}")


def load_algorithm_from_file(filename):
    with open(filename, "r", encoding="utf-8") as f:
        return string_to_algorithm(f.read())


def percentile(values, p):
    if not values:
        return 0.0
    sorted_values = sorted(values)
    if len(sorted_values) == 1:
        return float(sorted_values[0])
    rank = (len(sorted_values) - 1) * p / 100
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return float(sorted_values[int(rank)])
    weight = rank - lower
    return float(sorted_values[lower] * (1 - weight) + sorted_values[upper] * weight)


def summarize(values):
    if not values:
        return {"avg": 0.0, "p99": 0.0, "max": 0.0}
    return {
        "avg": float(sum(values) / len(values)),
        "p99": percentile(values, 99),
        "max": float(max(values)),
    }


def calculate_sequence_error_pkt_ver(baseline_pkts, target_pkts):
    baseline_positions = {pkt.pktid: idx for idx, pkt in enumerate(baseline_pkts)}
    errors = []
    for idx, pkt in enumerate(target_pkts):
        if pkt.pktid in baseline_positions:
            errors.append(max(0, idx - baseline_positions[pkt.pktid]))
    return summarize(errors)


def calculate_sequence_error_pkt_ver_common(baseline_pkts, target_pkts):
    baseline_ids = {pkt.pktid for pkt in baseline_pkts}
    target_ids = {pkt.pktid for pkt in target_pkts}
    common_ids = baseline_ids & target_ids
    baseline_common = [pkt for pkt in baseline_pkts if pkt.pktid in common_ids]
    target_common = [pkt for pkt in target_pkts if pkt.pktid in common_ids]
    baseline_positions = {pkt.pktid: idx for idx, pkt in enumerate(baseline_common)}
    errors = []
    for idx, pkt in enumerate(target_common):
        errors.append(max(0, idx - baseline_positions[pkt.pktid]))
    return summarize(errors)


def _should_enqueue(mode, input_count, input_bytes, output_count, output_bytes, congestion_ratio):
    if mode == "pkt":
        return input_count < (output_count + 1) * congestion_ratio
    if mode == "bit":
        return input_bytes < output_bytes * congestion_ratio + 1500
    raise ValueError(f"Unsupported mode: {mode}")


def _normalize_dequeue_result(result, return_mode):
    if return_mode == "with_delay":
        pkt, rank, rank_error, delay = result
        return pkt, rank, rank_error, delay
    pkt, rank, rank_error = result
    return pkt, rank, rank_error, None


def process_scheduler(scheduler, input_packets, congestion_ratio, mode="pkt", return_mode="basic"):
    output_packets = []
    ranks = []
    rank_errors = []
    delays = []
    input_count = output_count = 0
    input_bytes = output_bytes = 0

    while input_packets or not scheduler.is_empty():
        should_input = False
        if input_packets:
            should_input = _should_enqueue(
                mode, input_count, input_bytes, output_count, output_bytes, congestion_ratio
            )
        if scheduler.is_empty() and not should_input:
            should_input = True
        if should_input and input_packets:
            pkt = input_packets.pop(0)
            scheduler.enqueue(pkt)
            input_count += 1
            input_bytes += pkt.length
            continue

        pkt, rank, rank_error, delay = _normalize_dequeue_result(
            scheduler.dequeue(), return_mode
        )
        if pkt is None:
            continue
        output_packets.append(pkt)
        ranks.append(rank)
        rank_errors.append(rank_error)
        if return_mode == "with_delay":
            delays.append(delay)
        output_count += 1
        output_bytes += pkt.length

    if return_mode == "with_delay":
        return output_packets, ranks, rank_errors, delays
    return output_packets, ranks, rank_errors


def order_evaluation(
    baseline_scheduler,
    target_scheduler,
    packets,
    congestion_ratio=2,
    mode="pkt",
    return_mode="basic",
):
    if not packets:
        return {}

    if return_mode == "with_delay":
        baseline_output, baseline_ranks, baseline_rank_errors, baseline_delays = process_scheduler(
            baseline_scheduler, packets.copy(), congestion_ratio, mode, return_mode
        )
        target_output, target_ranks, target_rank_errors, target_delays = process_scheduler(
            target_scheduler, packets.copy(), congestion_ratio, mode, return_mode
        )
    else:
        baseline_output, baseline_ranks, baseline_rank_errors = process_scheduler(
            baseline_scheduler, packets.copy(), congestion_ratio, mode, return_mode
        )
        target_output, target_ranks, target_rank_errors = process_scheduler(
            target_scheduler, packets.copy(), congestion_ratio, mode, return_mode
        )

    input_count = len(packets)
    output_count = len(target_output)
    output_count_base = len(baseline_output)
    baseline_ids = {pkt.pktid for pkt in baseline_output}
    target_ids = {pkt.pktid for pkt in target_output}
    extra_dropped_count = len(baseline_ids - target_ids)
    input_total_bytes = sum(pkt.length for pkt in packets)
    output_total_bytes = sum(pkt.length for pkt in target_output)
    output_total_bytes_base = sum(pkt.length for pkt in baseline_output)

    result = {
        "baseline_output": baseline_output,
        "target_output": target_output,
        "pkt_error": calculate_sequence_error_pkt_ver(baseline_output, target_output),
        "pkt_error_common": calculate_sequence_error_pkt_ver_common(baseline_output, target_output),
        "packet_stats": {
            "input_count": input_count,
            "output_count": output_count,
            "output_count_base": output_count_base,
            "loss_rate": (input_count - output_count) * 100 / input_count,
            "loss_rate_base": (input_count - output_count_base) * 100 / input_count,
            "drop_error_ratio": extra_dropped_count * 100 / input_count,
            "input_total_bytes": input_total_bytes,
            "output_total_bytes": output_total_bytes,
            "output_total_bytes_base": output_total_bytes_base,
            "output_byte_ratio": output_total_bytes * 100 / input_total_bytes,
            "output_byte_ratio_base": output_total_bytes_base * 100 / input_total_bytes,
        },
        "rank_error": {
            "baseline": baseline_rank_errors,
            "target": target_rank_errors,
        },
    }
    if return_mode == "with_delay":
        result["delays"] = {"baseline": baseline_delays, "target": target_delays}
        result["ranks"] = {"baseline": baseline_ranks, "target": target_ranks}
    return result


def compact_metrics(result):
    packet_stats = result["packet_stats"]
    target_rank_error = result["rank_error"]["target"]
    return {
        "loss_rate_base": packet_stats["loss_rate_base"],
        "loss_rate": packet_stats["loss_rate"],
        "loss_error": packet_stats["drop_error_ratio"],
        "rank_error": summarize(target_rank_error),
        "pkt_error": result["pkt_error"],
        "pkt_error_common": result["pkt_error_common"],
    }


def mean_ignore_none(values: Iterable[float]):
    clean = [value for value in values if value is not None and not math.isnan(value)]
    return float(sum(clean) / len(clean)) if clean else None
