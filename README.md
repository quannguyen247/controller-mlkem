# ML-KEM Sequencer FPGA / IP Core

ML-KEM Sequencer is a synthesizable Verilog RTL command scheduler for the three
FIPS 203 operations:

- ML-KEM KeyGen
- ML-KEM Encaps
- ML-KEM Decaps

The repository contains control RTL only. It does not duplicate the Keccak,
sampler, codec, or polynomial-engine datapaths. Instead, it emits a deterministic
command stream that an integrated accelerator can dispatch to those IP cores.

No Vivado project, AXI wrapper, or integrated accelerator top is included.

## Key Facts

- Top design:
  [Implementation/rtl/modules/mlkem_sequencer_top.v](Implementation/rtl/modules/mlkem_sequencer_top.v)
- Shared command and object definitions:
  [Implementation/rtl/utils/mlkem_sequencer_defs.vh](Implementation/rtl/utils/mlkem_sequencer_defs.vh)
- Parameter helpers:
  [Implementation/rtl/utils/mlkem_sequencer_funcs.vh](Implementation/rtl/utils/mlkem_sequencer_funcs.vh)
- Testbench:
  [Implementation/testbench/tb_mlkem_sequencer.sv](Implementation/testbench/tb_mlkem_sequencer.sv)
- Expected command-trace generator:
  [Implementation/vector/sequencer_test_vectors.py](Implementation/vector/sequencer_test_vectors.py)

## Supported Parameter Sets

| Parameter set | k | eta1 | eta2 | du | dv |
|---|---:|---:|---:|---:|---:|
| ML-KEM-512 | 2 | 3 | 2 | 10 | 4 |
| ML-KEM-768 | 3 | 2 | 2 | 10 | 4 |
| ML-KEM-1024 | 4 | 2 | 2 | 11 | 5 |

The selected parameter set is latched with the operation when `start` is
accepted.

## Command Interface

The sequencer exposes one command at a time:

- `cmd_valid` / `cmd_ready` accept the command descriptor.
- `cmd_done` advances to the next command.
- `cmd_error` aborts the operation.
- `cmd_op` identifies the required hash, sampler, polynomial, codec, packing,
  compare, select, or output operation.
- `cmd_object`, `cmd_i`, and `cmd_j` identify the logical vector or matrix item.
- `cmd_param` carries eta, encoding width, compression width, or source object.
- `cmd_nonce` carries the PRF nonce for CBD sampling.
- `cmd_flags` marks transpose, accumulation, and decapsulation re-encryption.
- `cmd_last` marks the final output command.

Command values are defined in `mlkem_sequencer_defs.vh`.

The command remains stable while `cmd_valid` is asserted and `cmd_ready` is
deasserted. After acceptance, the sequencer waits for `cmd_done` before issuing
the next command.

## Scheduled Operations

### KeyGen

The schedule covers seed expansion, matrix sampling, secret/error sampling,
NTTs, matrix-vector multiplication, error addition, key encoding, public-key
hashing, and final key packing.

### Encaps

The schedule covers public-key hashing, key/randomness derivation, public-key
decoding, transposed matrix sampling, noise sampling, polynomial encryption,
compression, ciphertext encoding, packing, and shared-secret output.

### Decaps

The schedule covers ciphertext and secret-key decoding, polynomial decryption,
message recovery, key/randomness derivation, deterministic re-encryption,
constant-time ciphertext comparison, fallback hash generation, key selection,
and shared-secret output.

## Verification

Generate expected command traces:

```powershell
python Implementation/vector/sequencer_test_vectors.py
```

The generated vectors cover all nine combinations of three operations and
three parameter sets. The testbench checks:

- every emitted command field;
- loop indices, nonces, eta, du, and dv;
- command stability under dispatcher backpressure;
- delayed `cmd_done` responses;
- exact command count and final-command marker;
- invalid operation and parameter-set rejection;
- immediate abort on dispatcher error.

## Directory Layout

- `Implementation/rtl/modules/` - synthesizable sequencer RTL
- `Implementation/rtl/utils/` - command, object, and parameter definitions
- `Implementation/testbench/` - ModelSim testbench
- `Implementation/vector/` - Python trace generator and generated traces

## Limitations

- The sequencer operates on logical objects and indices. Physical RAM-slot
  allocation belongs to the final accelerator integration.
- Command execution latency is external and unrestricted.
- Synthesis, implementation, timing, and utilization remain to be measured in
  the integration project.
