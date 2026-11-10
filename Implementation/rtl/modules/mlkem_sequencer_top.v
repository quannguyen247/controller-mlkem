`timescale 1ns / 1ps
`include "mlkem_sequencer_defs.vh"

module mlkem_sequencer_top (
    input wire clk,
    input wire rst_n,

    // Operation control
    input wire [`MLKEM_OPERATION_WIDTH-1:0] operation,
    input wire [`MLKEM_SET_WIDTH-1:0] parameter_set,
    input wire start,
    output wire busy,
    output wire done,
    output wire error,

    // Latched parameter set
    output wire [2:0] k,
    output wire [2:0] eta1,
    output wire [2:0] eta2,
    output wire [3:0] du,
    output wire [3:0] dv,

    // Command dispatcher
    output wire cmd_valid,
    input wire cmd_ready,
    output reg [`MLKEM_CMD_WIDTH-1:0] cmd_op,
    output reg [`MLKEM_OBJECT_WIDTH-1:0] cmd_object,
    output reg [2:0] cmd_i,
    output reg [2:0] cmd_j,
    output reg [3:0] cmd_param,
    output reg [7:0] cmd_nonce,
    output reg [3:0] cmd_flags,
    output reg cmd_last,
    input wire cmd_done,
    input wire cmd_error
);

    `include "mlkem_sequencer_funcs.vh"

    localparam [4:0] ST_IDLE  = 5'b00001;
    localparam [4:0] ST_ISSUE = 5'b00010;
    localparam [4:0] ST_WAIT  = 5'b00100;
    localparam [4:0] ST_DONE  = 5'b01000;
    localparam [4:0] ST_ERROR = 5'b10000;

    localparam [7:0] PH_KG_HASH_G       = 8'd1;
    localparam [7:0] PH_KG_MATRIX       = 8'd2;
    localparam [7:0] PH_KG_SAMPLE_S     = 8'd3;
    localparam [7:0] PH_KG_SAMPLE_E     = 8'd4;
    localparam [7:0] PH_KG_NTT_S        = 8'd5;
    localparam [7:0] PH_KG_NTT_E        = 8'd6;
    localparam [7:0] PH_KG_MUL_T        = 8'd7;
    localparam [7:0] PH_KG_ADD_E        = 8'd8;
    localparam [7:0] PH_KG_ENCODE_T     = 8'd9;
    localparam [7:0] PH_KG_ENCODE_S     = 8'd10;
    localparam [7:0] PH_KG_PACK_EK      = 8'd11;
    localparam [7:0] PH_KG_HASH_H       = 8'd12;
    localparam [7:0] PH_KG_PACK_DK      = 8'd13;

    localparam [7:0] PH_EN_HASH_H       = 8'd20;
    localparam [7:0] PH_EN_HASH_G       = 8'd21;

    localparam [7:0] PH_PKE_DECODE_T    = 8'd30;
    localparam [7:0] PH_PKE_MATRIX      = 8'd31;
    localparam [7:0] PH_PKE_SAMPLE_Y    = 8'd32;
    localparam [7:0] PH_PKE_SAMPLE_E1   = 8'd33;
    localparam [7:0] PH_PKE_SAMPLE_E2   = 8'd34;
    localparam [7:0] PH_PKE_NTT_Y       = 8'd35;
    localparam [7:0] PH_PKE_MUL_U       = 8'd36;
    localparam [7:0] PH_PKE_INTT_U      = 8'd37;
    localparam [7:0] PH_PKE_ADD_E1      = 8'd38;
    localparam [7:0] PH_PKE_MUL_V       = 8'd39;
    localparam [7:0] PH_PKE_INTT_V      = 8'd40;
    localparam [7:0] PH_PKE_ADD_E2      = 8'd41;
    localparam [7:0] PH_PKE_MESSAGE     = 8'd42;
    localparam [7:0] PH_PKE_ADD_M       = 8'd43;
    localparam [7:0] PH_PKE_COMPRESS_U  = 8'd44;
    localparam [7:0] PH_PKE_ENCODE_U    = 8'd45;
    localparam [7:0] PH_PKE_COMPRESS_V  = 8'd46;
    localparam [7:0] PH_PKE_ENCODE_V    = 8'd47;
    localparam [7:0] PH_PKE_PACK_C      = 8'd48;

    localparam [7:0] PH_DC_DECODE_U     = 8'd60;
    localparam [7:0] PH_DC_DECOMP_U     = 8'd61;
    localparam [7:0] PH_DC_DECODE_V     = 8'd62;
    localparam [7:0] PH_DC_DECOMP_V     = 8'd63;
    localparam [7:0] PH_DC_DECODE_S     = 8'd64;
    localparam [7:0] PH_DC_NTT_U        = 8'd65;
    localparam [7:0] PH_DC_MUL_W        = 8'd66;
    localparam [7:0] PH_DC_INTT_W       = 8'd67;
    localparam [7:0] PH_DC_SUB_W        = 8'd68;
    localparam [7:0] PH_DC_POLY_M       = 8'd69;
    localparam [7:0] PH_DC_HASH_G       = 8'd70;
    localparam [7:0] PH_DC_COMPARE      = 8'd71;
    localparam [7:0] PH_DC_HASH_J       = 8'd72;
    localparam [7:0] PH_DC_SELECT       = 8'd73;

    localparam [7:0] PH_OUTPUT          = 8'd80;

    reg [4:0] state;
    reg [7:0] phase;
    reg [`MLKEM_OPERATION_WIDTH-1:0] operation_r;
    reg [`MLKEM_SET_WIDTH-1:0] parameter_set_r;
    reg [2:0] k_r;
    reg [2:0] eta1_r;
    reg [2:0] eta2_r;
    reg [3:0] du_r;
    reg [3:0] dv_r;
    reg [2:0] index_i;
    reg [2:0] index_j;
    reg [7:0] nonce_r;
    reg reencryption_r;

    wire command_complete = (state == ST_WAIT) && cmd_done && !cmd_error;
    wire [3:0] reencrypt_flag =
        reencryption_r ? `MLKEM_FLAG_REENCRYPT : 4'd0;

    always @(*) begin
        cmd_op = `MLKEM_CMD_OUTPUT;
        cmd_object = `MLKEM_OBJECT_TEMP;
        cmd_i = 3'd0;
        cmd_j = 3'd0;
        cmd_param = 4'd0;
        cmd_nonce = 8'd0;
        cmd_flags = 4'd0;
        cmd_last = 1'b0;

        case (phase)
            PH_KG_HASH_G: begin
                cmd_op = `MLKEM_CMD_HASH_G;
                cmd_object = `MLKEM_OBJECT_TEMP;
            end
            PH_KG_MATRIX: begin
                cmd_op = `MLKEM_CMD_SAMPLE_MATRIX;
                cmd_object = `MLKEM_OBJECT_A;
                cmd_i = index_i;
                cmd_j = index_j;
            end
            PH_KG_SAMPLE_S: begin
                cmd_op = `MLKEM_CMD_SAMPLE_CBD;
                cmd_object = `MLKEM_OBJECT_S;
                cmd_i = index_i;
                cmd_param = {1'b0, eta1_r};
                cmd_nonce = nonce_r;
            end
            PH_KG_SAMPLE_E: begin
                cmd_op = `MLKEM_CMD_SAMPLE_CBD;
                cmd_object = `MLKEM_OBJECT_E;
                cmd_i = index_i;
                cmd_param = {1'b0, eta1_r};
                cmd_nonce = nonce_r;
            end
            PH_KG_NTT_S: begin
                cmd_op = `MLKEM_CMD_NTT;
                cmd_object = `MLKEM_OBJECT_S;
                cmd_i = index_i;
            end
            PH_KG_NTT_E: begin
                cmd_op = `MLKEM_CMD_NTT;
                cmd_object = `MLKEM_OBJECT_E;
                cmd_i = index_i;
            end
            PH_KG_MUL_T: begin
                cmd_op = `MLKEM_CMD_BASEMUL_ACC;
                cmd_object = `MLKEM_OBJECT_T;
                cmd_i = index_i;
                cmd_j = index_j;
                cmd_flags = index_j ? `MLKEM_FLAG_ACCUMULATE : 4'd0;
            end
            PH_KG_ADD_E: begin
                cmd_op = `MLKEM_CMD_ADD;
                cmd_object = `MLKEM_OBJECT_T;
                cmd_i = index_i;
                cmd_param = `MLKEM_OBJECT_E;
            end
            PH_KG_ENCODE_T: begin
                cmd_op = `MLKEM_CMD_ENCODE;
                cmd_object = `MLKEM_OBJECT_T;
                cmd_i = index_i;
                cmd_param = 4'd12;
            end
            PH_KG_ENCODE_S: begin
                cmd_op = `MLKEM_CMD_ENCODE;
                cmd_object = `MLKEM_OBJECT_S;
                cmd_i = index_i;
                cmd_param = 4'd12;
            end
            PH_KG_PACK_EK: begin
                cmd_op = `MLKEM_CMD_PACK;
                cmd_object = `MLKEM_OBJECT_EK;
            end
            PH_KG_HASH_H: begin
                cmd_op = `MLKEM_CMD_HASH_H;
                cmd_object = `MLKEM_OBJECT_EK;
            end
            PH_KG_PACK_DK: begin
                cmd_op = `MLKEM_CMD_PACK;
                cmd_object = `MLKEM_OBJECT_DK;
            end
            PH_EN_HASH_H: begin
                cmd_op = `MLKEM_CMD_HASH_H;
                cmd_object = `MLKEM_OBJECT_EK;
            end
            PH_EN_HASH_G,
            PH_DC_HASH_G: begin
                cmd_op = `MLKEM_CMD_HASH_G;
                cmd_object = `MLKEM_OBJECT_M;
            end
            PH_PKE_DECODE_T: begin
                cmd_op = `MLKEM_CMD_DECODE;
                cmd_object = `MLKEM_OBJECT_T;
                cmd_i = index_i;
                cmd_param = 4'd12;
                cmd_flags = reencrypt_flag;
            end
            PH_PKE_MATRIX: begin
                cmd_op = `MLKEM_CMD_SAMPLE_MATRIX;
                cmd_object = `MLKEM_OBJECT_A;
                cmd_i = index_i;
                cmd_j = index_j;
                cmd_flags = reencrypt_flag | `MLKEM_FLAG_TRANSPOSE;
            end
            PH_PKE_SAMPLE_Y: begin
                cmd_op = `MLKEM_CMD_SAMPLE_CBD;
                cmd_object = `MLKEM_OBJECT_Y;
                cmd_i = index_i;
                cmd_param = {1'b0, eta1_r};
                cmd_nonce = nonce_r;
                cmd_flags = reencrypt_flag;
            end
            PH_PKE_SAMPLE_E1: begin
                cmd_op = `MLKEM_CMD_SAMPLE_CBD;
                cmd_object = `MLKEM_OBJECT_E1;
                cmd_i = index_i;
                cmd_param = {1'b0, eta2_r};
                cmd_nonce = nonce_r;
                cmd_flags = reencrypt_flag;
            end
            PH_PKE_SAMPLE_E2: begin
                cmd_op = `MLKEM_CMD_SAMPLE_CBD;
                cmd_object = `MLKEM_OBJECT_E2;
                cmd_param = {1'b0, eta2_r};
                cmd_nonce = nonce_r;
                cmd_flags = reencrypt_flag;
            end
            PH_PKE_NTT_Y: begin
                cmd_op = `MLKEM_CMD_NTT;
                cmd_object = `MLKEM_OBJECT_Y;
                cmd_i = index_i;
                cmd_flags = reencrypt_flag;
            end
            PH_PKE_MUL_U: begin
                cmd_op = `MLKEM_CMD_BASEMUL_ACC;
                cmd_object = `MLKEM_OBJECT_U;
                cmd_i = index_i;
                cmd_j = index_j;
                cmd_flags = reencrypt_flag |
                            (index_j ? `MLKEM_FLAG_ACCUMULATE : 4'd0);
            end
            PH_PKE_INTT_U: begin
                cmd_op = `MLKEM_CMD_INTT;
                cmd_object = `MLKEM_OBJECT_U;
                cmd_i = index_i;
                cmd_flags = reencrypt_flag;
            end
            PH_PKE_ADD_E1: begin
                cmd_op = `MLKEM_CMD_ADD;
                cmd_object = `MLKEM_OBJECT_U;
                cmd_i = index_i;
                cmd_param = `MLKEM_OBJECT_E1;
                cmd_flags = reencrypt_flag;
            end
            PH_PKE_MUL_V: begin
                cmd_op = `MLKEM_CMD_BASEMUL_ACC;
                cmd_object = `MLKEM_OBJECT_V;
                cmd_j = index_j;
                cmd_flags = reencrypt_flag |
                            (index_j ? `MLKEM_FLAG_ACCUMULATE : 4'd0);
            end
            PH_PKE_INTT_V: begin
                cmd_op = `MLKEM_CMD_INTT;
                cmd_object = `MLKEM_OBJECT_V;
                cmd_flags = reencrypt_flag;
            end
            PH_PKE_ADD_E2: begin
                cmd_op = `MLKEM_CMD_ADD;
                cmd_object = `MLKEM_OBJECT_V;
                cmd_param = `MLKEM_OBJECT_E2;
                cmd_flags = reencrypt_flag;
            end
            PH_PKE_MESSAGE: begin
                cmd_op = `MLKEM_CMD_MESSAGE_TO_POLY;
                cmd_object = `MLKEM_OBJECT_M;
                cmd_flags = reencrypt_flag;
            end
            PH_PKE_ADD_M: begin
                cmd_op = `MLKEM_CMD_ADD;
                cmd_object = `MLKEM_OBJECT_V;
                cmd_param = `MLKEM_OBJECT_M;
                cmd_flags = reencrypt_flag;
            end
            PH_PKE_COMPRESS_U: begin
                cmd_op = `MLKEM_CMD_COMPRESS;
                cmd_object = `MLKEM_OBJECT_U;
                cmd_i = index_i;
                cmd_param = du_r;
                cmd_flags = reencrypt_flag;
            end
            PH_PKE_ENCODE_U: begin
                cmd_op = `MLKEM_CMD_ENCODE;
                cmd_object = `MLKEM_OBJECT_U;
                cmd_i = index_i;
                cmd_param = du_r;
                cmd_flags = reencrypt_flag;
            end
            PH_PKE_COMPRESS_V: begin
                cmd_op = `MLKEM_CMD_COMPRESS;
                cmd_object = `MLKEM_OBJECT_V;
                cmd_param = dv_r;
                cmd_flags = reencrypt_flag;
            end
            PH_PKE_ENCODE_V: begin
                cmd_op = `MLKEM_CMD_ENCODE;
                cmd_object = `MLKEM_OBJECT_V;
                cmd_param = dv_r;
                cmd_flags = reencrypt_flag;
            end
            PH_PKE_PACK_C: begin
                cmd_op = `MLKEM_CMD_PACK;
                cmd_object = `MLKEM_OBJECT_C;
                cmd_flags = reencrypt_flag;
            end
            PH_DC_DECODE_U: begin
                cmd_op = `MLKEM_CMD_DECODE;
                cmd_object = `MLKEM_OBJECT_U;
                cmd_i = index_i;
                cmd_param = du_r;
            end
            PH_DC_DECOMP_U: begin
                cmd_op = `MLKEM_CMD_DECOMPRESS;
                cmd_object = `MLKEM_OBJECT_U;
                cmd_i = index_i;
                cmd_param = du_r;
            end
            PH_DC_DECODE_V: begin
                cmd_op = `MLKEM_CMD_DECODE;
                cmd_object = `MLKEM_OBJECT_V;
                cmd_param = dv_r;
            end
            PH_DC_DECOMP_V: begin
                cmd_op = `MLKEM_CMD_DECOMPRESS;
                cmd_object = `MLKEM_OBJECT_V;
                cmd_param = dv_r;
            end
            PH_DC_DECODE_S: begin
                cmd_op = `MLKEM_CMD_DECODE;
                cmd_object = `MLKEM_OBJECT_S;
                cmd_i = index_i;
                cmd_param = 4'd12;
            end
            PH_DC_NTT_U: begin
                cmd_op = `MLKEM_CMD_NTT;
                cmd_object = `MLKEM_OBJECT_U;
                cmd_i = index_i;
            end
            PH_DC_MUL_W: begin
                cmd_op = `MLKEM_CMD_BASEMUL_ACC;
                cmd_object = `MLKEM_OBJECT_W;
                cmd_j = index_j;
                cmd_flags = index_j ? `MLKEM_FLAG_ACCUMULATE : 4'd0;
            end
            PH_DC_INTT_W: begin
                cmd_op = `MLKEM_CMD_INTT;
                cmd_object = `MLKEM_OBJECT_W;
            end
            PH_DC_SUB_W: begin
                cmd_op = `MLKEM_CMD_SUB;
                cmd_object = `MLKEM_OBJECT_W;
                cmd_param = `MLKEM_OBJECT_V;
            end
            PH_DC_POLY_M: begin
                cmd_op = `MLKEM_CMD_POLY_TO_MESSAGE;
                cmd_object = `MLKEM_OBJECT_M;
            end
            PH_DC_COMPARE: begin
                cmd_op = `MLKEM_CMD_COMPARE;
                cmd_object = `MLKEM_OBJECT_C;
                cmd_flags = `MLKEM_FLAG_REENCRYPT;
            end
            PH_DC_HASH_J: begin
                cmd_op = `MLKEM_CMD_HASH_J;
                cmd_object = `MLKEM_OBJECT_C;
            end
            PH_DC_SELECT: begin
                cmd_op = `MLKEM_CMD_SELECT;
                cmd_object = `MLKEM_OBJECT_K;
            end
            PH_OUTPUT: begin
                cmd_op = `MLKEM_CMD_OUTPUT;
                cmd_object = (operation_r == `MLKEM_OPERATION_KEYGEN) ?
                             `MLKEM_OBJECT_EK : `MLKEM_OBJECT_K;
                cmd_last = 1'b1;
            end
            default: begin
                cmd_op = `MLKEM_CMD_OUTPUT;
                cmd_object = `MLKEM_OBJECT_TEMP;
            end
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            phase <= PH_KG_HASH_G;
            operation_r <= `MLKEM_OPERATION_KEYGEN;
            parameter_set_r <= `MLKEM_SET_512;
            k_r <= 3'd0;
            eta1_r <= 3'd0;
            eta2_r <= 3'd2;
            du_r <= 4'd0;
            dv_r <= 4'd0;
            index_i <= 3'd0;
            index_j <= 3'd0;
            nonce_r <= 8'd0;
            reencryption_r <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        if (mlkem_set_supported(parameter_set) &&
                            mlkem_operation_supported(operation)) begin
                            operation_r <= operation;
                            parameter_set_r <= parameter_set;
                            k_r <= mlkem_k(parameter_set);
                            eta1_r <= mlkem_eta1(parameter_set);
                            eta2_r <= 3'd2;
                            du_r <= mlkem_du(parameter_set);
                            dv_r <= mlkem_dv(parameter_set);
                            index_i <= 3'd0;
                            index_j <= 3'd0;
                            nonce_r <= 8'd0;
                            reencryption_r <= 1'b0;

                            case (operation)
                                `MLKEM_OPERATION_KEYGEN: phase <= PH_KG_HASH_G;
                                `MLKEM_OPERATION_ENCAPS: phase <= PH_EN_HASH_H;
                                `MLKEM_OPERATION_DECAPS: phase <= PH_DC_DECODE_U;
                                default: phase <= PH_OUTPUT;
                            endcase
                            state <= ST_ISSUE;
                        end else begin
                            state <= ST_ERROR;
                        end
                    end
                end
                ST_ISSUE: begin
                    if (cmd_ready)
                        state <= ST_WAIT;
                end
                ST_WAIT: begin
                    if (cmd_error) begin
                        state <= ST_ERROR;
                    end else if (command_complete) begin
                        state <= ST_ISSUE;

                        case (phase)
                            PH_KG_HASH_G: begin
                                phase <= PH_KG_MATRIX;
                            end
                            PH_KG_MATRIX: begin
                                if (index_j + 1'b1 < k_r) begin
                                    index_j <= index_j + 1'b1;
                                end else if (index_i + 1'b1 < k_r) begin
                                    index_i <= index_i + 1'b1;
                                    index_j <= 3'd0;
                                end else begin
                                    index_i <= 3'd0;
                                    index_j <= 3'd0;
                                    nonce_r <= 8'd0;
                                    phase <= PH_KG_SAMPLE_S;
                                end
                            end
                            PH_KG_SAMPLE_S: begin
                                nonce_r <= nonce_r + 1'b1;
                                if (index_i + 1'b1 < k_r) begin
                                    index_i <= index_i + 1'b1;
                                end else begin
                                    index_i <= 3'd0;
                                    phase <= PH_KG_SAMPLE_E;
                                end
                            end
                            PH_KG_SAMPLE_E: begin
                                nonce_r <= nonce_r + 1'b1;
                                if (index_i + 1'b1 < k_r) begin
                                    index_i <= index_i + 1'b1;
                                end else begin
                                    index_i <= 3'd0;
                                    phase <= PH_KG_NTT_S;
                                end
                            end
                            PH_KG_NTT_S: begin
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    phase <= PH_KG_NTT_E;
                                end
                            end
                            PH_KG_NTT_E: begin
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    index_j <= 3'd0;
                                    phase <= PH_KG_MUL_T;
                                end
                            end
                            PH_KG_MUL_T: begin
                                if (index_j + 1'b1 < k_r) begin
                                    index_j <= index_j + 1'b1;
                                end else if (index_i + 1'b1 < k_r) begin
                                    index_i <= index_i + 1'b1;
                                    index_j <= 3'd0;
                                end else begin
                                    index_i <= 3'd0;
                                    index_j <= 3'd0;
                                    phase <= PH_KG_ADD_E;
                                end
                            end
                            PH_KG_ADD_E: begin
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    phase <= PH_KG_ENCODE_T;
                                end
                            end
                            PH_KG_ENCODE_T: begin
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    phase <= PH_KG_ENCODE_S;
                                end
                            end
                            PH_KG_ENCODE_S: begin
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    phase <= PH_KG_PACK_EK;
                                end
                            end
                            PH_KG_PACK_EK: phase <= PH_KG_HASH_H;
                            PH_KG_HASH_H: phase <= PH_KG_PACK_DK;
                            PH_KG_PACK_DK: phase <= PH_OUTPUT;

                            PH_EN_HASH_H: phase <= PH_EN_HASH_G;
                            PH_EN_HASH_G: begin
                                index_i <= 3'd0;
                                index_j <= 3'd0;
                                nonce_r <= 8'd0;
                                reencryption_r <= 1'b0;
                                phase <= PH_PKE_DECODE_T;
                            end

                            PH_PKE_DECODE_T: begin
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    index_j <= 3'd0;
                                    phase <= PH_PKE_MATRIX;
                                end
                            end
                            PH_PKE_MATRIX: begin
                                if (index_j + 1'b1 < k_r) begin
                                    index_j <= index_j + 1'b1;
                                end else if (index_i + 1'b1 < k_r) begin
                                    index_i <= index_i + 1'b1;
                                    index_j <= 3'd0;
                                end else begin
                                    index_i <= 3'd0;
                                    index_j <= 3'd0;
                                    nonce_r <= 8'd0;
                                    phase <= PH_PKE_SAMPLE_Y;
                                end
                            end
                            PH_PKE_SAMPLE_Y: begin
                                nonce_r <= nonce_r + 1'b1;
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    phase <= PH_PKE_SAMPLE_E1;
                                end
                            end
                            PH_PKE_SAMPLE_E1: begin
                                nonce_r <= nonce_r + 1'b1;
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    phase <= PH_PKE_SAMPLE_E2;
                                end
                            end
                            PH_PKE_SAMPLE_E2: begin
                                index_i <= 3'd0;
                                phase <= PH_PKE_NTT_Y;
                            end
                            PH_PKE_NTT_Y: begin
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    index_j <= 3'd0;
                                    phase <= PH_PKE_MUL_U;
                                end
                            end
                            PH_PKE_MUL_U: begin
                                if (index_j + 1'b1 < k_r) begin
                                    index_j <= index_j + 1'b1;
                                end else if (index_i + 1'b1 < k_r) begin
                                    index_i <= index_i + 1'b1;
                                    index_j <= 3'd0;
                                end else begin
                                    index_i <= 3'd0;
                                    index_j <= 3'd0;
                                    phase <= PH_PKE_INTT_U;
                                end
                            end
                            PH_PKE_INTT_U: begin
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    phase <= PH_PKE_ADD_E1;
                                end
                            end
                            PH_PKE_ADD_E1: begin
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    index_j <= 3'd0;
                                    phase <= PH_PKE_MUL_V;
                                end
                            end
                            PH_PKE_MUL_V: begin
                                if (index_j + 1'b1 < k_r)
                                    index_j <= index_j + 1'b1;
                                else begin
                                    index_j <= 3'd0;
                                    phase <= PH_PKE_INTT_V;
                                end
                            end
                            PH_PKE_INTT_V: phase <= PH_PKE_ADD_E2;
                            PH_PKE_ADD_E2: phase <= PH_PKE_MESSAGE;
                            PH_PKE_MESSAGE: phase <= PH_PKE_ADD_M;
                            PH_PKE_ADD_M: begin
                                index_i <= 3'd0;
                                phase <= PH_PKE_COMPRESS_U;
                            end
                            PH_PKE_COMPRESS_U: begin
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    phase <= PH_PKE_ENCODE_U;
                                end
                            end
                            PH_PKE_ENCODE_U: begin
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    phase <= PH_PKE_COMPRESS_V;
                                end
                            end
                            PH_PKE_COMPRESS_V: phase <= PH_PKE_ENCODE_V;
                            PH_PKE_ENCODE_V: phase <= PH_PKE_PACK_C;
                            PH_PKE_PACK_C: begin
                                if (reencryption_r)
                                    phase <= PH_DC_COMPARE;
                                else
                                    phase <= PH_OUTPUT;
                            end

                            PH_DC_DECODE_U: begin
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    phase <= PH_DC_DECOMP_U;
                                end
                            end
                            PH_DC_DECOMP_U: begin
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    phase <= PH_DC_DECODE_V;
                                end
                            end
                            PH_DC_DECODE_V: phase <= PH_DC_DECOMP_V;
                            PH_DC_DECOMP_V: begin
                                index_i <= 3'd0;
                                phase <= PH_DC_DECODE_S;
                            end
                            PH_DC_DECODE_S: begin
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    phase <= PH_DC_NTT_U;
                                end
                            end
                            PH_DC_NTT_U: begin
                                if (index_i + 1'b1 < k_r)
                                    index_i <= index_i + 1'b1;
                                else begin
                                    index_i <= 3'd0;
                                    index_j <= 3'd0;
                                    phase <= PH_DC_MUL_W;
                                end
                            end
                            PH_DC_MUL_W: begin
                                if (index_j + 1'b1 < k_r)
                                    index_j <= index_j + 1'b1;
                                else begin
                                    index_j <= 3'd0;
                                    phase <= PH_DC_INTT_W;
                                end
                            end
                            PH_DC_INTT_W: phase <= PH_DC_SUB_W;
                            PH_DC_SUB_W: phase <= PH_DC_POLY_M;
                            PH_DC_POLY_M: phase <= PH_DC_HASH_G;
                            PH_DC_HASH_G: begin
                                index_i <= 3'd0;
                                index_j <= 3'd0;
                                nonce_r <= 8'd0;
                                reencryption_r <= 1'b1;
                                phase <= PH_PKE_DECODE_T;
                            end
                            PH_DC_COMPARE: phase <= PH_DC_HASH_J;
                            PH_DC_HASH_J: phase <= PH_DC_SELECT;
                            PH_DC_SELECT: phase <= PH_OUTPUT;
                            PH_OUTPUT: state <= ST_DONE;
                            default: state <= ST_ERROR;
                        endcase
                    end
                end
                ST_DONE: state <= ST_IDLE;
                ST_ERROR: state <= ST_IDLE;
                default: state <= ST_IDLE;
            endcase
        end
    end

    assign k = k_r;
    assign eta1 = eta1_r;
    assign eta2 = eta2_r;
    assign du = du_r;
    assign dv = dv_r;
    assign cmd_valid = (state == ST_ISSUE);
    assign busy = (state != ST_IDLE);
    assign done = (state == ST_DONE) || (state == ST_ERROR);
    assign error = (state == ST_ERROR);

endmodule
