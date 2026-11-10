# ML-KEM Sequencer Implementation Signoff

## 1. Purpose

This document defines evidence required for FPGA and ASIC implementation claims
for [mlkem_sequencer_top](../Implementation/rtl/modules/mlkem_sequencer_top.v).
It is a signoff plan, not a completed report.

Current status:

| Area | Status |
| --- | --- |
| KV260/K26 part, board files, and tool version | `TBD` |
| OOC constraints and reports | `UNVERIFIED` |
| Integrated accelerator implementation | `UNVERIFIED` |
| Fully routed STA/DRC/power | `UNVERIFIED` |
| ASIC PDK/libraries/corners/tools | `TBD` |
| ASIC front-end and physical signoff | `UNVERIFIED` |

No `.xdc`, `.sdc`, project, or implementation script is present in this
repository.

## 2. Common release baseline

The release shall freeze and archive:

- RTL/file-list revision and hashes;
- top, configuration, and integration descriptor contract revision;
- clock, reset, I/O, command-latency, and environment assumptions;
- verification closure from [VERIFICATION_PLAN.md](VERIFICATION_PLAN.md);
- lint/CDC/RDC/timing/DRC/DFT waiver register;
- tool/version/command/script manifest;
- reproducible build and report collection instructions.

All warnings shall be reviewed by severity and root cause. Compile success or a
single timing number is not signoff evidence.

## 3. FPGA flow for AMD Kria KV260/K26

The evaluation target is AMD Kria KV260 using its K26 device. The exact device
part string, speed grade, board definition, PL clock, and Vivado version shall
come from the controlled integration project and are `TBD`.

### 3.1 Out-of-context flow

Use `mlkem_sequencer_top` as the OOC top. Constraints shall define:

- the primary `clk`;
- active-low synchronous reset behavior;
- clock uncertainty appropriate to the implementation stage;
- input/output delay budgets for the request and dispatcher interfaces;
- maximum expected dispatcher fanout/load or representative output loads;
- no timing exception without path-specific design justification.

The OOC environment should constrain a realistic register-to-register boundary
for every I/O. OOC timing shall be labeled as an interface-budget result and
shall not be presented as integrated KV260 closure.

### 3.2 Integrated accelerator flow

The integrated design shall define:

- K26 part and board/clock sources;
- reset synchronization and distribution;
- dispatcher registration, ready/completion paths, and command fanout;
- physical logical-object storage and datapath connectivity;
- AXI/control wrapper and software contract if used;
- timeout/error/abort and zeroization policy;
- hardware known-answer and stress test procedure.

The native interface permits unbounded dispatcher latency. Any system watchdog
or maximum-latency requirement belongs to integration and shall not alter the
unit protocol without a specification revision.

### 3.3 FPGA signoff gates

1. **Elaboration/lint:** no unresolved references, inferred latches,
   combinational loops, width/sign defects, unreachable logic without review, or
   unwaived high-severity warning.
2. **FSM analysis:** all legal states/transitions recognized; safe behavior for
   illegal encoding assessed; optimization does not change protocol behavior.
3. **CDC/RDC:** OOC single-clock/reset result documented; integrated crossings,
   asynchronous controls, and reset release analyzed.
4. **Synthesis:** utilization, state encoding, high-fanout nets, control-set
   count, inferred primitives, timing, and warning reports archived.
5. **Resource audit:** LUT, FF, carry, DSP, BRAM, URAM, distributed-RAM, and
   clock-buffer usage reported. RTL contains no explicit RAM or DSP, but
   post-synthesis mapping is authoritative.
6. **Implementation:** placement and routing complete with no unrouted or
   partially routed nets.
7. **STA:** all clocks/endpoints constrained; setup, hold, and pulse-width checks
   pass for required corners; WNS/TNS/WHS/THS and unconstrained-path count
   archived.
8. **DRC/methodology:** zero unwaived errors/critical warnings.
9. **Power:** activity assumptions include representative command transitions,
   dispatcher stalls, and each operation/set; static/dynamic breakdown and
   thermal context recorded.
