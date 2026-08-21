<h1 align="center">
  <br>
  Scale-up PIFO
  <br>
</h1>

<p align="center">
  A scalable packet scheduler built from multiple parallel PIFOs and a
  range-based round-robin load balancer.
</p>


## 🕶️ Overview

Scale-up PIFO approximates one large logical PIFO with several smaller physical PIFOs. On enqueue, the packet rank selects a contiguous rank range. A per-range round-robin counter then selects the physical PIFO. On dequeue, the physical PIFOs are visited in a fixed round-robin order. Periodically uploaded range counters drive the border-adjustment logic.

The P4 programs implement the RRLB core on a Tofino switch. Because Tofino does not provide an exact PIFO primitive, the P4 prototype does not implement the complete PIFO datapath. The FPGA `PUSH_LB` module similarly uses a FIFO array as an integration and timing harness around the RRLB core.


## 📖 License

This project is released under the [GNU General Public License v2.0 only](LICENSE) (`GPL-2.0-only`).
