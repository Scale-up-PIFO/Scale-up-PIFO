import argparse
import json
from pathlib import Path

from scheduler import (
    AIFOScheduler,
    DynamicIntervalRRPIFOScheduler,
    GearboxScheduler,
    IdealPIFOScheduler,
    PacksScheduler,
    RRInterleavingPIFOScheduler,
    SPPIFOScheduler,
    SPPCQScheduler,
    WFQPCQScheduler,
)
from utils import compact_metrics, load_algorithm_from_file, load_trace_from_file, mean_ignore_none, order_evaluation


BASE_DIR = Path(__file__).resolve().parent
ALGORITHM_DIR = BASE_DIR / "algorithms"
TRACE_DIR = BASE_DIR / "traces"
RESULT_DIR = BASE_DIR / "results"

WORKLOADS = {
    "wfq": {
        "figure": "Figure 11",
        "algorithm": "3.txt",
        "interval_total_length": 5_000_000,
        "pcq_algorithm": "22.txt",
    },
    "sp": {
        "figure": "Figure 15",
        "algorithm": "13.txt",
        "interval_total_length": 50,
        "pcq_algorithm": "13.txt",
    },
    "sff": {
        "figure": "Figure 16",
        "algorithm": "21.txt",
        "interval_total_length": 24_638_255,
        "pcq_algorithm": "21.txt",
    },
}

BUFFER_TRACES_MB = {
    20: "Trace3_80.txt",
    40: "Trace3_160.txt",
    60: "Trace3_240.txt",
    80: "Trace3_320.txt",
    100: "Trace3_400.txt",
}


def algorithm_path(name):
    return ALGORITHM_DIR / name


def load_algorithm(name):
    return load_algorithm_from_file(algorithm_path(name))


def make_ideal(workload, buffer_size):
    return IdealPIFOScheduler(load_algorithm(WORKLOADS[workload]["algorithm"]), buffer_size=buffer_size)


def make_scheduler(label, workload, buffer_size, interval_total_length=None, num_intervals=16, adjust_period=100000):
    spec = WORKLOADS[workload]
    algorithm_name = spec["algorithm"]
    interval_total_length = interval_total_length or spec["interval_total_length"]
    if label == "scaleup_pifo":
        return DynamicIntervalRRPIFOScheduler(
            load_algorithm(algorithm_name),
            num_pifos=4,
            num_load_balancers=2,
            interval_total_length=interval_total_length,
            num_intervals=num_intervals,
            adjust_period=adjust_period,
            pifo_buffer_size=buffer_size,
        )
    if label == "rr_interleaving":
        return RRInterleavingPIFOScheduler(load_algorithm(algorithm_name), PIFO_num=4, buffer_size=buffer_size)
    if label == "gearbox":
        return GearboxScheduler(load_algorithm(spec["pcq_algorithm"]), buffer_size=buffer_size)
    if label == "sp_pifo":
        return SPPIFOScheduler(load_algorithm(algorithm_name), fifo_num=8, buffer_size=buffer_size)
    if label == "aifo":
        return AIFOScheduler(load_algorithm(algorithm_name), window_size=1000, k=0, buffer_size=buffer_size)
    if label == "packs":
        return PacksScheduler(load_algorithm(algorithm_name), window_size=1000, fifo_num=8, k=0, buffer_size=buffer_size)
    if label == "pcq":
        if workload == "sp":
            return SPPCQScheduler(load_algorithm(spec["pcq_algorithm"]), fifo_num=56, buffer_size=buffer_size)
        return WFQPCQScheduler(load_algorithm(spec["pcq_algorithm"]), fifo_num=56, buffer_size=buffer_size)
    raise ValueError(f"Unknown scheduler label: {label}")


def evaluate_scheduler(label, workload, packets, buffer_size, interval_total_length=None, num_intervals=16, adjust_period=100000):
    ideal = make_ideal(workload, buffer_size)
    target = make_scheduler(
        label,
        workload,
        buffer_size,
        interval_total_length=interval_total_length,
        num_intervals=num_intervals,
        adjust_period=adjust_period,
    )
    result = order_evaluation(ideal, target, packets.copy(), congestion_ratio=2, mode="pkt")
    return compact_metrics(result)


def limit_packets(packets, packet_limit):
    if packet_limit and packet_limit > 0:
        return packets[:packet_limit]
    return packets


def run_buffer_sweep(workloads, schedulers, output, buffers=None, packet_limit=0):
    RESULT_DIR.mkdir(exist_ok=True)
    buffer_traces = BUFFER_TRACES_MB
    if buffers is not None:
        buffer_traces = {buffer_mb: BUFFER_TRACES_MB[buffer_mb] for buffer_mb in buffers}
    results = {}
    for workload in workloads:
        results[workload] = {"figure": WORKLOADS[workload]["figure"], "buffers": {}}
        for buffer_mb, trace_name in buffer_traces.items():
            packets = limit_packets(load_trace_from_file(TRACE_DIR / trace_name, max_flow_num=50), packet_limit)
            buffer_size = buffer_mb * 1024 * 1024
            results[workload]["buffers"][str(buffer_mb)] = {}
            for scheduler_label in schedulers:
                print(f"{workload} {buffer_mb}MB {scheduler_label}")
                metrics = evaluate_scheduler(scheduler_label, workload, packets, buffer_size)
                results[workload]["buffers"][str(buffer_mb)][scheduler_label] = metrics
    write_json(output, results)
    return results


