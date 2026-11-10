import sys
from pathlib import Path

VECTORS = Path(__file__).resolve().parent

SET_512 = 0
SET_768 = 1
SET_1024 = 2

OP_KEYGEN = 0
OP_ENCAPS = 1
OP_DECAPS = 2

CMD_HASH_G = 0
CMD_HASH_H = 1
CMD_HASH_J = 2
CMD_SAMPLE_MATRIX = 3
CMD_SAMPLE_CBD = 4
CMD_NTT = 5
CMD_INTT = 6
CMD_BASEMUL_ACC = 7
CMD_ADD = 8
CMD_SUB = 9
CMD_ENCODE = 10
CMD_DECODE = 11
CMD_COMPRESS = 12
CMD_DECOMPRESS = 13
CMD_MESSAGE_TO_POLY = 14
CMD_POLY_TO_MESSAGE = 15
CMD_PACK = 16
CMD_COMPARE = 17
CMD_SELECT = 18
CMD_OUTPUT = 19

OBJ_A = 0
OBJ_S = 1
OBJ_E = 2
OBJ_T = 3
OBJ_Y = 4
OBJ_E1 = 5
OBJ_E2 = 6
OBJ_U = 7
OBJ_V = 8
OBJ_M = 9
OBJ_W = 10
OBJ_EK = 11
OBJ_DK = 12
OBJ_C = 13
OBJ_K = 14
OBJ_TEMP = 15

FLAG_TRANSPOSE = 1
FLAG_ACCUMULATE = 2
FLAG_REENCRYPT = 4

PARAMS = {
    SET_512: (2, 3, 2, 10, 4),
    SET_768: (3, 2, 2, 10, 4),
    SET_1024: (4, 2, 2, 11, 5),
}

def emit(trace, op, obj=0, i=0, j=0, param=0, nonce=0, flags=0, last=0):
    trace.append(
        op |
        (obj << 5) |
        (i << 9) |
        (j << 12) |
        (param << 15) |
        (nonce << 19) |
        (flags << 27) |
        (last << 31)
    )

def append_pke_encrypt(trace, k, eta1, eta2, du, dv, reencrypt):
    flags_base = FLAG_REENCRYPT if reencrypt else 0

    for i in range(k):
        emit(trace, CMD_DECODE, OBJ_T, i=i, param=12, flags=flags_base)

    for i in range(k):
        for j in range(k):
            emit(trace, CMD_SAMPLE_MATRIX, OBJ_A, i=i, j=j,
                 flags=flags_base | FLAG_TRANSPOSE)

    nonce = 0
    for i in range(k):
        emit(trace, CMD_SAMPLE_CBD, OBJ_Y, i=i, param=eta1,
             nonce=nonce, flags=flags_base)
        nonce += 1

    for i in range(k):
        emit(trace, CMD_SAMPLE_CBD, OBJ_E1, i=i, param=eta2,
             nonce=nonce, flags=flags_base)
        nonce += 1

    emit(trace, CMD_SAMPLE_CBD, OBJ_E2, param=eta2,
         nonce=nonce, flags=flags_base)

    for i in range(k):
        emit(trace, CMD_NTT, OBJ_Y, i=i, flags=flags_base)

    for i in range(k):
        for j in range(k):
            flags = flags_base | (FLAG_ACCUMULATE if j else 0)
            emit(trace, CMD_BASEMUL_ACC, OBJ_U, i=i, j=j, flags=flags)

    for i in range(k):
        emit(trace, CMD_INTT, OBJ_U, i=i, flags=flags_base)
    for i in range(k):
        emit(trace, CMD_ADD, OBJ_U, i=i, param=OBJ_E1,
             flags=flags_base)

    for j in range(k):
        flags = flags_base | (FLAG_ACCUMULATE if j else 0)
        emit(trace, CMD_BASEMUL_ACC, OBJ_V, j=j, flags=flags)

    emit(trace, CMD_INTT, OBJ_V, flags=flags_base)
    emit(trace, CMD_ADD, OBJ_V, param=OBJ_E2, flags=flags_base)
    emit(trace, CMD_MESSAGE_TO_POLY, OBJ_M, flags=flags_base)
    emit(trace, CMD_ADD, OBJ_V, param=OBJ_M, flags=flags_base)

    for i in range(k):
        emit(trace, CMD_COMPRESS, OBJ_U, i=i, param=du, flags=flags_base)
    for i in range(k):
        emit(trace, CMD_ENCODE, OBJ_U, i=i, param=du, flags=flags_base)

    emit(trace, CMD_COMPRESS, OBJ_V, param=dv, flags=flags_base)
    emit(trace, CMD_ENCODE, OBJ_V, param=dv, flags=flags_base)
    emit(trace, CMD_PACK, OBJ_C, flags=flags_base)

