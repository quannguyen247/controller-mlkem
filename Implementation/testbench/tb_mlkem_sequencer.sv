`timescale 1ns / 1ps

module tb_mlkem_sequencer;

    localparam integer TIMEOUT_CYCLES = 20000;
    localparam integer MAX_CASES = 16;
    localparam integer MAX_COMMANDS = 1024;

    logic clk, rst_n;
    logic [1:0] operation, parameter_set;
    logic start, busy, done, error;
    logic [2:0] k, eta1, eta2;
    logic [3:0] du, dv;

    logic cmd_valid, cmd_ready;
    logic [4:0] cmd_op;
    logic [3:0] cmd_object;
    logic [2:0] cmd_i, cmd_j;
    logic [3:0] cmd_param;
    logic [7:0] cmd_nonce;
    logic [3:0] cmd_flags;
    logic cmd_last;
    logic cmd_done, cmd_error;

    logic [27:0] case_vectors [0:MAX_CASES-1];
    logic [31:0] command_vectors [0:MAX_COMMANDS-1];
    logic [639:0] line_buffer;

    int case_count, command_count;
    int case_idx, error_count, spec_fd;

    mlkem_sequencer_top u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .operation(operation),
        .parameter_set(parameter_set),
        .start(start),
        .busy(busy),
        .done(done),
        .error(error),
        .k(k),
        .eta1(eta1),
        .eta2(eta2),
        .du(du),
        .dv(dv),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_op(cmd_op),
        .cmd_object(cmd_object),
        .cmd_i(cmd_i),
        .cmd_j(cmd_j),
        .cmd_param(cmd_param),
        .cmd_nonce(cmd_nonce),
        .cmd_flags(cmd_flags),
        .cmd_last(cmd_last),
        .cmd_done(cmd_done),
        .cmd_error(cmd_error)
    );

    initial begin
        clk = 1'b0;
        forever #2.5 clk = ~clk;
    end

    function [31:0] command_record;
        begin
            command_record = {
                cmd_last,
                cmd_flags,
                cmd_nonce,
                cmd_param,
                cmd_j,
                cmd_i,
                cmd_object,
                cmd_op
            };
        end
    endfunction

    task expected_params(
        input integer set_value,
        output integer expected_k,
        output integer expected_eta1,
        output integer expected_du,
        output integer expected_dv
    );
    begin
        case (set_value)
            0: begin
                expected_k = 2;
                expected_eta1 = 3;
                expected_du = 10;
                expected_dv = 4;
            end
            1: begin
                expected_k = 3;
                expected_eta1 = 2;
                expected_du = 10;
                expected_dv = 4;
            end
            default: begin
                expected_k = 4;
                expected_eta1 = 2;
                expected_du = 11;
                expected_dv = 5;
            end
        endcase
    end
    endtask

    task reset_dut;
    begin
        rst_n = 1'b0;
        start = 1'b0;
        cmd_ready = 1'b0;
        cmd_done = 1'b0;
        cmd_error = 1'b0;
        repeat(5) @(posedge clk);
        #0.5;
        rst_n = 1'b1;
        repeat(2) @(posedge clk);
    end
    endtask

    task run_trace(
        input integer operation_value,
        input integer set_value,
        input integer command_offset,
        input integer expected_count,
        input integer trace_id
    );
        integer trace_index;
        integer cycles;
        integer response_delay;
        integer expected_k;
        integer expected_eta1;
        integer expected_du;
        integer expected_dv;
        reg pending;
        reg take_command;
        reg hold_active;
        reg [31:0] sampled_command;
        reg [31:0] held_command;
    begin
        reset_dut();
        operation = operation_value[1:0];
        parameter_set = set_value[1:0];
        trace_index = 0;
        cycles = 0;
        response_delay = 0;
        pending = 1'b0;
        hold_active = 1'b0;
        held_command = 32'd0;

        @(negedge clk);
        start = 1'b1;
        @(posedge clk);
        #0.5;
        @(negedge clk);
        start = 1'b0;

        expected_params(
            set_value,
            expected_k,
            expected_eta1,
            expected_du,
            expected_dv
        );

        if ((k != expected_k) || (eta1 != expected_eta1) ||
            (eta2 != 2) || (du != expected_du) || (dv != expected_dv)) begin
            $display("FAIL: Trace=%0d parameter outputs k=%0d eta1=%0d eta2=%0d du=%0d dv=%0d",
                trace_id, k, eta1, eta2, du, dv);
            error_count = error_count + 1;
        end

        while (!done && (cycles < TIMEOUT_CYCLES)) begin
            cmd_done = 1'b0;
            cmd_error = 1'b0;

            if (pending) begin
                cmd_ready = 1'b0;
                if (response_delay == 0)
                    cmd_done = 1'b1;
            end else begin
                cmd_ready = ((cycles % 4) != 1);
            end

            #0.5;
            take_command = cmd_valid && cmd_ready;
            sampled_command = command_record();

            if (cmd_valid && !cmd_ready) begin
                if (hold_active && (sampled_command !== held_command)) begin
                    $display("FAIL: Trace=%0d command changed while stalled", trace_id);
                    error_count = error_count + 1;
                end
                hold_active = 1'b1;
                held_command = sampled_command;
            end else if (take_command) begin
                hold_active = 1'b0;
            end

            @(posedge clk);
            #0.5;

            if (cmd_done) begin
                pending = 1'b0;
            end else if (pending && (response_delay > 0)) begin
                response_delay = response_delay - 1;
            end

            if (take_command) begin
                if (trace_index >= expected_count) begin
                    $display("FAIL: Trace=%0d emitted extra command", trace_id);
                    error_count = error_count + 1;
                end else if (sampled_command !==
                             command_vectors[command_offset + trace_index]) begin
                    $display("FAIL: Trace=%0d command=%0d expected=%08x got=%08x",
                        trace_id, trace_index,
                        command_vectors[command_offset + trace_index],
                        sampled_command);
                    error_count = error_count + 1;
                end

                pending = 1'b1;
                response_delay = trace_index % 3;
                trace_index = trace_index + 1;
            end

            cycles = cycles + 1;
            if (!done)
                @(negedge clk);
        end

        cmd_ready = 1'b0;
        cmd_done = 1'b0;

        if (!done || error || (trace_index != expected_count)) begin
            $display("FAIL: Trace=%0d timeout=%0d error=%0d commands=%0d/%0d",
                trace_id, !done, error, trace_index, expected_count);
            error_count = error_count + 1;
        end

        @(posedge clk);
        #0.5;
        if (done || busy || cmd_valid) begin
            $display("FAIL: Trace=%0d did not return cleanly to idle", trace_id);
            error_count = error_count + 1;
        end
    end
    endtask

    task test_invalid_request(
        input [1:0] operation_value,
        input [1:0] set_value
    );
    begin
        reset_dut();
        operation = operation_value;
        parameter_set = set_value;

        @(negedge clk);
        start = 1'b1;
        @(posedge clk);
        #0.5;
        start = 1'b0;

        if (!done || !error || cmd_valid) begin
            $display("FAIL: Invalid request operation=%0d set=%0d", operation_value, set_value);
            error_count = error_count + 1;
        end
    end
    endtask

    task test_dispatch_error;
    begin
        reset_dut();
        operation = 2'd0;
        parameter_set = 2'd0;

        @(negedge clk);
        start = 1'b1;
        @(posedge clk);
        #0.5;
        @(negedge clk);
        start = 1'b0;
        cmd_ready = 1'b1;

        wait(cmd_valid);
        @(posedge clk);
        #0.5;
        cmd_ready = 1'b0;

        @(negedge clk);
        cmd_error = 1'b1;
        @(posedge clk);
        #0.5;
        cmd_error = 1'b0;

        if (!done || !error) begin
            $display("FAIL: Dispatcher error did not abort sequence");
            error_count = error_count + 1;
        end
    end
    endtask

    string tb_file, tb_dir, tv_dir;

    function automatic string dirname(input string path);
        int slash_pos = -1;

        for (int j = 0; j < path.len(); j++)
            if ((path[j] == 8'h2F) || (path[j] == 8'h5C)) slash_pos = j;

        if (slash_pos > 0)
            return path.substr(0, slash_pos - 1);
        else if (slash_pos == 0)
            return path.substr(0, 0);
        else
            return ".";
    endfunction

    initial begin
        tb_file = `__FILE__;
        tb_dir = dirname(tb_file);
        tv_dir = {tb_dir, "/../vector"};

        error_count = 0;
        rst_n = 1'b0;
        operation = 2'd0;
        parameter_set = 2'd0;
        start = 1'b0;
        cmd_ready = 1'b0;
        cmd_done = 1'b0;
        cmd_error = 1'b0;

        spec_fd = $fopen({tv_dir, "/sequencer_tv_spec.txt"}, "r");
        if (spec_fd == 0) begin
            $display("ERROR: Cannot open %s/sequencer_tv_spec.txt", tv_dir);
            $finish;
        end

        void'($fgets(line_buffer, spec_fd));
        void'($sscanf(line_buffer, "case_count=%d", case_count));
        void'($fgets(line_buffer, spec_fd));
        void'($sscanf(line_buffer, "command_count=%d", command_count));
        $fclose(spec_fd);

        if ((case_count > MAX_CASES) || (command_count > MAX_COMMANDS)) begin
            $display("ERROR: Generated vectors exceed testbench buffers");
            $finish;
        end

        $readmemh({tv_dir, "/sequencer_cases.mem"}, case_vectors);
        $readmemh({tv_dir, "/sequencer_cmd.mem"}, command_vectors);

        for (case_idx = 0; case_idx < case_count; case_idx = case_idx + 1) begin
            run_trace(
                case_vectors[case_idx][1:0],
                case_vectors[case_idx][3:2],
                case_vectors[case_idx][15:4],
                case_vectors[case_idx][27:16],
                case_idx
            );
        end

        test_invalid_request(2'b11, 2'b00);
        test_invalid_request(2'b00, 2'b11);
        test_dispatch_error();

        $display(">>> ML-KEM SEQUENCER PASSED: %0d TRACES, %0d COMMANDS (%0d ERRORS)",
            case_count, command_count, error_count);
        $finish;
    end

endmodule
