# Lesson 1: from a multiply to a systolic array

This lesson matches the RTL in this repository. You can do it entirely in Vivado 2024.2 without a board.

## 1. Three different languages/tools

**SystemVerilog** describes a circuit. A clocked `always @(posedge clk)` block describes registers that update at a rising clock edge. Many such blocks operate concurrently. It is not a C program executing one PE after another.

**A testbench** is SystemVerilog used only in simulation. It creates a clock, supplies inputs, calculates expected values, and stops when a mismatch occurs. Constructs such as `#5`, `$display`, `$readmemh`, and `$finish` here are simulation infrastructure, not the future accelerator controller.

**Tcl** is the command language that controls Vivado. `create_project` creates a project; `add_files` registers source files; `set_property top` selects the module to simulate; `launch_simulation` compiles and starts XSim; `run all` advances simulation until the test finishes. AMD documents this flow in [UG835](https://docs.amd.com/r/2023.2-English/ug835-vivado-tcl-commands/launch_simulation).

Simulation checks behavior. Synthesis turns RTL into FPGA resources. Implementation places and routes those resources. Timing analysis checks whether signals settle before the next clock edge. Generating a bitstream and programming hardware come after those steps.

## 2. Run the first experiment

Open Vivado, save any existing work, and close any other project. Find the **Tcl Console** at the bottom of the Vivado window. These commands belong there, not in Windows PowerShell:

```tcl
cd {C:/Users/HP/OneDrive/Documents/ChatGPT/SYSTOLIC ARRAY HARDWARE ACCELERATor}
source scripts/create_project.tcl
source scripts/simulate_pe.tcl
```

Braces keep the path with spaces together as one Tcl argument. `source` executes commands from a file. The generated project lives under `build/vivado/sa_llm.xpr`; source files stay in `rtl/` and `sim/`.

Read the console. Success requires a line starting `PASS tb_mac_pe:` and no fatal error. A `$finish` message is normal at the end of a passing test. A `$fatal` is a failed test. Keep the full first error when diagnosing a failure.

The complete test runs for about 1.31 milliseconds of **simulated time**, so zoom into the beginning of the waveform. Wall-clock execution time on your PC is a different quantity.

To return to the first few cycles:

```tcl
restart
run 160 ns
```

Use Zoom Fit in the waveform window and set `a`, `b`, and `acc` to signed decimal. Hexadecimal `FE` is -2 for signed INT8, and `80` is -128; the bits are unchanged when you change display radix.

## 3. What the processing element does

A **PE**, or processing element, is one small arithmetic cell:

```text
 signed A ---> [forward register] ---> next PE to the right
       \ 
        [signed multiply] ---> [add] ---> [ACC register]
       /                        ^              |
 signed B                       +--------------+
       |
       +----> [forward register] ---> next PE below
```

Its equation is `acc_next = acc + a*b`. The sum remains in this PE, so this is **output-stationary** dataflow.

| Signal | Meaning in this implementation |
|---|---|
| `clk` | Common clock; rising edges update registers |
| `rst` | Active-high synchronous reset; clears all PE state |
| `clear` | Clears sum, forwarded data, and valids before a new tile |
| `ce` | Clock enable; 0 freezes all state together |
| `a_in`, `b_in` | Signed 8-bit operands, -128 through 127 |
| `a_valid_in`, `b_valid_in` | Indicate that each input contains an operand belonging to the schedule |
| `a_out`, `b_out` | Registered copies forwarded right and down |
| `a_valid_out`, `b_valid_out` | Registered validity travelling with the data |
| `acc` | Signed 32-bit accumulated result |

Priority is reset/clear, then enable, then multiplication validity. Reset and clear therefore work even if `ce=0`. Data forwarding happens on every enabled edge; accumulation happens only if **both** input valids are high. Zero is a valid operand; invalid means no operand, not the number zero.

At the first non-reset steps, the test applies:

| Step | Inputs/control | Accumulator after the edge |
|---|---|---:|
| 1 | reset | 0 |
| 2 | 3 x 4, both valid | 12 |
| 3 | -2 x 5, both valid | 2 |
| 4 | -128 x -128, but ce=0 | 2 |
| 5 | 7 x 9, B invalid | 2 |
| 6 | 7 x 9, A invalid | 2 |
| 7 | clear=1, ce=0 | 0 |

Read `rtl/mac_pe.sv` alongside these waveforms. `wire signed [15:0] product` stores the 16-bit product. Replicating the product sign bit extends it to 32 bits without changing its value. Nonblocking assignment `<=` means every register uses the values present before the edge, then updates together. This gives exactly one registered hop per enabled clock edge.

The accumulator is wider because many products are added. This design wraps on overflow; it does not saturate. The tests also instantiate a 16-bit accumulator to make overflow easy to observe. For example, two products `(-128)*(-128)` sum to 32768, represented as -32768 after signed 16-bit wrap.

This first PE has a combinational multiply/add path into the accumulator register. It accepts one operand pair per enabled cycle, but it is **not** a separately pipelined multiplier followed by an adder. Later timing measurements decide whether extra pipeline stages are necessary. Adding registers changes the scheduling equations and tests.

## 4. Matrix multiplication

For A with shape M x K and B with shape K x P, C has shape M x P:

`C[i,j] = sum(k=0..K-1) A[i,k] * B[k,j]`.

The shared dimension K is the dot-product length. It must match; matrix multiplication is not element-by-element multiplication.

```text
A = [1 2]     B = [5 6]     C = [19 22]
    [3 4]         [7 8]         [43 50]

C00 = 1*5 + 2*7 = 19
C01 = 1*6 + 2*8 = 22
C10 = 3*5 + 4*7 = 43
C11 = 3*6 + 4*8 = 50
```

A 2 x 2 array has four PEs. PE00 calculates C00, PE01 C01, and so on. A flows horizontally and B vertically:

```text
                B column 0     B column 1
                     |              |
A row 0 ---------> [PE00] -------> [PE01]
                     |              |
A row 1 ---------> [PE10] -------> [PE11]
```

## 5. Why the inputs must be skewed

Each hop takes one enabled clock edge. Therefore feed row r of A with a delay of r cycles, and column c of B with a delay of c cycles. At boundary step t:

`A_left[r] = A[r,t-r]` if `0 <= t-r < K`;

`B_top[c] = B[t-c,c]` if `0 <= t-c < K`.

All other boundary inputs have valid=0. The controller/testbench must ensure the A and B operands arriving at a PE have the same k index. Valid bits alone do not check their identities.

After clearing the array, the example uses this schedule. A dash means invalid. Each row shows inputs consumed at that rising edge and sums **after** it:

| Enabled edge t | A left row0,row1 | B top col0,col1 | C00 | C01 | C10 | C11 |
|---:|---|---|---:|---:|---:|---:|
| 0 | 1, - | 5, - | 5 | 0 | 0 | 0 |
| 1 | 2, 3 | 7, 6 | 19 | 6 | 15 | 0 |
| 2 | -, 4 | -, 8 | 19 | 22 | 43 | 18 |
| 3 | -, - | -, - | 19 | 22 | 43 | 50 |

The final edge is needed even though boundary inputs are invalid: previously registered operands are still moving through the array. This is **draining the pipeline**.

For this exact RTL, PE[r,c] consumes product k at enabled edge `t=k+r+c`. The final product reaches PE[N-1,N-1] at `t=K+2N-3`. Counting from edge 0 gives **K+2N-2 enabled compute edges**. Clearing, reading results, loading buffers, and any stalls are additional overhead. For N=8, K=8 this is 22 compute edges, not 8.

Setting `ce=0` pauses the whole array. The scheduler must also pause t and keep the boundary inputs stable. Independently pausing one PE is not supported by this first architecture.

## 6. Run the array experiment

```tcl
source scripts/simulate_array.tcl
```

The testbench creates three separate simulated arrays concurrently: N=2, N=4, N=8. This does not mean the eventual FPGA must contain all three arrays; later each parameter choice is a separate synthesis experiment.

Expected pass markers:

```text
PASS N=8: ...
PASS N=4: ...
PASS N=2: ...
PASS tb_systolic_array: all array sizes passed
```

Do not rely on their order. The 2 x 2 array needs more tiles and usually finishes last. The example output is the top-left 2 x 2 block; the remaining entries are zero for the larger arrays.

`c_flat` packs results in row-major order. C[r,c] occupies bits starting at `(r*N+c)*32`. For N=2: bits 31:0 contain 19, bits 63:32 contain 22, bits 95:64 contain 43, and bits 127:96 contain 50. Each slice must be interpreted as signed separately.

## 7. What tiling means in the tests

The Python generator produces A[11,17], B[17,13], and C[11,13]. None of these dimensions neatly matches all the array sizes. The testbench loads submatrices, supplies zero padding at the edges, and splits K into chunks of at most 5. For each chunk it clears the hardware array, runs it, reads the partial sums, and adds those into an integer host-side output matrix.

This demonstrates `C_tile = sum over k_tiles (A_tile * B_tile)`. Clearing the array between K chunks without saving and adding those partial results would be a bug. The current design uses the testbench to add them; a later hardware controller/output buffer will take over.

This is a functional arithmetic regression, not a measurement of a DDR-connected accelerator. Additional idle/drain edges deliberately make bugs visible and are not an optimized throughput schedule.

## 8. Next lesson and exit criteria

Before adding a hardware controller, you should be able to explain why 2 x 2 multiplication takes four enabled edges for K=2, why row 1 is delayed, why an invalid operand does not accumulate, and why a stalled cycle does not advance the schedule.

The next module is `tile_controller.sv` with states `IDLE -> CLEAR -> FEED/DRAIN -> DONE`, explicit start/busy/done signals, and cycle counting. Then add synchronous BRAM reads and adjust the input schedule for their read latency. Do not jump directly from the raw arithmetic core to DMA.
