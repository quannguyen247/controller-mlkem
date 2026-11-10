# ML-KEM Sequencer Specification

## 1. Document status

This document is the normative functional and integration specification for
`mlkem_sequencer_top`. The RTL in `Implementation/rtl/` remains the
implementation source of truth; discrepancies shall be resolved before release.

The terms **shall**, **shall not**, **should**, **may**, **TBD**, and
**UNVERIFIED** identify requirements, prohibitions, recommendations, permitted
choices, open decisions, and claims without current evidence.

Related documents:

- [Verification Plan](docs/VERIFICATION_PLAN.md)
- [Implementation Signoff Plan](docs/IMPLEMENTATION_SIGNOFF.md)

## 2. Scope

`mlkem_sequencer_top` is a single-clock command scheduler for:

- ML-KEM KeyGen;
- ML-KEM Encaps;
- ML-KEM Decaps;
- ML-KEM-512, ML-KEM-768, and ML-KEM-1024 parameter selections.

The sequencer emits one abstract command descriptor at a time and waits for an
external dispatcher to report completion before advancing.

### 2.1 Non-goals

The sequencer does not implement:

- Keccak/SHAKE, sampling, NTT, polynomial arithmetic, codec, key packing,
  ciphertext comparison, key selection, or output data movement;
- operand payloads, seed/message/key inputs, physical RAM addresses, object
  lifetime management, hazards, arbitration, DMA, AXI/APB registers, software
  control, interrupts, or timeout recovery;
- proof that an attached datapath implements FIPS 203;
- FIPS validation, constant-time execution, side-channel resistance,
  zeroization, masking, redundancy, or fault countermeasures.

It is therefore not a complete ML-KEM accelerator.

## 3. Normative references

1. NIST FIPS 203, *Module-Lattice-Based Key-Encapsulation Mechanism Standard*.
2. IEEE 1800, *SystemVerilog Language Reference Manual*.
3. IEEE 1800.2, *Universal Verification Methodology Language Reference Manual*,
   for the planned verification environment.

The command schedule is intended to represent the major operations of FIPS 203,
but command names alone do not establish algorithmic conformance. The exact
operand semantics and data dependencies listed as `TBD` shall be defined and
verified at accelerator integration.

## 4. Configuration and encoding

### 4.1 Parameter sets

| `parameter_set` | Name | `k` | `eta1` | `eta2` | `du` | `dv` |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| `2'b00` | ML-KEM-512 | 2 | 3 | 2 | 10 | 4 |
| `2'b01` | ML-KEM-768 | 3 | 2 | 2 | 10 | 4 |
| `2'b10` | ML-KEM-1024 | 4 | 2 | 2 | 11 | 5 |
| `2'b11` | Unsupported; outputs are not updated | N/A | N/A | N/A | N/A | N/A |

For a valid request, the five parameter outputs are latched from the selected
set. During idle before the first valid request, reset values are `k=0`,
`eta1=0`, `eta2=2`, `du=0`, and `dv=0`.

### 4.2 Operations

| `operation` | Meaning |
| ---: | --- |
| `2'b00` | KeyGen schedule |
| `2'b01` | Encaps schedule |
| `2'b10` | Decaps schedule |
| `2'b11` | Unsupported |

### 4.3 Command and object encoding

All symbolic values are normative and are defined in
`mlkem_sequencer_defs.vh`.

| `cmd_op` | Command | `cmd_op` | Command |
| ---: | --- | ---: | --- |
| 0 | `HASH_G` | 10 | `ENCODE` |
| 1 | `HASH_H` | 11 | `DECODE` |
| 2 | `HASH_J` | 12 | `COMPRESS` |
| 3 | `SAMPLE_MATRIX` | 13 | `DECOMPRESS` |
| 4 | `SAMPLE_CBD` | 14 | `MESSAGE_TO_POLY` |
| 5 | `NTT` | 15 | `POLY_TO_MESSAGE` |
| 6 | `INTT` | 16 | `PACK` |
| 7 | `BASEMUL_ACC` | 17 | `COMPARE` |
| 8 | `ADD` | 18 | `SELECT` |
| 9 | `SUB` | 19 | `OUTPUT` |