def keygen_trace(parameter_set):
    k, eta1, _, _, _ = PARAMS[parameter_set]
    trace = []
    emit(trace, CMD_HASH_G, OBJ_TEMP)

    for i in range(k):
        for j in range(k):
            emit(trace, CMD_SAMPLE_MATRIX, OBJ_A, i=i, j=j)

    nonce = 0
    for i in range(k):
        emit(trace, CMD_SAMPLE_CBD, OBJ_S, i=i, param=eta1, nonce=nonce)
        nonce += 1
    for i in range(k):
        emit(trace, CMD_SAMPLE_CBD, OBJ_E, i=i, param=eta1, nonce=nonce)
        nonce += 1

    for i in range(k):
        emit(trace, CMD_NTT, OBJ_S, i=i)
    for i in range(k):
        emit(trace, CMD_NTT, OBJ_E, i=i)

    for i in range(k):
        for j in range(k):
            emit(trace, CMD_BASEMUL_ACC, OBJ_T, i=i, j=j,
                 flags=FLAG_ACCUMULATE if j else 0)

    for i in range(k):
        emit(trace, CMD_ADD, OBJ_T, i=i, param=OBJ_E)
    for i in range(k):
        emit(trace, CMD_ENCODE, OBJ_T, i=i, param=12)
    for i in range(k):
        emit(trace, CMD_ENCODE, OBJ_S, i=i, param=12)

    emit(trace, CMD_PACK, OBJ_EK)
    emit(trace, CMD_HASH_H, OBJ_EK)
    emit(trace, CMD_PACK, OBJ_DK)
    emit(trace, CMD_OUTPUT, OBJ_EK, last=1)
    return trace

def encaps_trace(parameter_set):
    k, eta1, eta2, du, dv = PARAMS[parameter_set]
    trace = []
    emit(trace, CMD_HASH_H, OBJ_EK)
    emit(trace, CMD_HASH_G, OBJ_M)
    append_pke_encrypt(trace, k, eta1, eta2, du, dv, False)
    emit(trace, CMD_OUTPUT, OBJ_K, last=1)
    return trace

def decaps_trace(parameter_set):
    k, eta1, eta2, du, dv = PARAMS[parameter_set]
    trace = []

    for i in range(k):
        emit(trace, CMD_DECODE, OBJ_U, i=i, param=du)
    for i in range(k):
        emit(trace, CMD_DECOMPRESS, OBJ_U, i=i, param=du)
    emit(trace, CMD_DECODE, OBJ_V, param=dv)
    emit(trace, CMD_DECOMPRESS, OBJ_V, param=dv)

    for i in range(k):
        emit(trace, CMD_DECODE, OBJ_S, i=i, param=12)
    for i in range(k):
        emit(trace, CMD_NTT, OBJ_U, i=i)
    for i in range(k):
        emit(trace, CMD_BASEMUL_ACC, OBJ_W, j=i,
             flags=FLAG_ACCUMULATE if i else 0)

    emit(trace, CMD_INTT, OBJ_W)
    emit(trace, CMD_SUB, OBJ_W, param=OBJ_V)
    emit(trace, CMD_POLY_TO_MESSAGE, OBJ_M)
    emit(trace, CMD_HASH_G, OBJ_M)

    append_pke_encrypt(trace, k, eta1, eta2, du, dv, True)
    emit(trace, CMD_COMPARE, OBJ_C, flags=FLAG_REENCRYPT)
    emit(trace, CMD_HASH_J, OBJ_C)
    emit(trace, CMD_SELECT, OBJ_K)
    emit(trace, CMD_OUTPUT, OBJ_K, last=1)
    return trace

def write_mem(path, values, width):
    hex_width = (width + 3) // 4
    with open(path, "w") as file:
        for value in values:
            file.write(f"{value:0{hex_width}x}\n")

def generate():
    commands = []
    metadata = []

    for parameter_set in (SET_512, SET_768, SET_1024):
        for operation, builder in (
            (OP_KEYGEN, keygen_trace),
            (OP_ENCAPS, encaps_trace),
            (OP_DECAPS, decaps_trace),
        ):
            trace = builder(parameter_set)
            offset = len(commands)
            commands.extend(trace)
            metadata.append(
                operation |
                (parameter_set << 2) |
                (offset << 4) |
                (len(trace) << 16)
            )

    write_mem(VECTORS / "sequencer_cmd.mem", commands, 32)
    write_mem(VECTORS / "sequencer_cases.mem", metadata, 28)
    (VECTORS / "sequencer_tv_spec.txt").write_text(
        f"case_count={len(metadata)}\n"
        f"command_count={len(commands)}\n"
    )
    return len(metadata), len(commands)

def clear():
    for path in VECTORS.glob("sequencer_*.mem"):
        path.unlink()
    spec = VECTORS / "sequencer_tv_spec.txt"
    if spec.exists():
        spec.unlink()

def main():
    if len(sys.argv) > 1 and sys.argv[1].lower() == "clear":
        clear()
        print("Cleared sequencer vectors.")
        return 0

    case_count, command_count = generate()
    print(f"Generated {case_count} traces and {command_count} commands.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
