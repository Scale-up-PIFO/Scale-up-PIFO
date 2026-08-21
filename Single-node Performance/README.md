# Scale-up PIFO Single-node Experiments

This directory contains the single-node simulator implementation used by the Scale-up PIFO artifact.

## Layout

```text
multiPIFO/
  algorithms.py                 scheduling policy definitions
  scheduler.py                  PIFO, Scale-up PIFO, and baseline schedulers
  utils.py                      loader utilities and metric helpers
  single_node_experiments.py    command-line entry point
  algorithms/                   scheduling algorithm configurations
```

## Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

On Windows PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Usage

```bash
cd multiPIFO
python single_node_experiments.py buffer-sweep
python single_node_experiments.py range-count
python single_node_experiments.py update-interval
```

Useful narrow run:

```bash
python single_node_experiments.py buffer-sweep --workloads wfq --schedulers scaleup_pifo,rr_interleaving
```