| `cmd_object` | Object | `cmd_object` | Object |
| ---: | --- | ---: | --- |
| 0 | `A` | 8 | `V` |
| 1 | `S` | 9 | `M` |
| 2 | `E` | 10 | `W` |
| 3 | `T` | 11 | `EK` |
| 4 | `Y` | 12 | `DK` |
| 5 | `E1` | 13 | `C` |
| 6 | `E2` | 14 | `K` |
| 7 | `U` | 15 | `TEMP` |

Object values are logical identifiers, not addresses. Their byte layout,
coefficient domain, storage allocation, ownership, and lifetime are `TBD` at
integration.

### 4.4 Descriptor fields

| Field | Width | Defined use |
| --- | ---: | --- |
| `cmd_op` | 5 | Requested abstract operation |
| `cmd_object` | 4 | Primary logical object |
| `cmd_i` | 3 | Vector/matrix row or element index where emitted |
| `cmd_j` | 3 | Matrix/vector reduction index where emitted |
| `cmd_param` | 4 | `eta`, codec width, or secondary logical object for current `ADD/SUB` commands |
| `cmd_nonce` | 8 | CBD sampling nonce |
| `cmd_flags[0]` | 1 | `TRANSPOSE` for transposed matrix sampling |
| `cmd_flags[1]` | 1 | `ACCUMULATE` after the first reduction term |
| `cmd_flags[2]` | 1 | `REENCRYPT` during decapsulation re-encryption; also asserted on `COMPARE` |
| `cmd_flags[3]` | 1 | Reserved; emitted as zero |
| `cmd_last` | 1 | High only on the final `OUTPUT` command |

Fields without a defined use in a command are emitted as zero. The meaning of
the primary and secondary operands inside `BASEMUL_ACC`, hashes, pack/unpack,
compare, select, and output is not fully encoded by this interface and is
`TBD`. Integration shall not infer an operand contract from object names alone.

## 5. Requirements

| ID | Normative requirement |
| --- | --- |
| `SEQ-CFG-001` | The sequencer shall accept exactly the three parameter-set encodings in Section 4.1. |
| `SEQ-CFG-002` | The sequencer shall accept exactly the three operation encodings in Section 4.2. |
| `SEQ-CFG-003` | A valid request shall latch `operation`, `parameter_set`, `k`, `eta1`, `eta2`, `du`, and `dv`. |
| `SEQ-CTL-001` | A request shall be accepted only when `start` is sampled high in `ST_IDLE`. |
| `SEQ-CTL-002` | `start` sampled while busy shall not alter the active operation. |
| `SEQ-CMD-001` | `cmd_valid` shall be high only while issuing one command descriptor. |
| `SEQ-CMD-002` | A command shall be accepted only when `cmd_valid && cmd_ready` is sampled high. |
| `SEQ-CMD-003` | After command acceptance, the sequencer shall wait for `cmd_done` or `cmd_error` before issuing another command. |
| `SEQ-CMD-004` | All command fields shall remain stable while `cmd_valid=1` and `cmd_ready=0`. |
| `SEQ-CMD-005` | Unused command fields shall be zero as defined in Section 4.4. |
| `SEQ-CMD-006` | `cmd_last` shall be high only for the final `OUTPUT` command. |
| `SEQ-SCH-001` | Valid KeyGen requests shall emit the schedule in Section 7.2. |
| `SEQ-SCH-002` | Valid Encaps requests shall emit the schedule in Section 7.3. |
| `SEQ-SCH-003` | Valid Decaps requests shall emit the schedule in Section 7.4. |
| `SEQ-ERR-001` | An unsupported request shall enter the one-cycle terminal error state without issuing a command. |
| `SEQ-ERR-002` | `cmd_error` while waiting shall abort the operation and enter the terminal error state. |
| `SEQ-ERR-003` | `cmd_done` without a pending accepted command shall have no architectural effect. |
| `SEQ-DON-001` | `done` shall be high for one terminal `ST_DONE` or `ST_ERROR` cycle. |
| `SEQ-RST-001` | `rst_n` shall be an active-low synchronous reset sampled on `posedge clk`. |
| `SEQ-RST-002` | A sampled reset shall abort the operation and restore the reset state without issuing `done`. |
| `SEQ-INT-001` | The dispatcher shall implement the missing operand, storage, and command semantics before system-level ML-KEM claims are made. |
| `SEQ-SEC-001` | Project documentation shall not claim FIPS validation or side-channel/fault resistance without separate evidence. |

