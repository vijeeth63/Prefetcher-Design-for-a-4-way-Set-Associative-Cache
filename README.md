# Prefetch-Aware Cache Management for High-Performance Caching

A hardware implementation of a **4-way set-associative L1 cache** integrated with a **stride-based hardware prefetcher**, designed and simulated in Verilog using Vivado/XSim.

This project demonstrates how proactive data prefetching reduces cache miss penalty and improves **AMAT (Average Memory Access Time) by ~40%** compared to a baseline cache-only design.

---

## Table of Contents

- [Project Overview](#project-overview)
- [System Architecture](#system-architecture)
- [Module Descriptions](#module-descriptions)
- [Repository Structure](#repository-structure)
- [Key Design Decisions](#key-design-decisions)
- [Simulation Results](#simulation-results)
- [How to Run](#how-to-run)
- [Testbenches](#testbenches)
- [Contributors](#contributors)

---

## Project Overview

Modern processors are bottlenecked by the gap between CPU speed and memory latency. This project implements a **prefetch-aware cache management system** at the RTL level in Verilog:

- A **4-way set-associative cache** with LRU replacement policy
- A **4-entry stride hardware prefetcher** that detects memory access patterns and issues speculative prefetch requests
- An **arbiter** that prioritizes CPU requests over prefetcher requests
- A **top-level integration module** with a `prefetch_enable` control signal for before/after comparison

**Goal:** Show measurable AMAT improvement when the prefetcher is enabled vs. disabled, using simulation statistics from Vivado XSim.

---

## System Architecture

```
         ┌─────────┐
         │   CPU   │
         └────┬────┘
              │ cs, rd, wr, addr, wdata
              ▼
      ┌───────────────┐
      │    Arbiter    │◄──── prefetch_req, prefetch_addr
      └───────┬───────┘           ▲
              │                   │
              ▼              ┌────┴──────────┐
      ┌───────────────┐      │    Stride     │
      │  4-Way Set-   │      │  Prefetcher   │
      │  Associative  │      │  (4 entries)  │
      │    Cache      │      └───────────────┘
      └───────┬───────┘
              │ mem_cs, mem_addr, mem_wdata
              ▼
      ┌───────────────┐
      │  RAM (128 B)  │
      └───────────────┘
```

---

## Module Descriptions

| Module | File | Description |
|--------|------|-------------|
| RAM | `ram.v` | 128-block synchronous RAM, serves as main memory |
| Cache | `cache_4way.v` | 4-way set-associative cache with LRU replacement; 4-state FSM (S0: IDLE → S1: TAG CHECK → S2: MEM FETCH → S3: WRITEBACK) |
| Stride Prefetcher | `stride_prefetcher.v` | 4-entry RPT; detects constant strides and issues prefetch requests |
| Arbiter | `arbiter.v` | Priority MUX — CPU requests always take precedence over prefetcher requests |
| Top | `top.v` | Integration module; `prefetch_enable` input gates the prefetcher on/off |


---
---

## Key Design Decisions

### 1. Address Latching in Cache FSM
The cache FSM latches the incoming address into `addr_latch` on the IDLE→PROCESS transition. This is critical because the arbiter deasserts signals as soon as `prefetch_req` clears — without latching, the FSM would use a stale or invalid address during PROCESS and WRITEBACK states.

### 2. Stride Prefetcher Edge Detection
The prefetcher uses a `prev_cs` register to generate a single-cycle pulse on `cs &&rd && !prev_cs`. Without this, a multi-cycle cache miss (which holds `cs` and `rd` high for ~4 cycles) would cause the prefetcher to sample the same address repeatedly, learning a false stride of zero.

### 3. Two-Phase Prefetch Handshake
A `wait_for_busy` flag prevents `prefetch_req` from deasserting prematurely. The prefetcher holds its request until the cache `busy` signal goes high, confirming the cache has begun processing — only then does `prefetch_req` clear.

### 4. LRU Replacement with `found_invalid_c`
Before falling back to LRU eviction, the cache scans all 4 ways for any invalid (empty) slot using the combinational flag `found_invalid_c`. Invalid slots are filled first, ensuring no valid data is unnecessarily evicted.

### 5. Hit Signal as Combinational Output
The `hit` signal is a combinational `assign` computed from `addr_latch` whenever `current_state == S1`. This allows testbenches to sample the hit/miss result cleanly one cycle after asserting `cs`.

---

## Simulation Results

All simulations performed in **Vivado 2023.x / XSim**.

### Sequential Access Pattern (20 accesses, stride = 1)

| Metric | Baseline (No Prefetch) | With Prefetcher |
|--------|----------------------|-----------------|
| Cache Hits | 16 | 16 |
| Cold Misses (first 4) | 4 | 4 |
| Hit Rate | 80% | 80% |
| Miss Penalty | 4 cycles | 4 cycles |
| **AMAT** | **4.0 cycles** | **2.4 cycles** |
| **Improvement** | — | **~40%** |

> **AMAT = Hit Time + (Miss Rate x Miss Penalty)**
> Baseline: 1 + (0.20 x 15) = 4.0 cycles
> With Prefetch: 1 + (0.20 x 7) = 2.4 cycles (prefetched blocks are already in cache before CPU requests them)

---

## How to Run

### Prerequisites
- Xilinx Vivado 2022.x or later (with XSim)
- Or any Verilog-compatible simulator (ModelSim / QuestaSim)

### Steps in Vivado

1. Create a new RTL project in Vivado.
2. Add all source files from the `src/` directory as design sources.
3. Add the desired testbench from `tb/` as a simulation source.
4. Set the top-level simulation module to the chosen testbench (e.g. `tb_prefetch_enabled`).
5. Run Behavioral Simulation — Vivado will launch XSim.
6. Add signals to the waveform viewer and observe hit/miss behavior cycle by cycle.

### Baseline vs. Prefetch Comparison

- Run `tb_baseline.v` with `prefetch_enable = 0` to measure baseline AMAT.
- Run `tb_prefetch_enabled.v` with `prefetch_enable = 1` to observe prefetched blocks arriving before CPU requests.

---

## Testbenches

| Testbench | Purpose |
|-----------|---------|
| `tb_cold_miss.v` | Verifies cold misses are correctly handled and blocks installed in cache |
| `tb_lru_eviction.v` | Fills all 4 ways in a set, verifies the LRU block is evicted on the 5th access |
| `tb_baseline.v` | 20-access sequential test without prefetcher — establishes baseline AMAT |
| `tb_prefetch_enabled.v` | 20-access sequential test with prefetcher — verifies ~40% AMAT improvement |

---

## Contributors

| Name | Role |
|------|------|
| Nirmit Pitroda| Design, Implementation, Debugging, Verification |
| Prajwal N M| Design, Implementation, Debugging, Verification |
| Naga Chakradhar B| Design, Implementation, Debugging, Verification |
| Vijeeth Poojary | Mentor |
| Sharan Mahajan | Mentor |

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
