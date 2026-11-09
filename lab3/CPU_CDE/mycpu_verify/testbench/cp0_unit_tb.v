`timescale 1ns/1ps

module cp0_unit_tb;
reg clk;
reg reset;
reg [5:0] hw_int;
reg cp0_we;
reg [7:0] cp0_waddr;
reg [31:0] cp0_wdata;
reg [7:0] cp0_raddr;
wire [31:0] cp0_rdata;
reg exc_commit;
reg [4:0] exc_code;
reg [31:0] exc_pc;
reg exc_bd;
reg [31:0] exc_bad_vaddr;
reg eret_commit;
wire [31:0] cp0_epc;
wire cp0_bev;
wire interrupt_pending;

integer assertion_count;
integer traps_observed;
integer timer_wait;
integer irq_index;
reg [31:0] observed;
reg [31:0] count_before;
reg [31:0] compare_target;
reg timer_seen;

always #5 clk = ~clk;

cp0_reg uut(
    .clk(clk),
    .reset(reset),
    .hw_int(hw_int),
    .cp0_we(cp0_we),
    .cp0_waddr(cp0_waddr),
    .cp0_wdata(cp0_wdata),
    .cp0_raddr(cp0_raddr),
    .cp0_rdata(cp0_rdata),
    .exc_commit(exc_commit),
    .exc_code(exc_code),
    .exc_pc(exc_pc),
    .exc_bd(exc_bd),
    .exc_bad_vaddr(exc_bad_vaddr),
    .eret_commit(eret_commit),
    .cp0_epc(cp0_epc),
    .cp0_bev(cp0_bev),
    .interrupt_pending(interrupt_pending)
);

task check32;
    input [31:0] actual;
    input [31:0] expected;
    input [8*80-1:0] label;
    begin
        assertion_count = assertion_count + 1;
        if (actual !== expected)
            $fatal(1, "CP0_TB_FAIL %0s expected=%08x actual=%08x", label, expected, actual);
    end
endtask

task check1;
    input actual;
    input expected;
    input [8*80-1:0] label;
    begin
        assertion_count = assertion_count + 1;
        if (actual !== expected)
            $fatal(1, "CP0_TB_FAIL %0s expected=%b actual=%b", label, expected, actual);
    end
endtask

task read_reg;
    input [7:0] address;
    output [31:0] value;
    begin
        cp0_raddr = address;
        #1;
        value = cp0_rdata;
    end
endtask

task write_reg;
    input [7:0] address;
    input [31:0] value;
    begin
        @(negedge clk);
        cp0_we = 1'b1;
        cp0_waddr = address;
        cp0_wdata = value;
        @(posedge clk);
        #1;
        @(negedge clk);
        cp0_we = 1'b0;
    end
endtask

task commit_exception;
    input [4:0] code;
    input [31:0] pc;
    input delay_slot;
    input [31:0] bad_address;
    begin
        @(negedge clk);
        exc_commit = 1'b1;
        exc_code = code;
        exc_pc = pc;
        exc_bd = delay_slot;
        exc_bad_vaddr = bad_address;
        @(posedge clk);
        #1;
        exc_commit = 1'b0;
        traps_observed = traps_observed + 1;
        @(negedge clk);
    end
endtask

task commit_eret;
    begin
        @(negedge clk);
        eret_commit = 1'b1;
        @(posedge clk);
        #1;
        eret_commit = 1'b0;
        @(negedge clk);
    end
endtask

initial begin
    clk = 1'b0;
    reset = 1'b1;
    hw_int = 6'b0;
    cp0_we = 1'b0;
    cp0_waddr = 8'b0;
    cp0_wdata = 32'b0;
    cp0_raddr = 8'b0;
    exc_commit = 1'b0;
    exc_code = 5'b0;
    exc_pc = 32'b0;
    exc_bd = 1'b0;
    exc_bad_vaddr = 32'b0;
    eret_commit = 1'b0;
    assertion_count = 0;
    traps_observed = 0;
    timer_wait = 0;
    irq_index = 0;
    observed = 32'b0;
    count_before = 32'b0;
    compare_target = 32'b0;
    timer_seen = 1'b0;

    repeat (3) @(posedge clk);
    #1;
    read_reg(8'h60, observed);
    check32(observed, 32'h0040_0000, "reset Status.BEV and writable fields");
    read_reg(8'h48, observed);
    check32(observed, 32'b0, "reset Count");
    read_reg(8'h58, observed);
    check32(observed, 32'b0, "reset Compare");
    read_reg(8'h68, observed);
    check32(observed, 32'h0000_007c, "reset Cause.ExcCode reference value");
    read_reg(8'h40, observed);
    check32(observed, 32'b0, "reset BadVAddr");
    check32(cp0_epc, 32'b0, "reset EPC");
    check1(cp0_bev, 1'b1, "BEV output after reset");

    @(negedge clk);
    reset = 1'b0;
    @(posedge clk);
    #1;
    read_reg(8'h68, observed);
    check1(observed[30], 1'b1, "Count==Compare latches TI after reset release");
    check1(interrupt_pending, 1'b0, "reset IE/IM mask the timer request");

    // Compare writes clear the pending timer request; Count advances once per
    // two CPU clocks, as in the CPU132 reference implementation.
    write_reg(8'h58, 32'hffff_ffff);
    read_reg(8'h68, observed);
    check1(observed[30], 1'b0, "Compare write clears TI");
    write_reg(8'h48, 32'h0000_0100);
    read_reg(8'h48, count_before);
    repeat (2) @(posedge clk);
    #1;
    read_reg(8'h48, observed);
    check32(observed, count_before + 32'd1, "Count increments once in two clocks");

    // Program Compare a few Count ticks ahead and prove TI and IP7 latch.
    read_reg(8'h48, count_before);
    compare_target = count_before + 32'd3;
    write_reg(8'h58, compare_target);
    timer_seen = 1'b0;
    for (timer_wait = 0; timer_wait < 12; timer_wait = timer_wait + 1) begin
        @(posedge clk);
        #1;
        if (uut.timer_pending)
            timer_seen = 1'b1;
    end
    check1(timer_seen, 1'b1, "Count/Compare match raises timer pending");
    read_reg(8'h68, observed);
    check1(observed[30], 1'b1, "Cause.TI reports timer pending");
    check1(observed[15], 1'b1, "timer pending is visible as Cause.IP7");
    write_reg(8'h60, 32'h0000_8001);
    check1(interrupt_pending, 1'b1, "enabled timer request reaches interrupt output");
    read_reg(8'h48, count_before);
    write_reg(8'h58, count_before + 32'd10);
    read_reg(8'h68, observed);
    check1(observed[30], 1'b0, "Compare rewrite clears timer pending");
    check1(observed[15], 1'b0, "cleared timer releases IP7 when hw_int[5]=0");
    check1(interrupt_pending, 1'b0, "cleared timer no longer interrupts");
    write_reg(8'h58, 32'hffff_ffff);

    // Status implements only IE, EXL, IM and BEV. Cause writes update only
    // software IP0/IP1; architectural exception fields are protected.
    write_reg(8'h60, 32'hffff_ffff);
    read_reg(8'h60, observed);
    check32(observed, 32'h0040_ff03, "Status writable mask");
    check1(cp0_bev, 1'b1, "BEV output follows Status write");
    write_reg(8'h60, 32'h0040_0000);
    commit_exception(5'd8, 32'h8000_1238, 1'b1, 32'b0);
    read_reg(8'h68, observed);
    check1(observed[31], 1'b1, "delay-slot exception sets Cause.BD");
    check32({27'b0, observed[6:2]}, 32'd8, "syscall exception code");
    check32(cp0_epc, 32'h8000_1234, "delay-slot EPC points to branch");
    read_reg(8'h60, observed);
    check1(observed[1], 1'b1, "exception sets Status.EXL");

    // A nested address exception updates BadVAddr/ExcCode while preserving
    // the original EPC and BD until ERET.
    commit_exception(5'd4, 32'h8000_2000, 1'b0, 32'h0000_1003);
    read_reg(8'h68, observed);
    check1(observed[31], 1'b1, "nested exception preserves Cause.BD");
    check32({27'b0, observed[6:2]}, 32'd4, "nested exception updates ExcCode");
    check32(cp0_epc, 32'h8000_1234, "nested exception preserves EPC");
    read_reg(8'h40, observed);
    check32(observed, 32'h0000_1003, "AdEL records original BadVAddr");

    write_reg(8'h70, 32'h8000_4000);
    check32(cp0_epc, 32'h8000_4000, "MTC0 EPC write");
    commit_eret;
    read_reg(8'h60, observed);
    check1(observed[1], 1'b0, "ERET clears Status.EXL");
    check32(cp0_epc, 32'h8000_4000, "ERET preserves return EPC");

    write_reg(8'h68, 32'h0000_0000);
    write_reg(8'h68, 32'h0000_0100);
    write_reg(8'h60, 32'h0000_0101);
    check1(interrupt_pending, 1'b1, "software IP0 enters when IE and IM0 are set");
    write_reg(8'h60, 32'h0000_0201);
    check1(interrupt_pending, 1'b0, "software IP0 is blocked by IM0 mask");
    write_reg(8'h68, 32'h0000_0200);
    check1(interrupt_pending, 1'b1, "software IP1 enters when IE and IM1 are set");
    write_reg(8'h68, 32'h0000_0000);
    check1(interrupt_pending, 1'b0, "clearing software IP requests releases interrupt");
    read_reg(8'h68, observed);
    check1(observed[31], 1'b1, "MTC0 Cause preserves BD");
    check32({27'b0, observed[6:2]}, 32'd4, "MTC0 Cause preserves ExcCode");

    // Verify hw_int[0..5] maps to IP2..IP7 and that IM masks each source.
    for (irq_index = 0; irq_index < 6; irq_index = irq_index + 1) begin
        write_reg(8'h60, 32'h0000_0001 | (32'h1 << (10 + irq_index)));
        hw_int = 6'b000001 << irq_index;
        #1;
        read_reg(8'h68, observed);
        check1(observed[10 + irq_index], 1'b1, "external interrupt IP mapping");
        check1(interrupt_pending, 1'b1, "enabled external interrupt reaches output");
        write_reg(8'h60, 32'h0000_0001);
        check1(interrupt_pending, 1'b0, "IM masks external interrupt source");
        hw_int = 6'b0;
        #1;
    end

    // IP7 is the OR of timer and external source 5; Compare clears only TI.
    write_reg(8'h60, 32'h0000_8001);
    hw_int = 6'b100000;
    write_reg(8'h58, 32'hffff_ffff);
    read_reg(8'h68, observed);
    check1(observed[30], 1'b0, "external IP7 does not set timer TI");
    check1(observed[15], 1'b1, "external IP7 remains after Compare clears TI");
    check1(interrupt_pending, 1'b1, "external IP7 remains interrupting after Compare write");
    hw_int = 6'b0;
    #1;
    check1(interrupt_pending, 1'b0, "deasserted external IP7 releases interrupt");

    // Unsupported selects/registers read as zero, and unsupported writes are
    // ignored rather than aliasing a supported CP0 register.
    write_reg(8'h61, 32'hffff_ffff);
    read_reg(8'h61, observed);
    check32(observed, 32'b0, "unsupported Status select reads zero");
    read_reg(8'h08, observed);
    check32(observed, 32'b0, "unsupported CP0 register reads zero");
    read_reg(8'h60, observed);
    check32(observed, 32'h0000_8001, "unsupported select write does not alias Status");

    $display("CASE_NAME=cp0_reg_unit");
    $display("ASSERTIONS_PASS=%0d", assertion_count);
    $display("TRAPS_OBSERVED=%0d", traps_observed);
    $display("STATUS=PASS");
    $finish;
end

initial begin
    #100000;
    $fatal(1, "CP0_TB_FAIL timeout");
end

endmodule