## 6. Interface

### 6.1 Control and configuration

| Port | Dir. | Width | Semantics |
| --- | --- | ---: | --- |
| `clk` | In | 1 | Sequencer clock |
| `rst_n` | In | 1 | Active-low synchronous reset |
| `operation` | In | 2 | Operation selected at accepted `start` |
| `parameter_set` | In | 2 | Parameter set selected at accepted `start` |
| `start` | In | 1 | Request sampled in idle |
| `busy` | Out | 1 | High in all non-idle states, including terminal state |
| `done` | Out | 1 | One-cycle terminal indication |
| `error` | Out | 1 | High with `done` for an aborted/invalid operation |

### 6.2 Latched parameter outputs

| Port | Dir. | Width | Semantics |
| --- | --- | ---: | --- |
| `k` | Out | 3 | Module dimension |
| `eta1` | Out | 3 | Primary CBD parameter |
| `eta2` | Out | 3 | Secondary CBD parameter; always 2 for valid sets |
| `du` | Out | 4 | Ciphertext `u` compression/encoding width |
| `dv` | Out | 4 | Ciphertext `v` compression/encoding width |

### 6.3 Dispatcher interface

| Port | Dir. | Width | Semantics |
| --- | --- | ---: | --- |
| `cmd_valid` | Out | 1 | Descriptor is available |
| `cmd_ready` | In | 1 | Dispatcher accepts descriptor |
| `cmd_op` | Out | 5 | Command encoding |
| `cmd_object` | Out | 4 | Primary object encoding |
| `cmd_i` | Out | 3 | First index |
| `cmd_j` | Out | 3 | Second index |
| `cmd_param` | Out | 4 | Eta, width, or secondary object |
| `cmd_nonce` | Out | 8 | CBD nonce |
| `cmd_flags` | Out | 4 | Command modifiers |
| `cmd_last` | Out | 1 | Final output marker |
| `cmd_done` | In | 1 | Pending command completed successfully |
| `cmd_error` | In | 1 | Pending command failed; error has priority |

The command request and completion response are distinct phases. `cmd_done`
asserted in the same edge as initial command acceptance is not consumed because
the sequencer is still in `ST_ISSUE`; a dispatcher shall assert completion only
after acceptance while the sequencer is waiting. The dispatcher shall deassert
`cmd_done` and `cmd_error` before a subsequent command is accepted; a held
response can otherwise complete a later command.

There is no command tag. At most one command may be outstanding.

## 7. Schedule and FIPS 203 mapping

### 7.1 Mapping limits

The schedules below correspond to the major hash, sampling, polynomial,
encoding, packing, comparison, selection, and output stages expected in ML-KEM
KeyGen, Encaps, and Decaps. They do not specify hash input concatenation,
domain-separation bytes, SHAKE output lengths, key/ciphertext byte layouts,
arithmetic domains, twiddle order, rejection sampling details, or implicit
rejection data selection. Those contracts are `TBD` in the integrated
accelerator and shall be traced to the applicable FIPS 203 algorithms.

### 7.2 KeyGen command order

For `i,j = 0..k-1` in nested order:

