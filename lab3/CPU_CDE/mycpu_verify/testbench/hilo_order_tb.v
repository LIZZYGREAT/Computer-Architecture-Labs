`timescale 1ns/1ps

module hilo_order_tb;
reg clk;
reg resetn;
reg [5:0] hw_int;

wire inst_sram_en;
wire [3:0] inst_sram_wen;
wire [31:0] inst_sram_addr;
wire [31:0] inst_sram_wdata;
reg [31:0] inst_sram_rdata;
wire data_sram_en;
wire [3:0] data_sram_wen;
wire [31:0] data_sram_addr;
wire [31:0] data_sram_wdata;
reg [31:0] data_sram_rdata;
wire [31:0] debug_wb_pc;
wire [3:0] debug_wb_rf_wen;
wire [4:0] debug_wb_rf_wnum;
wire [31:0] debug_wb_rf_wdata;

reg [31:0] instruction_memory [0:255];
reg [31:0] data_memory [0:255];
integer i;
integer byte_index;
integer div1_start_count;
integer div2_start_count;
integer trap_events;
integer eret_events;
integer irq_younger_write_count;
integer assertion_count;
reg irq_injected;

localparam [31:0] SYSCALL_PC       = 32'hbfc0_0018;
localparam [31:0] DIV1_PC          = 32'hbfc0_001c;
localparam [31:0] DIV2_PC          = 32'hbfc0_0038;
localparam [31:0] IRQ_YOUNGER_PC   = 32'hbfc0_003c;
localparam [31:0] IRQ_RESUME_PC    = 32'hbfc0_0040;

always #5 clk = ~clk;

mycpu_top #(.PIPELINE_FORWARDING(1'b1)) dut (
    .clk(clk),
    .resetn(resetn),
    .hw_int(hw_int),
    .inst_sram_en(inst_sram_en),
    .inst_sram_wen(inst_sram_wen),
    .inst_sram_addr(inst_sram_addr),
    .inst_sram_wdata(inst_sram_wdata),
    .inst_sram_rdata(inst_sram_rdata),
    .data_sram_en(data_sram_en),
    .data_sram_wen(data_sram_wen),
    .data_sram_addr(data_sram_addr),
    .data_sram_wdata(data_sram_wdata),
    .data_sram_rdata(data_sram_rdata),
    .debug_wb_pc(debug_wb_pc),
    .debug_wb_rf_wen(debug_wb_rf_wen),
    .debug_wb_rf_wnum(debug_wb_rf_wnum),
    .debug_wb_rf_wdata(debug_wb_rf_wdata)
);

always @(posedge clk) begin
    if (inst_sram_en)
        inst_sram_rdata <= instruction_memory[inst_sram_addr[9:2]];

    if (data_sram_en) begin
        data_sram_rdata <= data_memory[data_sram_addr[9:2]];
        for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
            if (data_sram_wen[byte_index])
                data_memory[data_sram_addr[9:2]][byte_index*8 +: 8] <=
                    data_sram_wdata[byte_index*8 +: 8];
        end
    end
end

always @(posedge clk) begin
    if (resetn) begin
        if (dut.exe_stage.es_hilo_start) begin
            if (dut.exe_stage.es_pc == DIV1_PC) begin
                if (eret_events != 1)
                    $fatal(1, "HILO_ORDER_TB_FAIL younger DIV1 started before returning from syscall");
                div1_start_count = div1_start_count + 1;
            end
            else if (dut.exe_stage.es_pc == DIV2_PC) begin
                div2_start_count = div2_start_count + 1;
                if (!irq_injected) begin
                    irq_injected = 1'b1;
                    hw_int <= 6'b000001;
                end
            end
            else begin
                $fatal(1, "HILO_ORDER_TB_FAIL unexpected HI/LO start at PC %08x", dut.exe_stage.es_pc);
            end
        end

        if (debug_wb_pc == IRQ_YOUNGER_PC && (|debug_wb_rf_wen)) begin
            irq_younger_write_count = irq_younger_write_count + 1;
            $fatal(1, "HILO_ORDER_TB_FAIL younger instruction wrote back on interrupt");
        end

        if (dut.trap_commit) begin
            assertion_count = assertion_count + 1;
            if (trap_events == 0) begin
                if (dut.trap_code !== 5'd8 || dut.trap_pc !== SYSCALL_PC || dut.trap_bd !== 1'b0)
                    $fatal(1, "HILO_ORDER_TB_FAIL expected older syscall code=%0d pc=%08x bd=%b",
                           dut.trap_code, dut.trap_pc, dut.trap_bd);
                assertion_count = assertion_count + 1;
                if (div1_start_count != 0 || div2_start_count != 0 ||
                    dut.exe_stage.es_hilo_start !== 1'b0 ||
                    dut.exe_stage.u_hilo_unit.hi_reg !== 32'h0000_1111 ||
                    dut.exe_stage.u_hilo_unit.lo_reg !== 32'h0000_2222)
                    $fatal(1, "HILO_ORDER_TB_FAIL syscall did not kill younger DIV or preserve HI/LO");
            end
            else if (trap_events == 1) begin
                if (dut.trap_code !== 5'd0 || dut.trap_pc !== IRQ_YOUNGER_PC || dut.trap_bd !== 1'b0)
                    $fatal(1, "HILO_ORDER_TB_FAIL expected external interrupt code=%0d pc=%08x bd=%b",
                           dut.trap_code, dut.trap_pc, dut.trap_bd);
                assertion_count = assertion_count + 1;
                if (!dut.cp0_reg.cause_ip[2] || !dut.cp0_reg.status_ie ||
                    !dut.cp0_reg.status_im[2] || div1_start_count != 1 || div2_start_count != 1 ||
                    dut.exe_stage.u_hilo_unit.busy !== 1'b0 ||
                    dut.exe_stage.u_hilo_unit.done !== 1'b0 ||
                    dut.exe_stage.u_hilo_unit.hi_reg !== 32'd2 ||
                    dut.exe_stage.u_hilo_unit.lo_reg !== 32'd14)
                    $fatal(1, "HILO_ORDER_TB_FAIL DIV did not retire exactly once before external interrupt");
                hw_int <= 6'b0;
            end
            else begin
                $fatal(1, "HILO_ORDER_TB_FAIL unexpected extra trap code=%0d pc=%08x",
                       dut.trap_code, dut.trap_pc);
            end
            trap_events = trap_events + 1;
        end

        if (dut.eret_commit) begin
            assertion_count = assertion_count + 1;
            if (eret_events == 0 && dut.cp0_epc !== DIV1_PC)
                $fatal(1, "HILO_ORDER_TB_FAIL syscall handler target expected DIV1 %08x got %08x",
                       DIV1_PC, dut.cp0_epc);
            if (eret_events == 1 && dut.cp0_epc !== IRQ_RESUME_PC)
                $fatal(1, "HILO_ORDER_TB_FAIL interrupt handler target expected MFLO %08x got %08x",
                       IRQ_RESUME_PC, dut.cp0_epc);
            eret_events = eret_events + 1;
        end
    end
end

initial begin
    clk = 1'b0;
    resetn = 1'b0;
    hw_int = 6'b0;
    inst_sram_rdata = 32'b0;
    data_sram_rdata = 32'b0;
    div1_start_count = 0;
    div2_start_count = 0;
    trap_events = 0;
    eret_events = 0;
    irq_younger_write_count = 0;
    assertion_count = 0;
    irq_injected = 1'b0;

    for (i = 0; i < 256; i = i + 1) begin
        instruction_memory[i] = 32'b0;
        data_memory[i] = 32'b0;
    end

    instruction_memory[8'h00] = 32'h2408_1111; // addiu t0,zero,0x1111
    instruction_memory[8'h01] = 32'h0100_0011; // mthi t0
    instruction_memory[8'h02] = 32'h2409_2222; // addiu t1,zero,0x2222
    instruction_memory[8'h03] = 32'h0120_0013; // mtlo t1
    instruction_memory[8'h04] = 32'h240a_0064; // addiu t2,zero,100
    instruction_memory[8'h05] = 32'h240b_0007; // addiu t3,zero,7
    instruction_memory[8'h06] = 32'h0000_000c; // syscall: older synchronous exception
    instruction_memory[8'h07] = 32'h014b_001a; // DIV1 t2,t3, younger than syscall
    instruction_memory[8'h08] = 32'h2410_0066; // addiu s0,zero,0x66
    instruction_memory[8'h09] = 32'h240c_0064; // addiu t4,zero,100
    instruction_memory[8'h0a] = 32'h240d_0007; // addiu t5,zero,7
    instruction_memory[8'h0b] = 32'h3c0e_0040; // lui t6,0x0040 (keep BEV set)
    instruction_memory[8'h0c] = 32'h35ce_0401; // ori t6,t6,IE|IM[2]
    instruction_memory[8'h0d] = 32'h408e_6000; // mtc0 t6,Status
    instruction_memory[8'h0e] = 32'h018d_001a; // DIV2 t4,t5
    instruction_memory[8'h0f] = 32'h2414_0044; // addiu s4,zero,0x44 (interrupt target)
    instruction_memory[8'h10] = 32'h0000_8812; // mflo s1
    instruction_memory[8'h11] = 32'h0000_9010; // mfhi s2
    instruction_memory[8'h12] = 32'h2413_0077; // addiu s3,zero,0x77
    instruction_memory[8'h13] = 32'h0bf0_0013; // j 0xbfc0004c
    instruction_memory[8'h14] = 32'h0000_0000; // nop

    // Both exceptions use BEV=1, so share this handler.
    instruction_memory[8'he0] = 32'h401a_7000; // mfc0 k0,EPC
    instruction_memory[8'he1] = 32'h275a_0004; // addiu k0,k0,4
    instruction_memory[8'he2] = 32'h409a_7000; // mtc0 k0,EPC
    instruction_memory[8'he3] = 32'h4200_0018; // eret

    repeat (4) @(posedge clk);
    @(negedge clk);
    resetn = 1'b1;

    wait (dut.id_stage.u_regfile.rf[19] === 32'h0000_0077);
    wait (trap_events == 2 && eret_events == 2);
    repeat (10) @(posedge clk);
    #1;

    assertion_count = assertion_count + 1;
    if (div1_start_count != 1 || div2_start_count != 1 || irq_injected !== 1'b1 ||
        irq_younger_write_count != 0 || hw_int !== 6'b0)
        $fatal(1, "HILO_ORDER_TB_FAIL final operation/request counts DIV1=%0d DIV2=%0d irq=%b younger_wb=%0d hw_int=%b",
               div1_start_count, div2_start_count, irq_injected, irq_younger_write_count, hw_int);
    assertion_count = assertion_count + 1;
    if (dut.exe_stage.u_hilo_unit.hi_reg !== 32'd2 ||
        dut.exe_stage.u_hilo_unit.lo_reg !== 32'd14 ||
        dut.id_stage.u_regfile.rf[17] !== 32'd14 ||
        dut.id_stage.u_regfile.rf[18] !== 32'd2)
        $fatal(1, "HILO_ORDER_TB_FAIL final HI/LO or MFHI/MFLO result mismatch");

    $display("CASE_NAME=cpu_hilo_exception_interrupt_order");
    $display("ASSERTIONS_PASS=%0d", assertion_count);
    $display("TRAPS_OBSERVED=%0d", trap_events);
    $display("ERETS_OBSERVED=%0d", eret_events);
    $display("STATUS=PASS");
    $display("HILO_ORDER_TB_PASS older_syscall_killed_younger_div=1 div_busy_irq_ordered=1 div_starts=2 hi=00000002 lo=0000000e");
    $finish;
end

initial begin
    #100000;
    $fatal(1, "HILO_ORDER_TB_FAIL watchdog timeout traps=%0d erets=%0d div1=%0d div2=%0d irq=%b",
           trap_events, eret_events, div1_start_count, div2_start_count, irq_injected);
end

endmodule
