# Validation record

Date: 7 October 2026. Tool: locally installed AMD Vivado/XSim 2024.2.

The standalone regression `scripts/run_tests.ps1` compiled, elaborated and simulated both testbench tops successfully. It checked simulator exit codes and required explicit PASS markers.

```text
PASS tb_mac_pe: exhaustive INT8 products, accumulation, valid, stalls, reset, wrap (131085 steps)
PASS N=8: 20 tiles; Python golden 11x17 * 17x13; padding, K tiling, stalls
PASS N=4: 52 tiles; Python golden 11x17 * 17x13; padding, K tiling, stalls
PASS N=2: 172 tiles; Python golden 11x17 * 17x13; padding, K tiling, stalls
PASS tb_systolic_array: all array sizes passed
ALL TESTS PASSED
```

The PE test checks all 65,536 signed INT8 multiplication pairs independently. Additional tests cover accumulation, two separate operand valid signals, forwarding, global clock enable, synchronous reset and clear. A second PE with ACC_W=16 checks intentional two's-complement wrap without needing a very long INT32 overflow run.

The array tests include a known matrix result, all-zero inputs, -128 and 127 extremes, global stalls, result stability after draining, partial edge tiles, and multiple K chunks. Each array's full 11x13 result is compared with independently generated Python integer results for an 11x17 by 17x13 multiplication. The counts include four directed tiles per array.

The tests do not establish exhaustive array correctness, synthesis quality, maximum clock rate, power, DDR bandwidth, board functionality or Transformer accuracy. No AXI/BRAM/controller hardware exists yet. The testbench supplies scheduling and performs cross-K-tile accumulation.

Generated logs are under `build/xsim/`. They are ignored by Git and can be recreated by the regression script.

The project-mode workflow was also verified with `scripts/run_project_tests.tcl` using Vivado in batch mode. It sources the same project creation and simulation scripts intended for the GUI Tcl Console, runs both tests, closes each simulation to flush its log, checks its PASS marker, and completed with `PASS project Tcl workflow`. The log is `build/project_tests.log`.

Local environment issues resolved during this check: the simulator's bundled GCC required execution outside the agent sandbox because of a Windows DLL relocation error; OneDrive had set generated directories read-only; the batch checker needed to close simulation before reading its buffered log and handle generated waveform configuration changes. No installed Vivado files or filesystem ACLs were changed.