1. `HASH_G(TEMP)`
2. `SAMPLE_MATRIX(A,i,j)` for all `i,j`
3. `SAMPLE_CBD(S,i,eta1,nonce=i)` for all `i`
4. `SAMPLE_CBD(E,i,eta1,nonce=k+i)` for all `i`
5. `NTT(S,i)` for all `i`
6. `NTT(E,i)` for all `i`
7. `BASEMUL_ACC(T,i,j)`, with `ACCUMULATE` when `j>0`
8. `ADD(T,i,param=E)` for all `i`
9. `ENCODE(T,i,param=12)` for all `i`
10. `ENCODE(S,i,param=12)` for all `i`
11. `PACK(EK)`
12. `HASH_H(EK)`
13. `PACK(DK)`
14. `OUTPUT(EK,last=1)`

Command count:

```text
Ckeygen(k) = 2*k^2 + 7*k + 5
```

### 7.3 Encaps command order

1. `HASH_H(EK)`
2. `HASH_G(M)`
3. Execute the common PKE-encrypt schedule below with `REENCRYPT=0`
4. `OUTPUT(K,last=1)`

Common PKE-encrypt schedule:

1. `DECODE(T,i,12)` for all `i`
2. `SAMPLE_MATRIX(A,i,j,TRANSPOSE)` for all `i,j`
3. `SAMPLE_CBD(Y,i,eta1,nonce=i)` for all `i`
4. `SAMPLE_CBD(E1,i,eta2,nonce=k+i)` for all `i`
5. `SAMPLE_CBD(E2,eta2,nonce=2k)`
6. `NTT(Y,i)` for all `i`
7. `BASEMUL_ACC(U,i,j)` for all `i,j`, accumulating when `j>0`
8. `INTT(U,i)` and `ADD(U,i,param=E1)` for all `i`
9. `BASEMUL_ACC(V,j)` for all `j`, accumulating when `j>0`
10. `INTT(V)`, `ADD(V,param=E2)`, `MESSAGE_TO_POLY(M)`,
    `ADD(V,param=M)`
11. `COMPRESS(U,i,du)` and `ENCODE(U,i,du)` for all `i`
12. `COMPRESS(V,dv)`, `ENCODE(V,dv)`, `PACK(C)`

Every common command carries `REENCRYPT` when invoked from Decaps
re-encryption. Command count:

```text
Cencaps(k) = 2*k^2 + 9*k + 11
```

### 7.4 Decaps command order

1. `DECODE(U,i,du)` for all `i`
2. `DECOMPRESS(U,i,du)` for all `i`
3. `DECODE(V,dv)`, `DECOMPRESS(V,dv)`
4. `DECODE(S,i,12)` for all `i`
5. `NTT(U,i)` for all `i`
6. `BASEMUL_ACC(W,j)` for all `j`, accumulating when `j>0`
7. `INTT(W)`, `SUB(W,param=V)`, `POLY_TO_MESSAGE(M)`, `HASH_G(M)`
8. Execute the common PKE-encrypt schedule with `REENCRYPT=1`
9. `COMPARE(C,REENCRYPT)`
10. `HASH_J(C)`
11. `SELECT(K)`
12. `OUTPUT(K,last=1)`

Command count:

```text
Cdecaps(k) = 2*k^2 + 14*k + 18
```

`COMPARE` and `SELECT` are requests to external logic. The sequencer does not
implement or prove constant-time ciphertext comparison, implicit rejection, or
secret selection.

## 8. Microarchitecture and timing

The RTL contains one-hot states:

```text
ST_IDLE -> ST_ISSUE -> ST_WAIT -> ST_ISSUE ... -> ST_DONE -> ST_IDLE
                                      \-> ST_ERROR -> ST_IDLE
```

`phase`, `index_i`, `index_j`, `nonce_r`, and `reencryption_r` generate the
descriptor. There are no data memories, FIFOs, payload datapaths, multiple clock
domains, explicit clock gates, or asynchronous reset logic.

For each command:

- the sequencer spends at least one cycle in `ST_ISSUE`;
- after acceptance, it spends at least one cycle in `ST_WAIT`;
- dispatcher completion latency is unbounded by this interface.

