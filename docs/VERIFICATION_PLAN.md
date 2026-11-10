# ML-KEM Sequencer Verification Plan

## 1. Purpose and status

This plan defines verification of [SPEC.md](../SPEC.md), including the native
command protocol and exact schedule. It is UVM-ready but does not claim that a
UVM environment, formal proof, coverage closure, or implementation signoff
currently exists.

Current collateral:

- [tb_mlkem_sequencer.sv](../Implementation/testbench/tb_mlkem_sequencer.sv)
- [sequencer_test_vectors.py](../Implementation/vector/sequencer_test_vectors.py)

Generated metadata currently contains nine traces and 546 command descriptors:

| Set | KeyGen | Encaps | Decaps |
| --- | ---: | ---: | ---: |
| ML-KEM-512 | 27 | 37 | 54 |
| ML-KEM-768 | 44 | 56 | 78 |
| ML-KEM-1024 | 65 | 79 | 106 |

A current simulator pass is **UNVERIFIED** unless a revision-matched log is
archived.

## 2. Verification objectives

| ID | Objective |
| --- | --- |
| `SEQ-V-CFG-001` | Verify parameter outputs for all valid sets. |
| `SEQ-V-TRC-001` | Verify every KeyGen descriptor and ordering rule. |
| `SEQ-V-TRC-002` | Verify every Encaps descriptor and ordering rule. |
| `SEQ-V-TRC-003` | Verify every Decaps descriptor, re-encryption flag, compare, hash, select, and output order. |
| `SEQ-V-IF-001` | Verify command acceptance, waiting, completion, and single-outstanding-command behavior. |
| `SEQ-V-CTL-001` | Verify start acceptance and behavior of start while busy/terminal. |
| `SEQ-V-NEG-001` | Verify all invalid operation/parameter-set combinations. |
| `SEQ-V-NEG-002` | Verify `cmd_error` abort at every command position. |
| `SEQ-V-NEG-003` | Verify stray/early/late `cmd_done` and simultaneous `cmd_done/cmd_error`. |
| `SEQ-V-RST-001` | Verify reset in idle and each FSM state. |
| `SEQ-V-RST-002` | Verify reset at every phase/index boundary and clean restart. |
| `SEQ-V-SVA-001` | Check accepted request and busy-time start rules. |
| `SEQ-V-SVA-002` | Check descriptor stability under `cmd_ready` backpressure. |
| `SEQ-V-SVA-003` | Check no second issue before completion/error. |
| `SEQ-V-SVA-004` | Check field legality, reserved-bit zero, and `cmd_last` uniqueness. |
| `SEQ-V-SVA-005` | Check command/index/nonce progression and count. |
| `SEQ-V-SVA-006` | Check one-cycle terminal response and clean idle return. |
| `SEQ-V-INT-001` | Verify command semantics against the integrated dispatcher/datapath contract. |
| `SEQ-V-COV-001` | Close functional and structural coverage. |
| `SEQ-V-SEC-001` | Confirm release collateral makes no unsupported compliance or resistance claim. |

## 3. Reference models

The schedule predictor shall be independent of RTL phase implementation. It
shall derive traces from:

1. the command/interface contract in the specification;
2. parameter-set tables;
3. an accelerator-level operation model tracing each abstract operation to
   FIPS 203.

The existing Python generator is an initial trace oracle. Before release it
shall be:

- revision/hash recorded;
- reviewed against FIPS 203 and the completed dispatcher operand contract;
- cross-checked against an independent C/C++ or second Python implementation;
- protected by unit tests for count formulas, nonce/index ranges, flag use, and
  reserved-field zeros.

The scoreboard shall report operation, set, trace position, command field,
expected descriptor, actual descriptor, state context where observable, seed,
and cycle.

## 4. UVM architecture

```text
sequencer_env
  sequencer_control_agent
  command_dispatch_agent
  sequencer_reference_model
  sequencer_scoreboard
  sequencer_virtual_sequencer
  sequencer_coverage
  reset_agent
```

- `sequencer_control_agent` drives `operation`, `parameter_set`, and `start`.
- `command_dispatch_agent` monitors descriptor requests and drives `cmd_ready`,
  `cmd_done`, and `cmd_error`.
- The dispatcher agent shall maintain a one-command outstanding model and
  support configurable acceptance and completion delays.
- The scoreboard shall compare the accepted descriptor stream, not transient
  values when `cmd_valid=0`.
- `reset_agent` coordinates synchronous reset injection with the virtual
  sequencer.
- An integration environment shall connect descriptor monitor output to
  datapath transaction monitors for end-to-end checking.

Required sequence items:

- `sequencer_request_item`;
- `command_response_policy_item`;
- `expected_command_item`;
- `reset_injection_item`;
- integrated logical-object/data transaction items, definitions `TBD`.

## 5. Test and sequence matrix

