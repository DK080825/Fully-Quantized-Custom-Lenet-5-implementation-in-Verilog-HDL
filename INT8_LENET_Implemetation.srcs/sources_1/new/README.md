# Fully Quantized Custom LeNet-5 Implementation in Verilog HDL

A detailed RTL implementation of an INT8-quantized LeNet-5 style accelerator, organized as reusable SystemVerilog/Verilog hardware modules for convolution, pooling, activation, and dense classification.

---

## Project Information

- **Author:** Do Khanh
- **School:** UIT (University of Information Technology)
- **Domain:** FPGA/SoC Hardware Acceleration for Deep Learning Inference
- **Model Type:** Quantized LeNet-5
- **Arithmetic Focus:** INT8 datapath with wider internal accumulation

---

## 1. Introduction

This project implements a hardware-oriented LeNet-5 inference pipeline in Verilog HDL.  
The design is decomposed into clear functional blocks and wrappers, making it suitable for:

- studying neural-network hardware mapping,
- testing quantized arithmetic behavior at RTL level,
- integrating a custom accelerator into larger FPGA/SoC systems.

Unlike software inference where all operations are sequentially executed on a CPU/GPU, this implementation expresses each stage as dedicated hardware dataflow modules with cycle-level control.

### Video Demos

- **Demo Video 1:** [https://youtu.be/iHpeTRM6k9U](https://youtu.be/iHpeTRM6k9U)
- **Demo Video 2:** [Insert second demo link here](https://example.com)

---

## 2. High-Level Model Architecture

The implemented network follows a LeNet-5 style flow:

1. Input image ingestion
2. Layer 1 convolution processing
3. Max-pooling + activation
4. Layer 2 convolution processing
5. Max-pooling + activation
6. Dense / fully connected classification stage
7. Final class output

### Figure Placeholder A - LeNet-5 hardware-oriented model overview

> Insert your "Kiến trúc mô hình LeNet-5 được triển khai phần cứng" image here.

<br><br><br><br><br><br>

---

## 3. Overall IP Hardware Design

At system level, the accelerator is assembled as a top IP that coordinates:

- input bank management,
- Layer 1 processing pipeline,
- Layer 2 processing pipeline,
- Dense processing pipeline,
- control FSM and status signaling.

The top block routes data and control between layer wrappers while preserving timing consistency across the pipeline.

### Figure Placeholder B - Overall architecture of LeNet-5 IP

> Insert your "Thiết kế IP phần cứng / LENET TOP" architecture image here.

<br><br><br><br><br><br>

---

## 4. Core Compute Blocks

### 4.1 INT8 MAC Unit

The MAC unit is the arithmetic kernel of the design. A typical compute sequence includes:

- input offset/zero-point adjustment (if enabled by quantization flow),
- INT8 multiplication,
- adder-tree style reduction,
- bias or scaling-factor combination,
- rounding/right-shift normalization,
- output saturation/clipping.

This staged implementation improves timing closure and enables deeper pipelining.

### Figure Placeholder C - MAC unit internal pipeline

> Insert your "Khối MAC UNIT" image here.

<br><br><br><br><br><br>

### 4.2 Max-pooling + ReLU Block

This block performs activation-domain post-processing:

- local-window max selection (pooling),
- ReLU filtering,
- stream-compatible output formatting.

It reduces spatial dimensions and propagates dominant features to the next stage.

### Figure Placeholder D - Max-pooling + ReLU architecture

> Insert your "Khối Max-pooling + ReLu" image here.

<br><br><br><br><br><br>

---

## 5. Layer Processing Units

### 5.1 Layer 1 Processing Unit

Layer 1 contains:

- control logic for address sequencing and state transitions,
- local weight storage/read logic,
- multiple filter processing branches,
- output banks for staging intermediate feature maps.

It is optimized for first-stage feature extraction from the input image.

### Figure Placeholder E - Layer 1 processing architecture

> Insert your "Khối Layer1 Processing Unit" image here.

<br><br><br><br><br><br>

### 5.2 Layer 2 Processing Unit

Layer 2 receives Layer 1 output features and performs deeper convolutional extraction.  
It similarly contains:

- control and address generation,
- filter compute cores,
- output-bank organization for downstream dense input.

### Figure Placeholder F - Layer 2 processing architecture

> Insert your "Khối Layer2 Processing Unit" image here.

<br><br><br><br><br><br>

---

## 6. Dense Processing Unit and Classification

The dense stage transforms final feature vectors into class-level outputs.  
Its responsibilities include:

- feature flattening/arrangement,
- dense neuron accumulation,
- optional Softmax-compatible output conversion.

### Figure Placeholder G - Dense processing + Softmax block

> Insert your "Khối Dense Processing Unit" image here.

<br><br><br><br><br><br>

---

## 7. SoC Integration Concept

For system-level deployment, the accelerator can be exposed as a custom IP and controlled via mapped registers/signals through a bus interface (e.g., AXI-based integration path).

Typical control/data signals include:

- clock/reset,
- write address/data/valid,
- read address/data/valid,
- start/load/done synchronization.

### Figure Placeholder H - SoC integration view

> Insert your "Tích hợp hệ thống SoC / AXI mapping" image here.

<br><br><br><br><br><br>

---

## 8. RTL File Organization

The implementation includes the following key module groups:

- **Top-level and wrappers**
  - `Lenet_Top.sv`
  - `Layer1_Wrapper.sv`
  - `Layer2_Wrapper.sv`
  - `Dense_Wrapper.sv`
  - `mlp_top.sv`

- **Layer processing units**
  - `L1_F*_process_unit.sv`
  - `L2_F*_process_unit.sv`

- **Arithmetic and post-processing**
  - `INT8_MAC_pipelined.sv`
  - `MAC_wrapper.sv`
  - `adder_tree_signed.sv`
  - `Maxpolling2x2.sv`
  - `MaxPooling_Relu_stream`
  - `Max_polling_Relu_top.sv`
  - `sofmax_func.sv`

- **Memory/control utilities**
  - `BRAM_decoder.sv`
  - `dual_mem_mux.sv`
  - `fixed_address_gen.sv`
  - `input_bank_ctrl.sv`
  - `FM_Process_Branch.sv`
  - `lutrom_sync.sv`
  - `M10K.v`

- **IP/Interface integration**
  - `myip.v`
  - `myip_slave_full_v1_0_S00_AXI.v`

---

## 9. Quantization and Numeric Notes

This project uses **PTQ (Post-Training Quantization)** as the quantization methodology for deployment.

### 9.1 What is PTQ?

**PTQ** converts a pre-trained floating-point model (typically FP32) into a lower-precision model (INT8 in this project) **after training is complete**, without re-training the full network.  
In practice, PTQ uses calibration data to estimate activation ranges and derive quantization parameters (e.g., scale and zero-point), then maps float tensors to integer tensors for efficient hardware inference.

### 9.2 Why PTQ is used in this project

- It allows a faster path from trained model to RTL deployment.
- It matches the hardware goal of efficient INT8 arithmetic.
- It avoids the full cost and complexity of quantization-aware retraining.

### 9.3 PTQ advantages

- **Fast deployment:** no full retraining loop is required.
- **Lower engineering cost:** simpler workflow than QAT for many projects.
- **Good hardware compatibility:** naturally aligns with INT8 MAC-based accelerators.
- **Portable flow:** can be applied to many trained checkpoints with calibration.

### 9.4 PTQ limitations

- **Potential accuracy drop:** especially for sensitive layers or low-bit settings.
- **Calibration sensitivity:** quality depends on representative calibration data.
- **Less robust than QAT:** difficult distributions may quantize poorly without retraining.
- **Per-layer tuning overhead:** some models still need manual tuning of clipping/scales.

- Input/weight/activation datapath primarily targets signed INT8 representation.
- Internal accumulators use extended precision to reduce overflow risk.
- Final stage outputs may be normalized, rounded, shifted, and saturated based on module policy.
- Exact quantization calibration (scale/zero-point) can be adapted to your training/export flow.

---

## 10. Verification Recommendations

For robust validation, use a 3-level approach:

1. **Unit-level simulation**
   - MAC correctness,
   - adder tree reduction,
   - pooling and activation behavior.

2. **Layer-level simulation**
   - Layer 1 output shape/timing,
   - Layer 2 output consistency.

3. **End-to-end simulation**
   - compare final class outputs with a software reference model.

Recommended checks:

- no unknown (`X`) propagation on key outputs,
- deterministic output under identical input vectors,
- controlled overflow/saturation behavior.

---

## 11. Design Strengths

- Modular architecture suitable for incremental optimization.
- Clear separation of control, compute, and memory utility blocks.
- Practical bridge between quantized neural networks and RTL implementation.
- Ready structure for further SoC integration and accelerator packaging.

---

## 12. Future Improvements

- Introduce energy-aware dataflow mapping (e.g., **Row-Stationary (RS) dataflow**) to minimize data movement between memory hierarchy levels and reduce overall processing energy.
- Re-architect memory scheduling with local reuse buffers (weights, activations, partial sums) to further reduce off-chip/on-chip transfer cost.
- Add automated regression testbench and golden-check scripts for fast functional verification after every RTL update.
- Provide per-layer latency, throughput, and energy-per-inference reports to guide design-space exploration.
- Add parameterized support for configurable image size, channel count, kernel size, and parallelism factors.
- Explore mixed-precision or adaptive quantization (INT8/INT6/INT4 in selected stages) for better efficiency-accuracy trade-offs.
- Improve documentation with timing diagrams, synthesis statistics, and resource breakdown (LUT/FF/BRAM/DSP).

---

## 13. Acknowledgment

This project is built for learning, experimentation, and practical hardware acceleration research in FPGA-based AI systems. Contributions, feedback, and improvements are welcome.

