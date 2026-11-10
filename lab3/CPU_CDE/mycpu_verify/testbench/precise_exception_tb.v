`timescale 1ns/1ps

module precise_exception_tb;
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
integer store_count;
integer old_store_count;
integer fault_store_count;
integer young_store_count;
integer trap_events;
integer eret_events;
integer assertion_count;

localparam [31:0] OLD_STORE_PC   = 32'hbfc0_0004;
localparam [31:0] FAULT_STORE_PC = 32'hbfc0_0008;
localparam [31:0] YOUNG_STORE_PC = 32'hbfc0_000c;

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

// Synchronous one-cycle SRAM response with byte-lane write support.
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
        if (data_sram_en && data_sram_addr == 32'd2)
            $fatal(1, "PRECISE_EXCEPTION_TB_FAIL misaligned store issued an SRAM request");

        if (data_sram_en && (|data_sram_wen)) begin
            store_count = store_count + 1;
            if (data_sram_wen !== 4'hf || data_sram_wdata !== 32'h0000_0011)
                $fatal(1, "PRECISE_EXCEPTION_TB_FAIL unexpected store lanes/data wen=%x data=%08x",
                       data_sram_wen, data_sram_wdata);
            if (data_sram_addr == 32'd0) begin
                old_store_count = old_store_count + 1;
            end
            else if (data_sram_addr == 32'd4) begin
                if (eret_events != 1)
                    $fatal(1, "PRECISE_EXCEPTION_TB_FAIL young store executed before ERET");
                young_store_count = young_store_count + 1;
            end
            else begin
                $fatal(1, "PRECISE_EXCEPTION_TB_FAIL unexpected SRAM store address %08x", data_sram_addr);
            end
        end

        if (dut.trap_commit) begin
            assertion_count = assertion_count + 1;
            if (dut.trap_code !== 5'd5 || dut.trap_pc !== FAULT_STORE_PC ||
                dut.trap_bd !== 1'b0 || dut.trap_bad_vaddr !== 32'd2)
                $fatal(1, "PRECISE_EXCEPTION_TB_FAIL AdES metadata code=%0d pc=%08x bd=%b bad=%08x",
                       dut.trap_code, dut.trap_pc, dut.trap_bd, dut.trap_bad_vaddr);
            assertion_count = assertion_count + 1;
            if (data_sram_en || (|data_sram_wen))
                $fatal(1, "PRECISE_EXCEPTION_TB_FAIL SRAM active on AdES commit");
            assertion_count = assertion_count + 1;
            if (store_count != 1 || old_store_count != 1 || young_store_count != 0 ||
                data_memory[0] !== 32'h0000_0011)
                $fatal(1, "PRECISE_EXCEPTION_TB_FAIL store scoreboard at trap total=%0d old=%0d young=%0d word0=%08x",
                       store_count, old_store_count, young_store_count, data_memory[0]);
            trap_events = trap_events + 1;
        end

        if (dut.eret_commit) begin
            assertion_count = assertion_count + 1;
            if (dut.cp0_epc !== YOUNG_STORE_PC)
                $fatal(1, "PRECISE_EXCEPTION_TB_FAIL ERET target expected young store %08x got %08x",
                       YOUNG_STORE_PC, dut.cp0_epc);
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
    store_count = 0;
    old_store_count = 0;
    fault_store_count = 0;
    young_store_count = 0;
    trap_events = 0;
    eret_events = 0;
    assertion_count = 0;

    for (i = 0; i < 256; i = i + 1) begin
        instruction_memory[i] = 32'b0;
        data_memory[i] = 32'b0;
    end
    data_memory[0] = 32'hdead_beef;

    instruction_memory[8'h00] = 32'h2410_0011; // addiu s0,zero,0x11
    instruction_memory[8'h01] = 32'hac10_0000; // P0: sw s0,0(zero)
    instruction_memory[8'h02] = 32'hac10_0002; // P1: sw s0,2(zero), AdES
    instruction_memory[8'h03] = 32'hac10_0004; // P2: sw s0,4(zero), younger
    instruction_memory[8'h04] = 32'h2411_0066; // addiu s1,zero,0x66
    instruction_memory[8'h05] = 32'h0bf0_0005; // j 0xbfc00014
    instruction_memory[8'h06] = 32'h0000_0000; // nop

    // The handler skips the faulting SW, so ERET resumes at P2.
    instruction_memory[8'he0] = 32'h401a_7000; // mfc0 k0,EPC
    instruction_memory[8'he1] = 32'h275a_0004; // addiu k0,k0,4
    instruction_memory[8'he2] = 32'h409a_7000; // mtc0 k0,EPC
    instruction_memory[8'he3] = 32'h4200_0018; // eret

    repeat (4) @(posedge clk);
    @(negedge clk);
    resetn = 1'b1;

    wait (dut.id_stage.u_regfile.rf[17] === 32'h0000_0066);
    wait (trap_events == 1 && eret_events == 1 && young_store_count == 1);
    repeat (8) @(posedge clk);
    #1;

    assertion_count = assertion_count + 1;
    if (trap_events != 1 || eret_events != 1 || dut.cp0_reg.cause_exc_code !== 5'd5 ||
        dut.cp0_reg.epc !== YOUNG_STORE_PC || dut.cp0_reg.bad_vaddr !== 32'd2)
        $fatal(1, "PRECISE_EXCEPTION_TB_FAIL CP0 did not retain AdES state EPC=%08x BadVAddr=%08x",
               dut.cp0_reg.epc, dut.cp0_reg.bad_vaddr);
    assertion_count = assertion_count + 1;
    if (store_count != 2 || old_store_count != 1 || fault_store_count != 0 || young_store_count != 1 ||
        data_memory[0] !== 32'h0000_0011 || data_memory[1] !== 32'h0000_0011)
        $fatal(1, "PRECISE_EXCEPTION_TB_FAIL final store scoreboard total=%0d old=%0d fault=%0d young=%0d mem0=%08x mem1=%08x",
               store_count, old_store_count, fault_store_count, young_store_count,
               data_memory[0], data_memory[1]);

    $display("CASE_NAME=precise_store_exception");
    $display("ASSERTIONS_PASS=%0d", assertion_count);
    $display("TRAPS_OBSERVED=%0d", trap_events);
    $display("ERETS_OBSERVED=%0d", eret_events);
    $display("STATUS=PASS");
    $display("PRECISE_EXCEPTION_TB_PASS old_store=1 fault_store=0 young_store=1 total_stores=2 exc_code=5 epc=%08x badvaddr=00000002",
             dut.cp0_reg.epc);
    $finish;
end

initial begin
    #100000;
    $fatal(1, "PRECISE_EXCEPTION_TB_FAIL watchdog timeout trap=%0d eret=%0d stores=%0d",
           trap_events, eret_events, store_count);
end

endmodule