def run_range_count(trace, interval_counts, output, packet_limit=0):
    RESULT_DIR.mkdir(exist_ok=True)
    packets = limit_packets(load_trace_from_file(trace, max_flow_num=50), packet_limit)
    buffer_size = 10 * 1024 * 1024
    results = {"interval_counts": interval_counts}
    for workload, spec in WORKLOADS.items():
        values = []
        for num_intervals in interval_counts:
            print(f"{workload} interval_count={num_intervals}")
            metrics = evaluate_scheduler(
                "scaleup_pifo",
                workload,
                packets,
                buffer_size,
                interval_total_length=spec["interval_total_length"],
                num_intervals=num_intervals,
            )
            values.append(metrics["rank_error"]["avg"])
        results[workload] = values
    write_json(output, results)
    plot_parameter_curve(results, "interval_counts", output.with_suffix(".png"), "Number of Ranges")
    return results


def run_update_interval(trace, frequencies, output, packet_limit=0):
    RESULT_DIR.mkdir(exist_ok=True)
    packets = limit_packets(load_trace_from_file(trace, max_flow_num=50), packet_limit)
    buffer_size = 10 * 1024 * 1024
    results = {"frequency": frequencies}
    for workload, spec in WORKLOADS.items():
        values = []
        for frequency in frequencies:
            print(f"{workload} update_interval={frequency}")
            metrics = evaluate_scheduler(
                "scaleup_pifo",
                workload,
                packets,
                buffer_size,
                interval_total_length=spec["interval_total_length"],
                num_intervals=16,
                adjust_period=frequency,
            )
            values.append(metrics["rank_error"]["avg"])
        results[workload] = values
    write_json(output, results)
    plot_parameter_curve(results, "frequency", output.with_suffix(".png"), "Update Interval")
    return results


def plot_parameter_curve(data, x_key, output_png, xlabel):
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib is not installed; skipped PNG plot generation")
        return

    x_values = data[x_key]
    plt.figure(figsize=(7, 4.5))
    for workload in WORKLOADS:
        values = data.get(workload)
        if values:
            plt.plot(x_values, values, marker="o", label=workload.upper())
    plt.xlabel(xlabel)
    plt.ylabel("Average Rank Error")
    plt.grid(True, linestyle="--", alpha=0.4)
    plt.legend()
    plt.tight_layout()
    plt.savefig(output_png, dpi=200)
    plt.close()


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    print(f"wrote {path}")


def parse_list(values, cast=str):
    return [cast(value.strip()) for value in values.split(",") if value.strip()]


def main():
    parser = argparse.ArgumentParser(description="Single-node experiments for the Scale-up PIFO paper.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    buffer_parser = subparsers.add_parser("buffer-sweep")
    buffer_parser.add_argument("--workloads", default="wfq,sp,sff")
    buffer_parser.add_argument(
        "--schedulers",
        default="scaleup_pifo,rr_interleaving,gearbox,sp_pifo,aifo,packs,pcq",
    )
    buffer_parser.add_argument("--buffers", default="20,40,60,80,100")
    buffer_parser.add_argument("--packet-limit", type=int, default=0)
    buffer_parser.add_argument("--output", type=Path, default=RESULT_DIR / "buffer_sweep.json")

    range_parser = subparsers.add_parser("range-count")
    range_parser.add_argument("--trace", type=Path, default=TRACE_DIR / "Trace3.txt")
    range_parser.add_argument("--interval-counts", default="2,4,8,16,24,32,48,64")
    range_parser.add_argument("--packet-limit", type=int, default=0)
    range_parser.add_argument("--output", type=Path, default=RESULT_DIR / "range_count.json")

    update_parser = subparsers.add_parser("update-interval")
    update_parser.add_argument("--trace", type=Path, default=TRACE_DIR / "Trace3.txt")
    update_parser.add_argument("--frequencies", default="10,50,100,500,1000,5000,10000")
    update_parser.add_argument("--packet-limit", type=int, default=0)
    update_parser.add_argument("--output", type=Path, default=RESULT_DIR / "update_interval.json")

    args = parser.parse_args()
    if args.command == "buffer-sweep":
        run_buffer_sweep(
            parse_list(args.workloads),
            parse_list(args.schedulers),
            args.output,
            parse_list(args.buffers, int),
            args.packet_limit,
        )
    elif args.command == "range-count":
        run_range_count(
            args.trace,
            parse_list(args.interval_counts, int),
            args.output,
            args.packet_limit,
        )
    elif args.command == "update-interval":
        run_update_interval(
            args.trace,
            parse_list(args.frequencies, int),
            args.output,
            args.packet_limit,
        )


if __name__ == "__main__":
    main()
