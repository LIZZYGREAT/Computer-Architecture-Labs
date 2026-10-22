`timescale 1ns/1ps

module hilo_unit_tb;
reg clk;
reg resetn;
reg start;
reg is_mult;
reg is_multu;
reg is_div;
reg is_divu;
reg [31:0] operand_a;
reg [31:0] operand_b;
reg consume_done;
reg write_hi_en;
reg write_lo_en;
reg [31:0] write_data;
wire busy;
wire done;
wire [31:0] hi_value;
wire [31:0] lo_value;

integer mult_accept_count;
integer div_accept_count;
integer done_commit_count;
integer commits_before_cancel;
reg done_seen;

always #5 clk = ~clk;

hilo_unit uut(
    .clk(clk),
    .resetn(resetn),
    .start(start),
    .is_mult(is_mult),
    .is_multu(is_multu),
    .is_div(is_div),
    .is_divu(is_divu),
    .consume_done(consume_done),
    .operand_a(operand_a),
    .operand_b(operand_b),
    .write_hi_en(write_hi_en),
    .write_lo_en(write_lo_en),
    .write_data(write_data),
    .busy(busy),
    .done(done),
    .hi_value(hi_value),
    .lo_value(lo_value)
);

always @(posedge clk) begin
    if (uut.accept_mult) begin
        mult_accept_count = mult_accept_count + 1;
    end
    if (uut.accept_div) begin
        div_accept_count = div_accept_count + 1;
    end
end

always @(posedge clk) begin
    if (!resetn) begin
        done_seen <= 1'b0;
    end
    else begin
        if (done && !done_seen) begin
            done_commit_count = done_commit_count + 1;
        end
        done_seen <= done;
    end
end

task check_result;
    input [31:0] expected_hi;
    input [31:0] expected_lo;
    input integer expected_mult_accepts;
    input integer expected_div_accepts;
    begin
        wait(done === 1'b1);
        #1;
        if (hi_value !== expected_hi || lo_value !== expected_lo) begin
            $fatal(1, "HILO_TB_FAIL result expected HI=%08x LO=%08x got HI=%08x LO=%08x",
                   expected_hi, expected_lo, hi_value, lo_value);
        end
        repeat (3) begin
            @(posedge clk);
            #1;
            if (!done || busy || hi_value !== expected_hi || lo_value !== expected_lo) begin
                $fatal(1, "HILO_TB_FAIL completion was not held until consume");
            end
        end
        if (mult_accept_count != expected_mult_accepts || div_accept_count != expected_div_accepts) begin
            $fatal(1, "HILO_TB_FAIL duplicate request mult=%0d div=%0d",
                   mult_accept_count, div_accept_count);
        end
        if (done_commit_count != expected_mult_accepts + expected_div_accepts) begin
            $fatal(1, "HILO_TB_FAIL completion count expected=%0d got=%0d",
                   expected_mult_accepts + expected_div_accepts, done_commit_count);
        end
        @(negedge clk);
        consume_done = 1'b1;
        @(posedge clk);
        #1;
        if (done) begin
            $fatal(1, "HILO_TB_FAIL done did not clear after consume");
        end
        @(negedge clk);
        consume_done = 1'b0;
        is_mult = 1'b0;
        is_multu = 1'b0;
        is_div = 1'b0;
        is_divu = 1'b0;
    end
endtask

task launch_operation;
    input mult;
    input multu;
    input div_op;
    input divu;
    input [31:0] value_a;
    input [31:0] value_b;
    begin
        @(negedge clk);
        is_mult = mult;
        is_multu = multu;
        is_div = div_op;
        is_divu = divu;
        operand_a = value_a;
        operand_b = value_b;
        start = 1'b1;
        wait(busy === 1'b1);
        @(negedge clk);
        start = 1'b0;
    end
endtask

initial begin
    clk = 1'b0;
    resetn = 1'b0;
    start = 1'b0;
    is_mult = 1'b0;
    is_multu = 1'b0;
    is_div = 1'b0;
    is_divu = 1'b0;
    operand_a = 32'b0;
    operand_b = 32'b0;
    consume_done = 1'b0;
    write_hi_en = 1'b0;
    write_lo_en = 1'b0;
    write_data = 32'b0;
    mult_accept_count = 0;
    div_accept_count = 0;
    done_commit_count = 0;
    commits_before_cancel = 0;
    done_seen = 1'b0;

    repeat (5) @(posedge clk);
    @(negedge clk);
    resetn = 1'b1;

    launch_operation(1'b1, 1'b0, 1'b0, 1'b0, 32'hfffffff9, 32'h00000006);
    check_result(32'hffffffff, 32'hffffffd6, 1, 0);

    launch_operation(1'b0, 1'b1, 1'b0, 1'b0, 32'hffffffff, 32'hffffffff);
    check_result(32'hfffffffe, 32'h00000001, 2, 0);

    launch_operation(1'b1, 1'b0, 1'b0, 1'b0, 32'h80000000, 32'h00000000);
    check_result(32'h00000000, 32'h00000000, 3, 0);

    launch_operation(1'b0, 1'b0, 1'b1, 1'b0, 32'hffffffe9, 32'h00000005);
    check_result(32'hfffffffd, 32'hfffffffc, 3, 1);

    launch_operation(1'b0, 1'b0, 1'b1, 1'b0, 32'h00000017, 32'hfffffffb);
    check_result(32'h00000003, 32'hfffffffc, 3, 2);

    launch_operation(1'b0, 1'b0, 1'b0, 1'b1, 32'hfffffff5, 32'h00000005);
    check_result(32'h00000000, 32'h33333331, 3, 3);

    @(negedge clk);
    write_data = 32'h12345678;
    write_hi_en = 1'b1;
    @(posedge clk);
    @(negedge clk);
    write_hi_en = 1'b0;
    write_data = 32'h89abcdef;
    write_lo_en = 1'b1;
    @(posedge clk);
    @(negedge clk);
    write_lo_en = 1'b0;
    #1;
    if (hi_value !== 32'h12345678 || lo_value !== 32'h89abcdef) begin
        $fatal(1, "HILO_TB_FAIL MTHI/MTLO values HI=%08x LO=%08x", hi_value, lo_value);
    end

    // Reset while a divide is active: discard the in-flight result and HI/LO.
    commits_before_cancel = done_commit_count;
    launch_operation(1'b0, 1'b0, 1'b0, 1'b1, 32'h80000000, 32'h00000003);
    @(negedge clk);
    resetn = 1'b0;
    repeat (5) @(posedge clk);
    #1;
    if (busy || done || hi_value !== 32'b0 || lo_value !== 32'b0) begin
        $fatal(1, "HILO_TB_FAIL reset did not cancel operation and clear state");
    end
    if (done_commit_count != commits_before_cancel) begin
        $fatal(1, "HILO_TB_FAIL reset-cancelled operation committed unexpectedly");
    end
    @(negedge clk);
    resetn = 1'b1;
    repeat (3) @(posedge clk);

    if (done_commit_count != mult_accept_count + div_accept_count - 1) begin
        $fatal(1, "HILO_TB_FAIL cancelled request changed accept/commit accounting");
    end
    $display("HILO_UNIT_TB_PASS mult_accepts=%0d div_accepts=%0d commits=%0d",
             mult_accept_count, div_accept_count, done_commit_count);
    $finish;
end

initial begin
    #1000000;
    $fatal(1, "HILO_TB_FAIL watchdog timeout");
end
endmodule