If every command is accepted in the first `ST_ISSUE` cycle and completes in the
first `ST_WAIT` cycle, a successful operation with `C` commands requires `2*C`
cycles from the edge accepting `start` through the edge entering `ST_DONE`.
This does not include the following return-to-idle cycle. Integrated latency is:

```text
L = sum over commands (issue_wait_cycles + execution_wait_cycles)
```

where each term is at least one cycle under the protocol. No maximum latency,
clock frequency, or throughput is specified.

## 9. Error and reset behavior

- Invalid operation or parameter-set input produces `done=1`, `error=1`, and
  `busy=1` in `ST_ERROR`, then returns to idle.
- `cmd_error` has priority over `cmd_done` while waiting.
- There is no retry, timeout, status code, command cancellation, or partial
  result cleanup.
- Reset aborts an operation without a terminal response.
- Unknown (`X`/`Z`) behavior is not architectural and is **UNVERIFIED**.
- Parameter outputs retain reset or last valid values after an invalid request;
  consumers shall qualify them by accepted request context.

## 10. Memory and security considerations

Only scheduler state and metadata are stored. No secret-key, ciphertext,
message, polynomial, or Keccak state is present in this repository.

The schedule and command count depend on operation and public parameter set,
not on runtime secret or ciphertext values, because no such values enter this
module. End-to-end timing can still vary with dispatcher latency, arbitration,
memory conflicts, errors, and external datapaths. No constant-time,
side-channel, zeroization, or fault-resistance claim is made.

## 11. Integration contract

Before system integration, the accelerator specification shall define:

- every command's complete inputs, outputs, and pre/postconditions;
- hash domain separation, concatenation, and byte counts;
- logical-object storage format, address mapping, lifetime, and hazards;
- NTT/Montgomery/coefficient representation at every boundary;
- sampler seeds, nonces, matrix index ordering, and transpose interpretation;
- pack/decode/compress data layout and byte endianness;
- compare result, `HASH_J` input, and `SELECT` fallback-key semantics;
- external visibility of both KeyGen results (`EK` and `DK`) and both Encaps
  results (`C` and `K`), because the final `OUTPUT` descriptor names only `EK`
  for KeyGen and only `K` for Encaps;
- command completion/error timing and cleanup;
- reset, abort, timeout, and zeroization policy.

Until this contract exists and is verified, the command trace is control intent,
not proof of a FIPS 203 implementation.

## 12. Traceability

| Requirement | RTL anchor | Planned verification |
| --- | --- | --- |
| `SEQ-CFG-001/002/003` | `mlkem_sequencer_funcs.vh`, `ST_IDLE` | `SEQ-V-CFG-001`, `SEQ-V-NEG-001` |
| `SEQ-CTL-001/002` | `ST_IDLE` request logic | `SEQ-V-CTL-001`, `SEQ-V-SVA-001` |
| `SEQ-CMD-001..006` | command decode, `ST_ISSUE`, `ST_WAIT` | `SEQ-V-IF-001`, `SEQ-V-SVA-002..005` |
| `SEQ-SCH-001` | KeyGen phase transitions | `SEQ-V-TRC-001` |
| `SEQ-SCH-002` | Encaps/common PKE phases | `SEQ-V-TRC-002` |
| `SEQ-SCH-003` | Decaps and re-encryption phases | `SEQ-V-TRC-003` |
| `SEQ-ERR-001/002/003` | `ST_ERROR`, `ST_WAIT` | `SEQ-V-NEG-001/002/003` |
| `SEQ-DON-001` | terminal states | `SEQ-V-SVA-006` |
| `SEQ-RST-001/002` | reset branch | `SEQ-V-RST-001/002` |
| `SEQ-INT-001`, `SEQ-SEC-001` | integration/release review | `SEQ-V-INT-001`, `SEQ-V-SEC-001` |

Closure criteria are in [VERIFICATION_PLAN.md](docs/VERIFICATION_PLAN.md).
FPGA and ASIC evidence requirements are in
[IMPLEMENTATION_SIGNOFF.md](docs/IMPLEMENTATION_SIGNOFF.md).
