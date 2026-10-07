# SA-LLM project development guide

Working title: **Design and Evaluation of a Quantized GEMM/GEMV Accelerator for Tiny Transformer Inference on Zynq**.

The current deliverable is the simulated arithmetic core. All AXI, memory, ARM, model and board features below are a **proposed roadmap**, not claims of implemented functionality. Begin with [Lesson 1](01_FIRST_SIMULATION.md), then work through this guide as each module is introduced. The board is a future target; no physical board is required for the current tests.

## 1. Project overview

Build a small custom matrix engine in RTL, verify it numerically, connect it to memory and a processor, and use it for selected operations in a tiny Transformer. A systolic array is the initial engine. A specialized matrix-vector engine is a later experiment motivated by autoregressive decoding.

Success means a reproducible accelerator architecture, correct software/hardware integration, and honest performance measurements. Text generation is a useful final demonstration, but is not by itself evidence of acceleration or novelty.

## 2. Problem statement

Matrix operations dominate many Transformer linear layers, but their shapes vary. During prompt processing, multiple token vectors can reuse a weight matrix. During batch-one decoding, each layer often processes only one vector. A two-dimensional array may therefore have different efficiency in these two cases. The research question is how to allocate limited arithmetic and memory resources to both workloads.

## 3. Motivation

This project joins digital design, computer architecture, embedded software and numerical methods. It makes useful tradeoffs measurable: more PEs versus memory bandwidth, narrow integers versus model accuracy, and specialized hardware versus software flexibility. A meaningful report explains where acceleration helps, where transfers erase the benefit, and why.

## 4. Why FPGA?

An FPGA implements configurable parallel circuits. Its DSP blocks accelerate arithmetic, flip-flops hold state, LUTs implement logic, and BRAM provides local storage. Custom widths and data movement are the main opportunities. Costs include long build times, finite on-chip storage and demanding verification. A small FPGA should not be expected to outperform a modern GPU on general LLM inference.

## 5. Why systolic arrays?

A systolic array passes operands between neighboring arithmetic cells on clock edges. An activation can be used by several columns and a weight by several rows, reducing repeated reads from a central buffer. Regular local connections are easier to scale than broadcasting all operands everywhere.

| Dataflow | Value retained locally | Main tradeoff |
|---|---|---|
| Output stationary | Partial output sum | Simple accumulation; A and B stream through |
| Weight stationary | Weight for repeated activation use | Requires weight-loading and partial-sum movement |
| Input stationary | Activation reused across weight/output work | Requires scheduling of weights and partial sums |

Use output stationary first. It naturally gives one C element per PE and avoids a partial-sum network. None of these dataflows is universally best; actual memory traffic and workload shapes decide.

## 6. Why Zybo Z7-20?

