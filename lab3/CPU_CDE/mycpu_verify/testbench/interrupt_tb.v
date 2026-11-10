`timescale 1ns/1ps

`ifndef IRQ_INDEX
`define IRQ_INDEX 0
`endif

module interrupt_tb;
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
integer instruction_index;
integer data_index;
integer byte_index;
integer trap_events;
integer eret_events;
integer data_word_zero_writes;
integer interrupted_pc_writebacks;
integer assertion_count;

localparam integer IRQ_INDEX_VALUE = `IRQ_INDEX;
localparam integer IP_BIT = IRQ_INDEX_VALUE + 2;
localparam [15:0] STATUS_IP_MASK = 16'h0001 << (IP_BIT + 8);

localparam [31:0] INTERRUPTED_PC = 32'hbfc0_001c;
localparam [31:0] RESUME_PC      = 32'hbfc0_0020;
localparam [31:0] EXCEPTION_VECTOR=32'hbfc0_0380;

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

// Small synchronous SRAM models preserve the CPU's request/response timing.
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
        if (dut.trap_commit) begin
            assertion_count = assertion_count + 1;
            if (dut.trap_code !== 5'd0 || dut.trap_pc !== INTERRUPTED_PC || dut.trap_bd !== 1'b0)
                $fatal(1, "INTERRUPT_TB_FAIL wrong trap code/PC/BD code=%0d pc=%08x bd=%b",
                       dut.trap_code, dut.trap_pc, dut.trap_bd);
            assertion_count = assertion_count + 1;
            if (!dut.cp0_reg.cause_ip[IP_BIT] || !dut.cp0_reg.status_ie ||
                !dut.cp0_reg.status_im[IP_BIT])
                $fatal(1, "INTERRUPT_TB_FAIL interrupt request was not enabled and visible at commit");
            assertion_count = assertion_count + 1;
            if (inst_sram_addr !== EXCEPTION_VECTOR)
                $fatal(1, "INTERRUPT_TB_FAIL wrong exception vector %08x", inst_sram_addr);
            assertion_count = assertion_count + 1;
            if (data_sram_en || (|data_sram_wen))
                $fatal(1, "INTERRUPT_TB_FAIL younger data side effect during interrupt commit");
            trap_events = trap_events + 1;
            hw_int <= 6'b0;
        end

        if (dut.eret_commit) begin
            assertion_count = assertion_count + 1;
            if (dut.cp0_epc !== RESUME_PC)
                $fatal(1, "INTERRUPT_TB_FAIL ERET target expected %08x got %08x",
                       RESUME_PC, dut.cp0_epc);
            eret_events = eret_events + 1;
        end

        if ((debug_wb_pc == INTERRUPTED_PC) && (|debug_wb_rf_wen))
            interrupted_pc_writebacks = interrupted_pc_writebacks + 1;

        if (data_sram_en && (|data_sram_wen) && (data_sram_addr == 32'b0))
            data_word_zero_writes = data_word_zero_writes + 1;
    end
end

initial begin
    clk = 1'b0;
    resetn = 1'b0;
    if (IRQ_INDEX_VALUE < 0 || IRQ_INDEX_VALUE > 5)
        $fatal(1, "INTERRUPT_TB_FAIL IRQ_INDEX must be 0..5, got %0d", IRQ_INDEX_VALUE);
    // Hold one external source high from reset. IE is enabled first with the
    // selected IM bit clear, then the bit is enabled to test the full path.
    hw_int = 6'b000001 << IRQ_INDEX_VALUE;
    inst_sram_rdata = 32'b0;
    data_sram_rdata = 32'b0;
    trap_events = 0;
    eret_events = 0;
    data_word_zero_writes = 0;
    interrupted_pc_writebacks = 0;
    assertion_count = 0;

    for (instruction_index = 0; instruction_index < 256; instruction_index = instruction_index + 1)
        instruction_memory[instruction_index] = 32'h0000_0000;
    for (data_index = 0; data_index < 256; data_index = data_index + 1)
        data_memory[data_index] = 32'b0;

    data_memory[0] = 32'hdead_beef;

    // Main program. Status enables IE while masking IP2, then unmasks IP2.
    // The instruction at INTERRUPTED_PC must be discarded; its younger store
    // must also be flushed and execute exactly once after ERET returns.
    instruction_memory[8'h00] = 32'h2411_0055; // addiu s1,zero,0x55
    instruction_memory[8'h01] = 32'h3c08_0040; // lui   t0,0x0040
    instruction_memory[8'h02] = 32'h3508_0001; // ori   t0,t0,IE (IM[2]=0)
    instruction_memory[8'h03] = 32'h4088_6000; // mtc0  t0,Status
    if (IRQ_INDEX_VALUE == 5)
        instruction_memory[8'h04] = 32'h4080_5800; // mtc0 zero,Compare: isolate external IP7 from reset TI
    else
        instruction_memory[8'h04] = 32'h2412_0001; // addiu s2,zero,1
    instruction_memory[8'h05] = 32'h3508_0000 | STATUS_IP_MASK; // enable selected IM bit
    instruction_memory[8'h06] = 32'h4088_6000; // mtc0  t0,Status
    instruction_memory[8'h07] = 32'h2410_0001; // addiu s0,zero,1 (interrupted)
    instruction_memory[8'h08] = 32'hac11_0000; // sw    s1,0(zero)
    instruction_memory[8'h09] = 32'h2413_0066; // addiu s3,zero,0x66
    instruction_memory[8'h0a] = 32'h0bf0_000a; // j     0xbfc00028
    instruction_memory[8'h0b] = 32'h0000_0000; // nop (delay slot)

    // General exception handler: skip the interrupted instruction and return.
    instruction_memory[8'he0] = 32'h401a_7000; // mfc0  k0,EPC
    instruction_memory[8'he1] = 32'h275a_0004; // addiu k0,k0,4
    instruction_memory[8'he2] = 32'h409a_7000; // mtc0  k0,EPC
    instruction_memory[8'he3] = 32'h4200_0018; // eret

    repeat (4) @(posedge clk);
    @(negedge clk);
    resetn = 1'b1;

    wait (dut.cp0_reg.status_ie === 1'b1 && dut.cp0_reg.status_im[IP_BIT] === 1'b0);
    repeat (2) @(posedge clk);
    #1;
    assertion_count = assertion_count + 1;
    if (trap_events != 0 || dut.interrupt_pending ||
        !dut.cp0_reg.cause_ip[IP_BIT] || dut.cp0_reg.status_im[IP_BIT])
        $fatal(1, "INTERRUPT_TB_FAIL IP%0d should be visible but masked before Status.IM[%0d]",
               IP_BIT, IP_BIT);

    wait (trap_events == 1);
    wait (eret_events == 1);
    wait (data_word_zero_writes == 1 && data_memory[0] === 32'h0000_0055);
    wait (dut.id_stage.u_regfile.rf[19] === 32'h0000_0066);
    repeat (8) @(posedge clk);
    #1;

    assertion_count = assertion_count + 1;
    if (trap_events != 1 || eret_events != 1)
        $fatal(1, "INTERRUPT_TB_FAIL interrupt/ERET event counts trap=%0d eret=%0d",
               trap_events, eret_events);
    assertion_count = assertion_count + 1;
    if (data_word_zero_writes != 1 || data_memory[0] !== 32'h0000_0055)
        $fatal(1, "INTERRUPT_TB_FAIL younger store was duplicated or lost writes=%0d value=%08x",
               data_word_zero_writes, data_memory[0]);
    assertion_count = assertion_count + 1;
    if (interrupted_pc_writebacks != 0)
        $fatal(1, "INTERRUPT_TB_FAIL interrupted instruction wrote a GPR");
    assertion_count = assertion_count + 1;
    if (dut.cp0_reg.status_exl || dut.interrupt_pending || hw_int !== 6'b0)
        $fatal(1, "INTERRUPT_TB_FAIL EXL/request did not clear after handler and ERET");

    $display("CASE_NAME=external_irq_ip%0d", IP_BIT);
    $display("ASSERTIONS_PASS=%0d", assertion_count);
    $display("TRAPS_OBSERVED=%0d", trap_events);
    $display("STATUS=PASS");
    $display("INTERRUPT_TB_PASS ip=%0d traps=%0d erets=%0d stores=%0d masked_then_taken=1",
             IP_BIT, trap_events, eret_events, data_word_zero_writes);
    $finish;
end

initial begin
    #100000;
    $fatal(1, "INTERRUPT_TB_FAIL watchdog timeout trap=%0d eret=%0d stores=%0d",
           trap_events, eret_events, data_word_zero_writes);
end

endmodule
