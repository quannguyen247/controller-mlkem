function mlkem_set_supported;
    input [`MLKEM_SET_WIDTH-1:0] parameter_set;
    begin
        mlkem_set_supported = (parameter_set == `MLKEM_SET_512) ||
                              (parameter_set == `MLKEM_SET_768) ||
                              (parameter_set == `MLKEM_SET_1024);
    end
endfunction

function mlkem_operation_supported;
    input [`MLKEM_OPERATION_WIDTH-1:0] operation;
    begin
        mlkem_operation_supported = (operation == `MLKEM_OPERATION_KEYGEN) ||
                                    (operation == `MLKEM_OPERATION_ENCAPS) ||
                                    (operation == `MLKEM_OPERATION_DECAPS);
    end
endfunction

function [2:0] mlkem_k;
    input [`MLKEM_SET_WIDTH-1:0] parameter_set;
    begin
        case (parameter_set)
            `MLKEM_SET_512: mlkem_k = 3'd2;
            `MLKEM_SET_768: mlkem_k = 3'd3;
            `MLKEM_SET_1024: mlkem_k = 3'd4;
            default: mlkem_k = 3'd0;
        endcase
    end
endfunction

function [2:0] mlkem_eta1;
    input [`MLKEM_SET_WIDTH-1:0] parameter_set;
    begin
        case (parameter_set)
            `MLKEM_SET_512: mlkem_eta1 = 3'd3;
            `MLKEM_SET_768,
            `MLKEM_SET_1024: mlkem_eta1 = 3'd2;
            default: mlkem_eta1 = 3'd0;
        endcase
    end
endfunction

function [3:0] mlkem_du;
    input [`MLKEM_SET_WIDTH-1:0] parameter_set;
    begin
        case (parameter_set)
            `MLKEM_SET_512,
            `MLKEM_SET_768: mlkem_du = 4'd10;
            `MLKEM_SET_1024: mlkem_du = 4'd11;
            default: mlkem_du = 4'd0;
        endcase
    end
endfunction

function [3:0] mlkem_dv;
    input [`MLKEM_SET_WIDTH-1:0] parameter_set;
    begin
        case (parameter_set)
            `MLKEM_SET_512,
            `MLKEM_SET_768: mlkem_dv = 4'd4;
            `MLKEM_SET_1024: mlkem_dv = 4'd5;
            default: mlkem_dv = 4'd0;
        endcase
    end
endfunction