The proposed part is `xc7z020clg400-1`. The board combines a dual-core ARM Cortex-A9 PS with FPGA PL and 1 GB DDR3L. The Z7-20 has 53,200 LUTs, 106,400 flip-flops and nominal 630 KiB of BRAM capacity. See the [Digilent board manual](https://digilent.com/reference/_media/reference/programmable-logic/zybo-z7/zybo-z7_rm.pdf) and [part definition](https://github.com/Digilent/vivado-boards/blob/master/new/board_files/zybo-z7-20/A.0/board.xml).

This allows a software runtime and a custom engine in one device. The Nexys A7 is an alternative for PL experiments, but it lacks this integrated ARM processing system, so the host architecture would change. Current simulation does not depend on either board.

## 7. Transformer/LLM fundamentals

A tokenizer maps text into token IDs. An embedding table maps each ID into a learned vector. A Transformer block transforms those vectors using attention and a feed-forward network. The final classifier produces a score (logit) for each vocabulary token; sampling chooses the next token.

For token matrix X[T,d] and linear-layer weight W[d,o], `Y=XW`. Some model files store W[o,d]; explicitly transpose or change packing rather than silently using the wrong layout.

A typical Llama-style block performs:

```text
X -> RMSNorm -> Q,K,V projections -> RoPE(Q,K)
                            |             |
                            +-> causal attention -> output projection
X ------------------------------------------------------> add -> H
H -> RMSNorm -> up/gate projections -> SiLU(gate)*up -> down projection
H ------------------------------------------------------> add -> next X
```

Attention is `softmax(Q K^T / sqrt(d_head) + causal_mask) V`. The causal mask prevents a token from attending to future tokens. RMSNorm is `gamma*x/sqrt(mean(x^2)+epsilon)`; it rescales without subtracting the mean. LayerNorm subtracts the mean and uses variance instead, and is only needed if the chosen model uses it.

RoPE rotates pairs of query/key coordinates according to position. For a pair `(u,v)` and angle theta: `(u*cos(theta)-v*sin(theta), u*sin(theta)+v*cos(theta))`. SiLU is `x/(1+exp(-x))`. SwiGLU multiplies a SiLU-transformed gate projection with another projection before the down projection. Residual addition preserves an earlier representation while adding the learned update.

| Operation | Prefill | Batch-one decoding | Initial placement |
|---|---|---|---|
| Tokenization, token sampling | Software/control | Software/control | ARM |
| Embedding lookup | Memory gather | Memory gather | ARM/DDR |
| Q/K/V and output projections | GEMM | GEMV | FPGA after verification |
| RMSNorm / LayerNorm | Reduction + nonlinear + vector | Same | ARM first |
| RoPE | Vector arithmetic | Vector arithmetic | ARM first, optional PL |
| QK transpose product | Batched/head GEMM | Dot products or GEMV | ARM first |
| Mask and stable softmax | Vector + nonlinear + reduction | Same | ARM first |
| Attention times V | GEMM | Vector-matrix product | ARM first |
| FFN up/gate/down projections | GEMM | GEMV | FPGA |
| SiLU / SwiGLU | Nonlinear + elementwise | Same | ARM first |
| Residual add | Vector | Vector | ARM, later simple PL ALU |
| Final vocabulary projection | GEMM if all logits needed | GEMV | FPGA candidate |
| KV append/read | Memory | Memory | DDR, BRAM cache later |

Each label describes mathematics, not an obligation to implement it in hardware. Small kernels can be slower after transfer and launch overhead.

## 8. Proposed architecture

Use the PS for model ownership, tokenization, sampling and scheduling. Use the PL for selected kernels. Keep FP32 nonlinear operations in software initially, quantize inputs before the accelerator, and dequantize its INT32 outputs before returning to the software graph.

Do not implement three large engines at once. First establish a matrix engine with a stable command/data interface. Later compare a separate GEMV datapath against a configurable shared MAC pool at equal resource budgets.

## 9. Detailed block diagram

```text
PC terminal <---- UART/Ethernet ----> ARM PS
                                   tokenizer / runtime / scheduler
                                        | control via GP AXI
                                        v
                         AXI4-Lite control/status registers
                                        |
                           command and buffer scheduler
                                        |
                     +------------------+------------------+
                     |                  |                  |
                GEMM array         GEMV lanes        vector unit
                     |                  |             (optional)
                     +------------------+------------------+
                                        |
                         banked BRAM scratchpads / FIFOs
                                        |
                               AXI4-Stream packets
                                        |
                               AXI DMA MM2S / S2MM
                                        |
                         AXI interconnect / protocol conversion
                                        |
                                   PS HP port
                                        |
                               PS DDR controller
                                        |
                         shared DDR: weights, tensors, KV cache
```

Control, streaming data and DDR access are different paths. PS also accesses DDR directly. The board's DDR is attached to the PS controller; do not add a PL MIG controller for this same memory.

## 10. Processing element architecture

The implemented PE has signed DATA_W-bit A/B inputs, separate validity signals, ACC_W-bit sum, registered A/B forwarding, synchronous reset/clear and a global enable. Default arithmetic is INT8 x INT8 -> INT32.

Each enabled edge consumes the current inputs, adds their product when both are valid, and forwards them. All registers use nonblocking assignments. The product is explicitly signed and sign-extended. ACC_W must be at least 2*DATA_W. Overflow wraps; saturation is a later explicit conversion operation, not an assumed property of Verilog.

The accumulator stays inside the PE; a partial-sum input is unnecessary for this dataflow. If future K tiling retains sums inside PEs, separate pipeline flush from accumulator clearing or add an explicit preload/continue control. Current tests safely clear every K chunk and accumulate chunk results in the testbench.

## 11. Systolic-array architecture

Use N x N cells. A travels right; B travels down. Row r of A starts r cycles late; column c of B starts c cycles late. This makes A[r,k] and B[k,c] meet at enabled edge `k+r+c`.

The implemented core finishes a depth-K tile after `K+2N-2` enabled computation edges, plus clear and result-handling overhead. On a global stall, both PE state and schedule must freeze. Separate per-PE backpressure is outside this design's contract.

An 8 x 8 array has 64 independently accumulated results. It consumes up to eight A and eight B bytes per enabled cycle. For K=8, there are 512 useful MACs over 22 compute edges, before other overhead. The full 2 x 2 schedule is in Lesson 1.

## 12. GEMM engine

GEMM means general matrix multiplication, often `C=alpha*A*B+beta*C`. The first engine implements the simpler `C=A*B`; do not claim arbitrary alpha/beta support until implemented.

For physical array N and reduction chunk Kb:

```python
for i0 in range(0, M, N):
    for j0 in range(0, P, N):
        Ctile = zeros_int32(N, N)
        for k0 in range(0, K, Kb):
            Atile = load_and_zero_pad(A[i0:i0+N, k0:k0+Kb])
            Btile = load_and_zero_pad(B[k0:k0+Kb, j0:j0+N])
            partial = run_systolic_tile(Atile, Btile)
            Ctile += partial
        store_only_valid_rows_and_columns(Ctile)
```

M/N edge padding must not write beyond output bounds. K padding contributes zero. Preserve INT32 partial sums through the full reduction; requantizing each chunk introduces extra error. Later choose loop order to reuse the more expensive operand and measure DDR bytes rather than guessing.

The hardware GEMM engine needs a tile controller, scratchpad address generators, input skew registers, output capture/storage, and an interface with start/busy/done/error. Start with one outstanding command and reject start while busy.

## 13. GEMV engine

GEMV computes `y=W*x`. A straightforward engine has L output lanes. Each cycle, broadcast x[k] to all lanes, read L weights W[row,k], and update L row accumulators. After K cycles, those L output elements are complete; repeat for the next row group. This uses L weight bytes per cycle for INT8 and reuses the input scalar across lanes.

Another design splits one dot product across lanes and uses a reduction tree. It requires careful sum-tree pipelining and is useful for different shapes. Compare both only after the simpler row-parallel design works.

With batch size one, little weight reuse occurs between tokens. Reading a weight byte for roughly two arithmetic operations gives a simplified weight-dominated intensity near 2 operations/byte. A GEMV engine can improve PE utilization but cannot exceed the memory system's ability to supply weights.

Separate engines simplify independent design but add DSPs, buffers and arbitration. A shared configurable MAC pool saves arithmetic resources at the cost of routing and control complexity. Compare under equal DSP and bandwidth limits; a larger combined design is not a fair comparison against a smaller baseline.

## 14. Vector engine

Stage 1 offloads only integer matrix products. Stage 2 replaces Transformer linear layers. Stage 3 considers residual add, elementwise multiply and scaling first, then RoPE/SiLU/RMSNorm if profiling justifies them. Stage 4 considers attention and softmax.

RMSNorm needs a sum-of-squares reduction, reciprocal square root and rescaling. RoPE needs paired multiplies/adds and sine/cosine values, which may come from a table. SiLU can use a table or piecewise approximation; record its input range and maximum error. Stable softmax subtracts the maximum before exponentiation, sums exponentials and normalizes. It is more complex than merely evaluating exp.

Every approximation must be evaluated at both operator and model level. Saving a little arithmetic is unhelpful if moving vectors between PS and PL costs more than the kernel itself.

## 15. Memory hierarchy

Use registers for immediate operands and sums, BRAM for banked local tiles, DDR for the full model and large tensors, and SD/host storage for persistent files. BRAM capacity alone is not sufficient: bank the buffers to deliver N activation bytes and N weight bytes per compute cycle. A single dual-port RAM does not magically provide sixteen independent reads for an 8 x 8 array.

For N=8 and Kb=256, one A tile is 2048 bytes and one B tile is 2048 bytes. Double-buffering both uses 8192 raw bytes; one 8 x 8 INT32 C tile uses 256 bytes. Actual BRAM block usage is higher depending on width, banking, padding and port configuration.

Ping-pong buffering uses two copies: compute from buffer A while DMA fills buffer B, then swap only when compute and transfer have completed. Do not overwrite a buffer still in use. Ideal steady-state tile time is about `max(T_load,T_compute,T_store)` if all overlap independently, not their sum. Shared DDR/buses and small transfers may prevent this ideal overlap. Initial fill and final drain always remain.

## 16. AXI and DMA architecture

AXI4 memory-mapped transactions carry addresses and support bursts. AXI4-Lite is a simpler register interface suited to command/status words. AXI4-Stream carries data beats without memory addresses and uses `TVALID && TREADY` to accept a beat. The sender must keep data and sideband signals stable during backpressure.

AXI DMA converts DDR reads to a stream (MM2S) and a stream to DDR writes (S2MM). Plan an input packet format, for example a command header followed by row-major A and B bytes; define lengths, TKEEP on a partial last beat and TLAST on the last beat. DMA does not automatically understand matrix layouts.

Use aligned bursts, adequate FIFO depth, explicit byte counts and timeouts. Start the receive path before producing output. Zynq-7000 HP ports are PS-side AXI3 interfaces; Vivado interconnect/protocol conversion bridges the AXI4 DMA side. HP DMA is not automatically coherent with ARM caches. See [UG585](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM) for the PS interfaces and [ACP comparison](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM/PL-DMA-via-AXI-ACP).

Initially use vendor DMA/interconnect IP. Writing a DMA bus master from scratch would distract from the accelerator research. Your RTL still owns the compute engine, tile scheduling and stream packing.

## 17. ARM/FPGA hardware-software partition

An eventual software API can be:

```c
int fpga_matmul(const int8_t *a, const int8_t *b, int32_t *c,
                unsigned m, unsigned n, unsigned k);
int fpga_gemv(const int8_t *w, const int8_t *x, int32_t *y,
              unsigned rows, unsigned cols);
```

These are proposed interfaces, not implemented drivers. Define row strides, alignment, shape limits, scale ownership and overflow behavior as part of the API. Return errors for unsupported shapes or timeouts.

Transaction: validate dimensions -> pack input tensors into DMA-safe DDR -> prepare cache state -> arm S2MM -> write dimensions/opcode -> start accelerator and MM2S -> wait with timeout for both computation and DMA completion -> invalidate result cache lines -> unpack/read C. Under bare metal use the platform's correct cache maintenance calls; under Linux use proper DMA allocation/mapping APIs, not guessed physical addresses or arbitrary virtual pointers. Do not modify input buffers while DMA owns them.

Suggested control register contract: CONTROL (start), STATUS (busy/done/error), opcode, M/N/K, strides, optional scaling metadata, and counters. Put DDR source/destination addresses in the DMA configuration unless the accelerator itself is a memory master. Start with polling; introduce interrupts once polling works.

## 18. Quantization

Quantization represents a real value approximately as `x ~= scale * (q - zero_point)`. Scale must be positive. Symmetric quantization sets zero_point=0; an easy initial convention uses signed [-127,127] to keep symmetry, although the hardware supports the full INT8 range [-128,127]. Asymmetric quantization chooses a nonzero zero point to match an offset range, but introduces correction terms into multiplication.

For symmetric weights: `s=max(abs(W))/127`, `q=clip(round(W/s),-127,127)`. Handle an all-zero tensor explicitly, for example s=1 and all q=0. Define one rounding rule in the exporter, reference and driver. Per-tensor scaling uses one scale; per-channel scaling uses one scale per output channel and often better handles differing channel ranges. Group scaling is another option but changes the reduction/dequantization contract.

Example: W=[-1,0,0.5,1] gives s=1/127 and approximately q=[-127,0,64,127]. Reconstructed 0.5 becomes 64/127 ~= 0.50394.

With symmetric activation scale sx and output-channel weight scale sw[j], `Y[j] ~= sx*sw[j]*sum(qx*qw[j])`. For x=[0.5,-1] with sx=0.5 and w=[2,-0.5] with sw=0.5, qx=[1,-2], qw=[4,-1], integer dot=6, dequantized dot=1.5. Requantizing to sy=0.25 yields qy=6. Generally `qy=clip(round((sx*sw/sy)*acc)+zy)`. Hardware later approximates the ratio by an integer multiplier and shift with an explicitly matched rounding rule.

Asymmetric multiplication needs `sum((qa-za)*(qb-zb))`, not merely `sum(qa*qb)`. Activation/weight sums and the K*za*zb term may be required. Start symmetric to avoid this extra mechanism.

Signed INT8 products have maximum positive magnitude 16384. A conservative sufficient signed accumulator width is `1+ceil(log2(K*16384+1))`. INT32 is safe for worst-case positive accumulation only through K=131071 without other additions; K=131072 all (-128)*(-128) products overflows. Bias, residuals and accumulation over multiple chunks also consume range. Saturation clamps to the representable endpoints; wrap discards high bits. The present core wraps.

Post-training quantization converts a trained model using calibration data, without retraining. Start with per-output-channel symmetric weights and per-token activation quantization for GEMV. For GEMM, per-row activation scales require applying sx[row]*sw[col] to each result. Compare FP32 and quantized logits, layer errors and held-out loss before deploying.

INT8 divides raw FP32 weight bytes by four. Narrower arithmetic may use fewer resources, but one INT8 multiply does not automatically pack multiple independent MACs into one DSP. INT4 halves raw INT8 weight traffic but needs nibble packing, signed unpacking, scales and an accuracy study. Treat W4A8 as an optional later experiment.

## 19. Tiny Transformer model selection

Start with the documented `stories260K` model and its matching tokenizer. Then consider an approximately 1M model if a compatible checkpoint is available or trained, and only then `stories15M`. The [llama2.c repository](https://github.com/karpathy/llama2.c) provides a compact reference runtime, and its [260K notes](https://github.com/karpathy/llama2.c/blob/master/doc/stories260K.md) describe the tiny model.

Pin a repository commit, record checkpoint/tokenizer hashes and inspect the actual header: layer count, hidden width, FFN width, query heads, KV heads, vocabulary and context. Do not assume all listed checkpoints share a tokenizer or quantization format. A floating-point binary cannot be relabeled INT8; write and verify an exporter.

Raw parameter storage, decimal MB, excluding scales, headers, padding, activations, KV cache and software:

| Parameters | FP32 | FP16 | INT8 | Packed INT4 |
|---:|---:|---:|---:|---:|
| 260,000 | 1.04 MB | 0.52 MB | 0.26 MB | 0.13 MB |
| 1,000,000 | 4 MB | 2 MB | 1 MB | 0.5 MB |
| 15,000,000 | 60 MB | 30 MB | 15 MB | 7.5 MB |

Formula: bytes ~= parameter_count * bits/8. A 260K INT8 model could fit in raw BRAM capacity, but buffers, banking and other logic reduce usable capacity; it is not true that every tiny model necessarily exceeds BRAM. The 1M and 15M INT8 models exceed it. DDR provides room, although bandwidth and runtime allocation still matter. Billion-parameter LLMs are outside the practical scope of this board/project.

## 20. Complete inference dataflow

```text
Read model/tokenizer -> validate metadata -> tokenize prompt
 -> prefill prompt and populate KV cache
 -> final norm and logits -> sample token -> print token
 -> embed new token -> run each block with cached K/V
 -> logits -> sample -> repeat until EOS or token limit
```

At each offloaded linear layer: choose scales -> quantize/pack input -> select kernel -> DMA -> integer compute -> DMA output -> dequantize -> continue software graph. Keep this boundary visible in performance measurements. Fusing consecutive hardware operators is a later way to reduce transfers.

## 21. Prefill versus decoding analysis

For T prompt tokens, X[T,d] times W[d,o] reuses W across T rows. As T grows, a GEMM tile can keep more PEs working. For one decoded token, X[1,d] times W[d,o] has only one output row. In the simple mapping, only one row of an N x N array does useful work, capping occupancy near 1/N even before fill/drain and padding. A transpose can change which dimension is underused but does not remove the missing batch dimension.

This is not a universal impossibility result: batching independent sequences, interleaving operations and changing dataflow can improve utilization. Your research should compare the baseline mapping, a specialized GEMV engine, and optionally a shared-lane mode.

Prefill speed and decode speed are separate metrics. A runtime that processes the prompt serially may never produce a large GEMM even during prefill; implement batched prefill explicitly before claiming a GEMM prefill benefit.

## 22. KV cache

Autoregressive attention reuses previous tokens' keys and values. Save them instead of recomputing all earlier projections. Query values for earlier tokens usually need not be cached for standard next-token generation.

KV bytes = `2 * layers * batch * cached_tokens * kv_heads * head_dim * bytes_per_element`. Example: 6 layers, batch 1, 256 tokens, 6 KV heads, head size 48, FP32 gives 3,538,944 bytes = 3.375 MiB. This is an illustrative configuration, not a claim about the chosen checkpoint. With grouped-query attention use KV head count, not query head count.

Store the full cache in DDR unless a measured tiny configuration fits alongside all buffers. Cache recent blocks in BRAM if access patterns justify it. Attention per new token grows with context length even when projection shapes stay fixed. Quantizing KV may save traffic, but requires a separate numerical validation.

## 23. FPGA resource planning

Zynq-7020 has 220 DSP slices and 140 36-Kibit BRAM blocks; see [AMD DS190](https://www.amd.com/content/dam/xilinx/support/documents/data_sheets/ds190-Zynq-7000-Overview.pdf). Reserve resources for DMA, control, buffers, clock/reset logic and debug.

| N | PEs | Nominal DSP budget if 1 DSP/PE | Visible PE state bits before synthesis optimization |
|---:|---:|---:|---:|
| 2 | 4 | 4 | 200 |
| 4 | 16 | 16 | 800 |
| 8 | 64 | 64 | 3200 |

State estimate is N^2*(32+8+8+2), excluding controllers, extra pipelines and buffers. It is not a flip-flop utilization prediction: registers may reside in DSPs, be optimized away or change with mapping. Multipliers may map to LUTs or DSPs depending on synthesis. LUT usage needs an actual synthesis report, not a fabricated precise estimate.

Later run separate out-of-context synthesis experiments with a clock constraint for N=2/4/8. Inspect DSP inference, report utilization, then implement the integrated design and report post-route timing. Raw array ports are internal interfaces, not thousands of external board pins.

## 24. Performance calculations

Peak MAC/s = N^2*f. If one multiply and one addition count as two operations, peak GOPS = `2*N^2*f/1e9`. At 8 x 8 and 100 MHz this is **6.4 GMAC/s = 12.8 GOPS = 0.0128 TOPS**. This is a theoretical arithmetic peak, not achieved throughput or a timing result.

Ideal full-tile utilization for this core, excluding clear/load/store, is `K/(K+2N-2)`. For N=8,K=8 it is 8/22 ~= 36.4%, giving about 4.65 useful GOPS at a hypothetical 100 MHz. Larger K amortizes fill/drain. Padding multiplies by useful-row/column fractions; stalls and transfer overhead reduce it further.

Measured utilization = `useful_MACs/(N^2*elapsed_cycles)`. Define the measurement window: compute-only and end-to-end values answer different questions. Zero-padding MACs are not useful work. Report wall-clock latency, operations per job, sustained throughput, bytes transferred, and achieved bytes/sec.

Roofline estimate: achieved operations/sec <= min(compute peak, sustained_bandwidth * arithmetic_intensity). For a hypothetical measured 1 GB/s and 2 operations/byte, the bandwidth ceiling is about 2 GOPS. As an illustrative lower bound, streaming 15 MB once per token at that bandwidth costs at least 15 ms, before other work. Do not substitute this example for measured board bandwidth or promise its implied token rate.

Energy/token = measured average watts * seconds/token. GOPS/W and tokens/J need a stated measurement boundary and instrument. Tool power estimates are estimates; board-input power includes CPU, DDR and peripherals.

## 25. Verification strategy

Use independent references and bit-exact comparison for integer arithmetic. The current Python model generates deterministic full-range signed data for 11x17 by 17x13; RTL tests compare against it for N=2,4,8. The PE test checks every INT8 pair, plus accumulation, invalid operands, stalls, reset and a reduced-width wrap example.

Future tests must cover start while busy, reset during a partially executed command, repeat commands without reset, maximum/minimum dimensions, rejected zero dimensions, random gaps/backpressure, misaligned/partial transfers where supported, timeouts, and malformed packets. Scoreboard accepted beats rather than cycles alone. Constrain dimensions and memory bounds and test rejection behavior.

For BRAM, model synchronous read latency. For AXI, vary READY independently and assert data stability during stalls. Match all TLAST and byte counts. Use a 64-bit software golden sum to detect when the INT32 contract would overflow before applying the specified wrap/saturation rule.

For models, compare floating point -> quantized software -> RTL kernel -> board kernel -> integrated logits. Fix the random seed and decoding mode for reproducibility. Generated text alone cannot locate numerical errors.

## 26. Step-by-step implementation roadmap

1. Understand dot products, two's complement and clocked state. Hand-calculate the 2 x 2 example.
2. Generate a software integer reference and inspect shapes/packing.
3. Verify the MAC PE, then the skewed 2 x 2 array.
4. Scale to 4 x 4 and 8 x 8 without changing the arithmetic contract.
5. Demonstrate tiling and partial-sum accumulation with a testbench (current milestone).
6. Replace the testbench schedule with a synthesizable controller; verify start/busy/done and stalls.
7. Add banked BRAM and account for read latency. Test load/compute/store ownership.
8. Add a minimal AXI-Lite interface and simulate independent read/write handshakes.
9. Add stream adapters, vendor DMA, FIFO sizing and packet checks.
10. When a board is available, build PS/PL integration, verify one tile from ARM, then many shapes.
11. Offload a quantized fully connected layer; include scales, bias if present and layout conversion.
12. Offload Q/K/V and FFN projections, checking each against the software model.
13. Complete one Transformer block and then a tiny full model with software nonlinear functions.
14. Add GEMV mode, ping-pong buffers and performance counters, one experiment at a time.
15. Freeze a reproducible demonstration and report, with limitations clearly recorded.

Keep a working baseline at every stage. DMA and Transformer integration should not be the first time the arithmetic is checked.

## 27. Module hierarchy

```text
accelerator_top                         [future]
 +-- axi_lite_control                   command/status, not bulk tensors
 +-- command_scheduler                 opcode and buffer ownership
 +-- stream_unpack / stream_pack        tensor packet boundaries and byte order
 +-- gemm_engine
 |    +-- tile_controller               clear/feed/drain/capture states
 |    +-- activation_buffer             banked synchronous storage
 |    +-- weight_buffer                 banked synchronous storage
 |    +-- input_skew_buffer              row/column delay lines and valids
 |    +-- systolic_array                IMPLEMENTED
 |    |    +-- mac_pe x N*N             IMPLEMENTED
 |    +-- output_buffer                 preserve INT32 K partials
 +-- gemv_engine                        later row-parallel MAC lanes
 +-- vector_engine                      optional operations selected by profiling
 +-- performance_counters               snapshot/readout, overflow policy

AXI DMA / interconnect / Zynq PS        vendor block-design IP outside core
```

The raw array is already parameterized; wrapper interfaces should avoid exposing a giant packed sum bus outside the FPGA. A future controller could accept `start`, `k_length`, `step_enable` and expose `busy`, `done`, `error`, read addresses and capture strobes. Freeze counter/address updates on global stalls. Define done as results captured, not merely final inputs submitted.

## 28. Software architecture

Use Python and optionally NumPy for reference math/vector generation, PyTorch for model export/calibration, SystemVerilog for RTL and tests, Vivado for simulation/synthesis/implementation, and Vitis C/C++ for ARM software later. Verilator is an optional fast regression path; PYNQ is optional if a suitable board image and driver stack are available. Neither is required to start. Git tracks sources and scripts; generated build output is ignored.

Split software into model loader, tokenizer, inference graph, quantization/packing, backend dispatcher, driver, and benchmark logger. Keep a CPU fallback for every kernel. A model file format should record dimensions, tensor order, datatype, signedness, scale layout, offsets, alignment and a version/checksum. Validate it before programming DMA.

## 29. Benchmark methodology

Compare ARM-only and FPGA using the same dimensions, layouts and numerical contract. Provide a clear scalar baseline and an optimized ARM baseline if feasible. Do not compare a deliberately slow Python reference with FPGA hardware as the principal speedup result.

Measure kernel cycles separately from end-to-end time including quantization, packing, cache maintenance, DMA and synchronization. Warm up, repeat runs, report median plus variation, and record clocks, software versions, compiler flags and model checksum. Report `speedup=T_CPU/T_FPGA` and identify cases where speedup is below one.

Sweep N=2/4/8, K lengths, batch sizes, matrix edges, GEMM/GEMV shapes and context lengths. Hold quantization fixed for architecture comparisons. For a quantization comparison hold the workload and accuracy dataset fixed.

## 30. Expected results

Expected functional result: bit-exact integer GEMM and eventually an offloaded tiny model producing consistent logits within the chosen quantization tolerance. Expected trend: small tiles lose efficiency to fill/drain; larger prompt batches improve weight reuse; batch-one decoding is more sensitive to weight traffic. These are hypotheses to test, not promised speedups.

Actual LUT/DSP/BRAM usage, clock frequency, power, tokens/sec and speedup remain unknown until the relevant synthesis and board measurements exist. Current simulation proves arithmetic for the tested conditions only.

## 31. Research contributions

A defensible statement is: "This work designs and evaluates a parameterized integer matrix accelerator and workload-dependent GEMM/GEMV execution strategy for a resource-constrained Zynq platform, quantifying utilization, transfer overhead and numerical accuracy for tiny Transformer inference."

Do not claim invention of systolic arrays, quantization or FPGA LLM inference. Support implementation novelty through explicit experiments: equal-DSP GEMM vs GEMV, transfer/compute overlap, tile-loop order, per-channel vs per-tensor quantization, and break-even dimensions for offloading. An additional useful question is whether software packing time erases the benefit of the faster datapath.

The first scheduler should be software: elementwise operations stay on CPU, vector shapes choose GEMV, and sufficiently large matrix shapes choose GEMM based on a measured cost table. A later RTL command queue can execute the same opcodes and arbitrate buffers. Dispatch alone does not solve memory contention.

## 32. Risks and mitigation

| Risk | Mitigation and evidence |
|---|---|
| Timing closure | Start with a modest clock; inspect critical paths; pipeline and reverify schedule |
| DSP shortage | Synthesize small arrays first; compare shared MAC modes before adding engines |
| BRAM shortage/ports | Calculate both bytes and reads/cycle; bank and reuse tiles |
| DDR bandwidth | Measure sustained DMA bandwidth and bytes per layer; use bursts and overlap |
| AXI stalls/deadlock | Simulate arbitrary backpressure, lengths and TLAST; use bounded timeouts |
| Cache incoherence | Specify DMA buffer ownership and use supported platform APIs |
| Numerical mismatch | Match signedness, layout, scale, rounding and overflow in one written contract |
| Quantization accuracy loss | Layerwise error analysis and held-out loss; keep sensitive operations FP32 |
| Slow decoding | Measure per-layer traffic; GEMV and caching experiments; reduce model size |
| Tokenizer mismatch | Pin tokenizer/checkpoint together; validate token IDs on PC first |
| Model conversion bugs | Versioned format, checksums, per-tensor round-trip tests |
| Debug complexity | Keep CPU fallback; known matrices, UART status and ILA probes |
| Scope overload | Freeze a verified accelerator+neural-layer deliverable before full LLM work |

Useful ILA probes later: start/busy/done, controller state, tile and K counters, buffer bank selectors, operand valids, FIFO levels, stream READY/VALID/LAST and error flags. UART should print command IDs, dimensions and timeout diagnostics. Avoid probing every 32-bit PE sum if that consumes excessive debug resources.

## 33. Improvements and performance counters

Prioritize changes by measured stalls. Add total cycles, compute cycles, DMA-wait cycles, busy cycles, accepted input/output bytes, completed commands and error counts. Count useful valid MACs or derive them from dimensions; an "array active" flag is insufficient to distinguish one active PE from 64.

Define counters as overlapping or mutually exclusive. Snapshot 64-bit counters atomically before reading over a 32-bit register bus. DDR transaction counters must observe the actual memory interface or supported monitor IP; accepted stream beats are not identical to DDR transactions.

Then evaluate double buffering, larger K tiles, retained output partial sums, layer fusion, GEMV modes and only afterward INT4 or complex nonlinear hardware.

## 34. Project timeline

| Weeks | Deliverable | Exit evidence |
|---|---|---|
| 1-2 | Math, Python reference, model inspection | Known examples and packing contract |
| 3-4 | PE and 2 x 2 array | Signed/extreme/stall regressions pass |
| 5-6 | 4 x 4 / 8 x 8 and synthesis study | Identical reference results, resource reports |
| 7-8 | RTL tile controller and K tiling | Odd dimensions, repeated jobs, reset-in-flight |
| 9-10 | Banked BRAM and stream adapters | Latency-aware, backpressure tests |
| 11-12 | AXI/DMA and ARM bring-up | Many shapes match CPU on board |
| 13-14 | Quantized neural layers | Layer errors and end-to-end timing recorded |
| 15-16 | One Transformer block | Intermediate tensors match reference |
| 17-18 | Tiny full model or integration buffer | Reproducible logits/tokens |
| 19-20 | GEMV / double-buffer experiments | Fair baseline comparisons |
| 21-22 | Report and demo | Reproducible build and results archive |
| 23-24 | Contingency | Timing, driver and demo fixes |

For four months, prioritize the verified matrix accelerator, ARM interface, one neural layer and benchmarks. Full text generation plus a new GEMV datapath is more realistic with six months and prior RTL/embedded experience. Board procurement should happen before the integration weeks.

## 35. Final demonstration

Show three modes: a known matrix with CPU/FPGA equality, a size sweep chart with measured transfer/compute times, and optional tiny-model generation from "Once upon a time". Print the actual model name, precision, prompt length, generated tokens, prefill latency, decode tokens/sec, FPGA call counts and DMA-wait cycles.

Use a fixed-seed deterministic run for repeatability and an optional sampling mode for interaction. Include a CPU-only switch. A live utilization timeline is useful only if driven by counters, not animated mock measurements. Keep a saved numerical regression as a fallback demo.

## 36. Report structure

| Chapter | Content |
|---|---|
| 1 Introduction | Objective, bounded scope and contributions |
| 2 Background | Digital arithmetic, matrix kernels, dataflows |
| 3 Literature review | Related accelerators; compare assumptions and resource budgets |
| 4 Transformer architecture | Chosen model, operator graph, prefill/decode shapes |
| 5 FPGA platform | PS/PL, memory, constraints and tools |
| 6 Systolic architecture | PE, schedule, latency, signed arithmetic |
| 7 Proposed accelerator | Buffers, tiling, GEMV and scheduler |
| 8 Hardware/software co-design | Driver, DMA ownership, backend partition |
| 9 Quantization | Scales, rounding, calibration and accuracy |
| 10 Implementation | RTL/IP hierarchy, builds and timing decisions |
| 11 Verification | References, corner cases, protocol and integration tests |
| 12 Results | Measured resources, latency, bandwidth and model metrics |
| 13 Analysis | Bottlenecks, roofline, utilization and fair comparisons |
| 14 Challenges | Observed failures and remaining limitations |
| 15 Improvements | Evidence-backed optimizations and optional extensions |
| 16 Conclusion | What was demonstrated and what remains unproven |

Include scripts, pinned versions, configuration tables and reproducibility instructions in appendices. Keep expected/projected values visibly distinct from measurements.

## 37. Future scope

Investigate W4A8, KV quantization, operator fusion, larger context, configurable shared GEMM/GEMV lanes, dynamic batching and nonlinear units. Each extension needs its own accuracy and performance study. Moving to a larger FPGA changes memory and resource limits but does not remove the need for bandwidth-aware scheduling.

## 38. Final project conclusion and phase checklist

**A. Minimum viable project:** verified INT8 PE, 4 x 4 array, hardware tiled GEMM, a board control interface, one quantized neural layer and CPU/FPGA timing including transfers. For a simulation-only course milestone, clearly limit claims to verified RTL and synthesis results; do not claim board speedup.

**B. Recommended final-year project:** 8 x 8 configurable array, DMA, ARM runtime integration, performance counters and a GEMV comparison. Add a full tiny model if integration time permits; keep softmax, normalization and tokenization in software first.

**C. Advanced research version:** resource-matched shared/separate GEMM/GEMV modes, measured dispatch policy, ping-pong memory scheduling, selective vector acceleration and INT4 with accuracy evaluation.

**D. Exact module order:** mac_pe -> systolic_array -> tile_controller -> skew/address generation -> activation/weight/output buffers -> gemm_controller -> stream adapters -> AXI-Lite control -> vendor DMA/PS integration -> ARM driver -> quantized-layer backend -> model integration -> counters/GEMV -> optional vector engine/INT4. Add basic counters alongside the controller if convenient.

**E. Move forward only when these gates pass:**

- [ ] PE: all signed pairs, accumulation, validity, reset, stalls and specified overflow agree.
- [ ] Array: cycle schedule explained; N=2/4/8 and edge/padded tiles match an independent reference.
- [ ] Controller: repeated commands, busy/start rules and reset-in-flight work; no lost K partials.
- [ ] Buffers: synchronous latency, banking and load/compute ownership verified.
- [ ] AXI: random backpressure, packet lengths, independent channels and timeouts verified.
- [ ] Board: multiple shapes match ARM; implementation meets clock constraints; no unaccounted cache errors.
- [ ] Quantized layer: scale/bias/layout contract matches software and layer error is reported.
- [ ] Transformer block: every intermediate stage compared, not just final text.
- [ ] Full model: matching tokenizer/checkpoint, reproducible logits, bounded context and cache management.
- [ ] Evaluation: compute-only and end-to-end measurements, fair baselines and actual resource reports archived.

The project is technically feasible as a small, carefully verified accelerator with a tiny-model demonstration. Its strongest contribution will be the explanation and measurement of the hardware/software and memory tradeoffs, including cases where acceleration does not help.
