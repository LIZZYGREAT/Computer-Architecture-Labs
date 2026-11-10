`timescale 1ns/1ps

module software_timer_irq_tb;
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
integer trap_events;
integer eret_events;
integer assertion_count;
reg timer_masked_seen;
reg timer_case_started;

localparam [31:0] IP0_INTERRUPT_PC = 32'hbfc0_0034;
localparam [31:0] IP1_INTERRUPT_PC = 32'hbfc0_0054;
localparam [31:0] TIMER_INTERRUPT_PC=32'hbfc0_00e8;

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
        if (dut.cp0_we && dut.cp0_waddr == 8'h58 && dut.cp0_wdata == 32'd12)
            timer_case_started = 1'b1;
        if (timer_case_started && dut.cp0_reg.compare == 32'd12 &&
            dut.cp0_reg.timer_pending && !dut.cp0_reg.status_im[7] && !timer_masked_seen)
            timer_masked_seen = 1'b1;

        if (dut.trap_commit) begin
            assertion_count = assertion_count + 1;
            if (dut.trap_code !== 5'd0 || dut.trap_bd !== 1'b0)
                $fatal(1, "SOFTWARE_TIMER_IRQ_TB_FAIL expected interrupt code=0 BD=0 got code=%0d BD=%b",
                       dut.trap_code, dut.trap_bd);
            assertion_count = assertion_count + 1;
            case (trap_events)
                0: begin
                    if (dut.trap_pc !== IP0_INTERRUPT_PC || !dut.cp0_reg.cause_ip[0] ||
                        dut.cp0_reg.cause_ip[1] || dut.cp0_reg.cause_ip[7] ||
                        !dut.cp0_reg.status_im[0])
                        $fatal(1, "SOFTWARE_TIMER_IRQ_TB_FAIL IP0 trap source/PC mismatch pc=%08x ip=%02x",
                               dut.trap_pc, dut.cp0_reg.cause_ip);
                end
                1: begin
                    if (dut.trap_pc !== IP1_INTERRUPT_PC || dut.cp0_reg.cause_ip[0] ||
                        !dut.cp0_reg.cause_ip[1] || dut.cp0_reg.cause_ip[7] ||
                        !dut.cp0_reg.status_im[1])
                        $fatal(1, "SOFTWARE_TIMER_IRQ_TB_FAIL IP1 trap source/PC mismatch pc=%08x ip=%02x",
                               dut.trap_pc, dut.cp0_reg.cause_ip);
                end
                2: begin
                    if (dut.trap_pc !== TIMER_INTERRUPT_PC || !timer_masked_seen ||
                        !dut.cp0_reg.timer_pending || !dut.cp0_reg.cause_ip[7] ||
                        dut.cp0_reg.hw_int !== 6'b0 || !dut.cp0_reg.status_im[7])
                        $fatal(1, "SOFTWARE_TIMER_IRQ_TB_FAIL timer IP7 trap not isolated/armed pc=%08x",
                               dut.trap_pc);
                end
                default: $fatal(1, "SOFTWARE_TIMER_IRQ_TB_FAIL unexpected extra trap at %08x", dut.trap_pc);
            endcase
            trap_events = trap_events + 1;
        end

        if (dut.eret_commit) begin
            assertion_count = assertion_count + 1;
            case (eret_events)
                0: if (dut.cp0_epc !== IP0_INTERRUPT_PC)
                       $fatal(1, "SOFTWARE_TIMER_IRQ_TB_FAIL IP0 ERET target %08x", dut.cp0_epc);
                1: if (dut.cp0_epc !== IP1_INTERRUPT_PC)
                       $fatal(1, "SOFTWARE_TIMER_IRQ_TB_FAIL IP1 ERET target %08x", dut.cp0_epc);
                2: if (dut.cp0_epc !== TIMER_INTERRUPT_PC)
                       $fatal(1, "SOFTWARE_TIMER_IRQ_TB_FAIL timer ERET target %08x", dut.cp0_epc);
                default: $fatal(1, "SOFTWARE_TIMER_IRQ_TB_FAIL unexpected extra ERET");
            endcase
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
    trap_events = 0;
    eret_events = 0;
    assertion_count = 0;
    timer_masked_seen = 1'b0;
    timer_case_started = 1'b0;

    for (i = 0; i < 256; i = i + 1) begin
        instruction_memory[i] = 32'b0;
        data_memory[i] = 32'b0;
    end

    // Keep Count nonzero while Compare=0 so reset-time Count==Compare cannot
    // create a false timer request during the software interrupt cases.
    instruction_memory[8'h00] = 32'h240c_0001; // addiu t4,zero,1
    instruction_memory[8'h01] = 32'h408c_4800; // mtc0 t4,Count
    instruction_memory[8'h02] = 32'h4080_5800; // mtc0 zero,Compare
    instruction_memory[8'h03] = 32'h3c08_0040; // lui t0,0x0040 (BEV=1)
    instruction_memory[8'h04] = 32'h3508_0001; // ori t0,t0,IE; IM0/1/7 masked
    instruction_memory[8'h05] = 32'h4088_6000; // mtc0 t0,Status
    instruction_memory[8'h06] = 32'h2409_0100; // addiu t1,zero,IP0
    instruction_memory[8'h07] = 32'h4089_6800; // mtc0 t1,Cause
    instruction_memory[8'h08] = 32'h0000_0000; // masked IP0 observation window
    instruction_memory[8'h09] = 32'h0000_0000;
    instruction_memory[8'h0a] = 32'h0000_0000;
    instruction_memory[8'h0b] = 32'h3508_0100; // enable IM0
    instruction_memory[8'h0c] = 32'h4088_6000; // mtc0 t0,Status
    instruction_memory[8'h0d] = 32'h0000_0000; // IP0 interrupt point
    instruction_memory[8'h0e] = 32'h240b_0200; // addiu t3,zero,IP1
    instruction_memory[8'h0f] = 32'h408b_6800; // mtc0 t3,Cause
    instruction_memory[8'h10] = 32'h0000_0000; // masked IP1 observation window
    instruction_memory[8'h11] = 32'h0000_0000;
    instruction_memory[8'h12] = 32'h0000_0000;
    instruction_memory[8'h13] = 32'h3508_0200; // enable IM1, retain IM0
    instruction_memory[8'h14] = 32'h4088_6000; // mtc0 t0,Status
    instruction_memory[8'h15] = 32'h0000_0000; // IP1 interrupt point

    instruction_memory[8'h16] = 32'h240c_0001; // addiu t4,zero,1
    instruction_memory[8'h17] = 32'h408c_4800; // mtc0 t4,Count
    instruction_memory[8'h18] = 32'h240d_000c; // addiu t5,zero,12
    instruction_memory[8'h19] = 32'h408d_5800; // mtc0 t5,Compare
    for (i = 8'h1a; i < 8'h38; i = i + 1)
        instruction_memory[i] = 32'h0000_0000; // wait masked until TI/IP7 is visible
    instruction_memory[8'h38] = 32'h3508_8000; // enable IM7
    instruction_memory[8'h39] = 32'h4088_6000; // mtc0 t0,Status
    instruction_memory[8'h3a] = 32'h0000_0000; // timer interrupt point
    instruction_memory[8'h3b] = 32'h2410_0055; // addiu s0,zero,0x55
    instruction_memory[8'h3c] = 32'h0bf0_003c; // j 0xbfc000f0
    instruction_memory[8'h3d] = 32'h0000_0000; // nop

    // Handler clears the software request and TI before returning to the
    // interrupted NOP. hw_int stays zero throughout the timer case.
    instruction_memory[8'he0] = 32'h4080_6800; // mtc0 zero,Cause
    instruction_memory[8'he1] = 32'h4080_5800; // mtc0 zero,Compare
    instruction_memory[8'he2] = 32'h4200_0018; // eret

    repeat (4) @(posedge clk);
    @(negedge clk);
    resetn = 1'b1;

    wait (dut.cp0_reg.cause_ip[0] && dut.cp0_reg.status_ie && !dut.cp0_reg.status_im[0]);
    repeat (2) @(posedge clk);
    #1;
    assertion_count = assertion_count + 1;
    if (trap_events != 0 || dut.interrupt_pending || dut.cp0_reg.cause_ip[0] !== 1'b1)
        $fatal(1, "SOFTWARE_TIMER_IRQ_TB_FAIL masked IP0 did not remain pending without trap");

    wait (dut.cp0_reg.cause_ip[1] && dut.cp0_reg.status_ie && !dut.cp0_reg.status_im[1]);
    repeat (2) @(posedge clk);
    #1;
    assertion_count = assertion_count + 1;
    if (trap_events != 1 || dut.interrupt_pending || dut.cp0_reg.cause_ip[0] ||
        dut.cp0_reg.cause_ip[1] !== 1'b1)
        $fatal(1, "SOFTWARE_TIMER_IRQ_TB_FAIL masked IP1 or IP0 clear behavior mismatch");

    wait (timer_masked_seen);
    repeat (2) @(posedge clk);
    #1;
    assertion_count = assertion_count + 1;
    if (trap_events != 2 || dut.interrupt_pending || !dut.cp0_reg.cause_ip[7] ||
        dut.cp0_reg.hw_int !== 6'b0)
        $fatal(1, "SOFTWARE_TIMER_IRQ_TB_FAIL timer IP7 was not visible while masked and externally isolated");

    wait (dut.id_stage.u_regfile.rf[16] === 32'h0000_0055);
    wait (trap_events == 3 && eret_events == 3);
    repeat (8) @(posedge clk);
    #1;

    assertion_count = assertion_count + 1;
    if (trap_events != 3 || eret_events != 3 || dut.cp0_reg.cause_sw_ip !== 2'b0 ||
        dut.cp0_reg.timer_pending !== 1'b0 || dut.cp0_reg.cause_ip[7] !== 1'b0 ||
        dut.cp0_reg.status_exl !== 1'b0 || dut.interrupt_pending || hw_int !== 6'b0)
        $fatal(1, "SOFTWARE_TIMER_IRQ_TB_FAIL requests did not clear after their handlers and ERET");

    $display("CASE_NAME=software_ip0_ip1_timer_ip7");
    $display("ASSERTIONS_PASS=%0d", assertion_count);
    $display("TRAPS_OBSERVED=%0d", trap_events);
    $display("ERETS_OBSERVED=%0d", eret_events);
    $display("STATUS=PASS");
    $display("SOFTWARE_TIMER_IRQ_TB_PASS ip0=1 ip1=1 timer_ip7=1 masked_then_taken=1 external_ip7=0");
    $finish;
end

initial begin
    #100000;
    $fatal(1, "SOFTWARE_TIMER_IRQ_TB_FAIL watchdog timeout traps=%0d erets=%0d masked_timer=%b",
           trap_events, eret_events, timer_masked_seen);
end

endmodule
