# SA-LLM: simulation-first systolic accelerator

Start with [the first Vivado lesson](docs/01_FIRST_SIMULATION.md). The [full project guide](docs/PROJECT_GUIDE.md) explains the proposed architecture, concepts, research plan, and later milestones.

## What exists now

| File | Purpose |
|---|---|
| `rtl/mac_pe.sv` | Signed INT8 multiply, INT32 accumulation, registered forwarding, independent operand valids, global stall |
| `rtl/systolic_array.sv` | Parameterized output-stationary N x N array |
| `sim/tb_mac_pe.sv` | Exhaustive INT8 products plus accumulation, validity, reset, stall and reduced-width overflow tests |
| `sim/tb_systolic_array.sv` | 2/4/8 arrays, known example, extremes, stalls, padding, reduction tiling, Python golden comparison |
| `software/generate_vectors.py` | Reproducible independent integer reference; generates the checked-in `.mem` files |
| `scripts/create_project.tcl` | Creates/reopens the Vivado project |
| `scripts/simulate_pe.tcl` | Runs the PE test and adds useful waveforms |
| `scripts/simulate_array.tcl` | Runs all three array configurations |
| `scripts/run_tests.ps1` | Automated xvlog/xelab/xsim regression with PASS/error checks |

Current target: **simulation only**, using installed **Vivado 2024.2**. The project device is `xc7z020clg400-1`, matching the proposed Zybo Z7-20, but no physical board or board files are needed. No pin constraints or bitstream are included.

## Extended tiled-GEMM prototype

The `manual_src` folder contains the later, complete simulation prototype built in Vivado:

- Parameterized 2×2, 4×4, and 8×8 systolic arrays made from signed INT8 MAC processing elements.
- Tile controller, input tile banks, tile loader, K-chunk output accumulator, and GEMM tile scheduler.
- `tiled_gemm_system.sv` for the full tiled data path.
- `compact_tiled_gemm_top.sv`, a board-style wrapper that streams each completed C result into a compact output-memory write interface.
- Unit and end-to-end SystemVerilog testbenches for every block, including edge-tile zero padding, signed data, K accumulation, stalls, and compact output writes.

The final compact wrapper synthesized for `xc7z020clg400-1` using 64 DSP48E1 blocks, about 3,052 LUTs, 4,774 registers, 79 I/O buffers, and met the 100 MHz timing constraint with +4.265 ns worst slack. This remains an educational prototype: it does not yet provide an AXI/DDR software interface or a complete Transformer/LLM runtime.


5. Synthesizable tile controller and explicit `start/busy/done` protocol.
6. Banked synchronous memories and latency-aware scheduling.
7. AXI control/streaming verification, then board integration.

See `docs/PROJECT_GUIDE.md` for the remaining Transformer stages and phase exit criteria.