10. **Hardware test:** bitstream/software identity, trace/result logs, all
    parameter sets, error injection where feasible, and observed clock/reset
    behavior archived.

Target frequency, utilization budget, and power budget are `TBD` and shall be
approved before optimization/signoff.

## 4. ASIC flow

Foundry, process node, PDK revision, libraries, voltage domains, operating
conditions, and package assumptions are `TBD`. The flow is tool neutral.

### 4.1 Front-end

- Compile/elaborate every release configuration.
- Run semantic, connectivity, coding-rule, and synthesizability lint.
- Run CDC/RDC with explicit clock/reset intent and reviewed waivers.
- Define functional/test modes, clocks, uncertainty, I/O budgets, transition,
  capacitance, fanout, case analysis, and justified exceptions.
- Synthesize and inspect timing, area, power, state encoding, decode depth, and
  command-output fanout.
- Run RTL-to-gate logical equivalence for all release netlists.
- Use gate-level/SDF simulation for residual risks not closed by LEC and STA,
  with annotation coverage recorded.

### 4.2 DFT expectations

The DFT plan shall define:

- scan insertion for state, phase, indices, nonce, parameters, and operation
  registers;
- scan/test clocks, reset controllability, test-mode behavior, lockup elements,
  and X handling;
- ATPG fault models and product-specific coverage targets (`TBD`);
- at-speed test requirements;
- MBIST only for memories introduced by integration; this sequencer RTL has no
  memory arrays.

DFT rule checks, post-scan equivalence, ATPG reports, and untested-fault analysis
shall be archived. Functional ready/done/error behavior shall remain equivalent
outside test mode.

### 4.3 Physical design and signoff

For hard-IP or chip implementation:

- floorplan, power grid, placement, clock-tree synthesis, route, and ECO flow
  shall be reproducible;
- high-fanout command/control nets shall meet transition and skew budgets;
- extracted-parasitic MMMC STA shall close setup/hold and signal-integrity
  requirements for all approved modes/corners;
- foundry-required DRC, LVS, antenna, density, ERC, and reliability checks shall
  pass or have approved waivers;
- IR drop, electromigration, noise/crosstalk, and vector-based power shall meet
  product limits.

For soft-IP delivery, provide characterized constraints and boundary budgets;
the consuming project owns foundry physical signoff.

## 5. Integration and security review

Before system signoff, reviewers shall verify that the dispatcher contract in
[SPEC.md](../SPEC.md) Section 11 is complete. In particular:

- descriptor decoding is unique and reserved values fail safely;
- object storage hazards cannot permit a command to complete before its writes
  are architecturally visible;
- compare/select implements the required decapsulation behavior without
  secret-dependent early exit;
- errors/reset cannot expose or select stale partial results;
- timeout and cleanup policy is defined;
- sensitive object lifetime and zeroization are implemented where required.

The sequencer's fixed descriptor count does not establish end-to-end
constant-time, side-channel resistance, or fault resistance. Such claims
require a system threat model and implementation-specific evidence.

## 6. Release artifacts

### 6.1 FPGA

- frozen RTL/file list and integration command contract;
- XDC and reproducible build scripts;
- lint, CDC/RDC, synthesis, utilization, route status, STA, DRC/methodology,
  and power reports;
- routed checkpoint and bitstream/package where distribution permits;
- board test software, known-answer vectors, logs, and waiver register.

### 6.2 ASIC

- frozen RTL/file list, SDC, UPF/CPF if applicable, and waivers;
- synthesis/scan netlists, LEC, DFT, and ATPG collateral;
- MMMC setup, parasitic and timing configuration;
- STA, power, CDC/RDC, and physical-verification reports;
- for hard IP: GDSII/OASIS, LEF, Liberty, extracted views, and required
  integration abstracts;
- release manifest with checksums and tool versions.

## 7. Signoff decision

`SIGNED OFF` requires reviewed evidence for every applicable gate and approved
waivers for every deviation. Unit-level command-trace simulation shall be
reported as such; it shall not be represented as FIPS 203 correctness,
integrated FPGA timing closure, ASIC signoff, or production readiness.