| Test ID | Content | Requirements |
| --- | --- | --- |
| `sequencer_smoke_test` | One KeyGen trace for ML-KEM-512 with immediate accept/complete | Basic control |
| `sequencer_all_traces_test` | All nine operation/set traces, exact fields and counts | `SEQ-SCH-001..003` |
| `sequencer_command_backpressure_test` | `cmd_ready` low for 1, burst, long, and randomized intervals | `SEQ-CMD-002/004` |
| `sequencer_completion_delay_test` | Zero-additional, short, long, and randomized wait latency | `SEQ-CMD-003` |
| `sequencer_invalid_request_test` | All combinations where operation or set is `2'b11`, including both invalid | `SEQ-ERR-001` |
| `sequencer_dispatch_error_sweep_test` | Inject `cmd_error` at every descriptor position for all nine traces | `SEQ-ERR-002` |
| `sequencer_response_protocol_test` | Stray `cmd_done`, same-cycle accept/done, simultaneous done/error, held response | `SEQ-ERR-003` and documented protocol |
| `sequencer_start_protocol_test` | Held start, repeated start in issue/wait/done/error, changed inputs while busy | `SEQ-CTL-001/002` |
| `sequencer_reset_sweep_test` | Reset in every state, phase, index boundary, stalled issue, and wait | `SEQ-RST-001/002` |
| `sequencer_field_legality_test` | Legal op/object/index/param/nonce/flags; unused fields and reserved bit zero | `SEQ-CMD-005/006` |
| `sequencer_random_stress_test` | Seeded randomized requests, backpressure, response latency, error/reset injection | All interface requirements |
| `sequencer_integration_test` | Execute descriptors on real block models and compare complete KeyGen/Encaps/Decaps outputs | `SEQ-INT-001` |

The unit-level trace test proves only emitted scheduling metadata. Full
algorithm verification requires `sequencer_integration_test` with completed
operand and storage contracts.

## 6. Assertions

Assertions should be bound to the RTL.

### 6.1 Protocol and control

- `cmd_valid && !cmd_ready` implies all descriptor fields remain stable.
- An accepted command is followed by no new `cmd_valid` until `cmd_done`,
  `cmd_error`, or reset.
- `cmd_error` while waiting leads to terminal error and suppresses subsequent
  commands.
- Unsupported request leads to terminal error without command acceptance.
- `busy == (state != ST_IDLE)` where internal-state binding is permitted.
- `done` and `error` are one cycle wide; `error` implies `done`.
- `cmd_last` implies `cmd_op==OUTPUT` and is observed exactly once per
  successful operation.
- Reserved flag bit is always zero and unused fields match the specification.

### 6.2 Schedule invariants

- `i < k` and `j < k` whenever an index is semantically used.
- Matrix and matrix-vector phases cover each required `(i,j)` exactly once.
- CBD nonces are ordered and bounded as specified.
- `ACCUMULATE` is zero for `j=0` and one for later terms.
- `TRANSPOSE` appears exactly on PKE matrix sampling.
- `REENCRYPT` appears on every common re-encryption descriptor, on compare, and
  nowhere else.
- Counts equal the formulas in the specification.

### 6.3 Liveness

With assumptions that every issued command is eventually accepted and every
accepted command eventually returns exactly one completion or error, the
operation eventually reaches a terminal state. Fairness assumptions shall be
recorded; unconstrained external stalling makes bounded completion impossible.

## 7. Coverage

### 7.1 Functional coverage

Required coverpoints and crosses:

- all operation and parameter-set encodings, including invalid;
- operation x parameter set;
- every command opcode and logical object;
- each meaningful `cmd_param`, flag combination, index endpoint, and nonce;
- first/middle/last command positions;
- `cmd_ready` stall buckets and completion-delay buckets;
- error injection at every command opcode and phase;
- reset in each state, operation, phase class, and command position;
- simultaneous `cmd_done && cmd_error`;
- start in idle/issue/wait/done/error;
- successful/error/reset-aborted outcomes.

Required bins shall reach 100%. Cross exclusions shall cite a specification rule
that makes the combination illegal or unreachable.

### 7.2 Structural coverage

Release targets:

- 100% reachable statement and branch coverage;
- 100% reachable FSM state and transition coverage;
- 100% phase and phase-transition coverage;
- 100% expression/condition coverage where supported;
- at least 95% toggle coverage with reviewed exclusions.

These are closure requirements, not current measured results.

## 8. Regression tiers

| Tier | Trigger | Required content |
| --- | --- | --- |
| `T0` | Every RTL/DV change | Compile, lint smoke, valid/invalid request smoke |
| `T1` | Pull request | All nine traces, protocol/backpressure, field legality, directed reset/error tests |
| `T2` | Nightly | Full error/reset sweeps, randomized stress, assertions, code and functional coverage |
| `T3` | Release | Reproducible clean run, independent trace-model cross-check, coverage closure, integrated algorithm tests |

Each run shall archive revision, simulator/version, options, model revision,
seed list, pass/fail and assertion summaries, coverage database, and waiver set.

## 9. Current baseline and gaps

The existing testbench checks all nine expected traces, deterministic
`cmd_ready` stalls, delayed completion, descriptor stability during stalls, one
invalid operation, one invalid set, and one dispatcher-error scenario.

Known gaps:

- dispatcher errors are not swept across commands;
- reset interruption, held start, stray/early/held responses, and simultaneous
  done/error are not fully tested;
- no SVA, functional coverage, code coverage, formal proof, X-prop analysis, or
  independent trace model is archived;
- no integrated datapath or full FIPS 203 known-answer test exists;
- logical-object and operand semantics remain incomplete;
- FPGA/ASIC implementation evidence is absent.

## 10. Closure and waivers

Verification closes only when:

1. every normative requirement has a passing test or proof;
2. all T3 regressions pass with zero unexpected errors;
3. all required functional bins and structural targets are closed;
4. the independent trace model agrees with the primary model;
5. integrated KeyGen, Encaps, and Decaps tests pass for all parameter sets;
6. no open severity-1 or severity-2 defect remains;
7. the applicable flow in
   [IMPLEMENTATION_SIGNOFF.md](IMPLEMENTATION_SIGNOFF.md) is complete.

A waiver shall identify the requirement or coverage item, technical cause,
risk, owner, approver, compensating evidence, and expiration/review milestone.
It shall not convert an unverified algorithm or security property into a claim.
