`timescale 1ns/1ps

module cp0_decode_tb;
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
integer trap_events;
integer eret_events;
integer legal_status_writes;
integer assertion_count;

localparam [31:0] BAD_MFC0_LOW  = 32'hbfc0_0010;
localparam [31:0] BAD_MFC0_HIGH = 32'hbfc0_0014;
localparam [31:0] BAD_MTC0_LOW  = 32'hbfc0_0018;
localparam [31:0] BAD_MTC0_HIGH = 32'hbfc0_001c;

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

// Synchronous SRAM models use the same one-cycle response as interrupt_tb.
always @(posedge clk) begin
    if (inst_sram_en)
        inst_sram_rdata <= instruction_memory[inst_sram_addr[9:2]];

    if (data_sram_en) begin
        data_sram_rdata <= data_memory[data_sram_addr[9:2]];
        for (i = 0; i < 4; i = i + 1) begin
            if (data_sram_wen[i])
                data_memory[data_sram_addr[9:2]][i*8 +: 8] <=
                    data_sram_wdata[i*8 +: 8];
        end
    end
end

always @(posedge clk) begin
    if (resetn) begin
        if (dut.trap_commit) begin
            assertion_count = assertion_count + 1;
            if (dut.trap_code !== 5'd10 || dut.trap_bd !== 1'b0)
                $fatal(1, "CP0_DECODE_TB_FAIL expected RI with BD=0 code=%0d bd=%b",
                       dut.trap_code, dut.trap_bd);
            assertion_count = assertion_count + 1;
            case (trap_events)
                0: if (dut.trap_pc !== BAD_MFC0_LOW)
                       $fatal(1, "CP0_DECODE_TB_FAIL low-reserved MFC0 EPC source %08x", dut.trap_pc);
                1: if (dut.trap_pc !== BAD_MFC0_HIGH)
                       $fatal(1, "CP0_DECODE_TB_FAIL high-reserved MFC0 EPC source %08x", dut.trap_pc);
                2: if (dut.trap_pc !== BAD_MTC0_LOW)
                       $fatal(1, "CP0_DECODE_TB_FAIL low-reserved MTC0 EPC source %08x", dut.trap_pc);
                3: if (dut.trap_pc !== BAD_MTC0_HIGH)
                       $fatal(1, "CP0_DECODE_TB_FAIL high-reserved MTC0 EPC source %08x", dut.trap_pc);
                default: $fatal(1, "CP0_DECODE_TB_FAIL unexpected extra trap at %08x", dut.trap_pc);
            endcase
            assertion_count = assertion_count + 1;
            if (dut.cp0_we || data_sram_en || (|data_sram_wen))
                $fatal(1, "CP0_DECODE_TB_FAIL invalid instruction had a CP0 or SRAM side effect");
            assertion_count = assertion_count + 1;
            if (dut.cp0_reg.status_ie !== 1'b0 || dut.cp0_reg.status_im !== 8'h01)
                $fatal(1, "CP0_DECODE_TB_FAIL Status changed before RI commit IE=%b IM=%02x",
                       dut.cp0_reg.status_ie, dut.cp0_reg.status_im);
            trap_events = trap_events + 1;
        end

        if (dut.eret_commit) begin
            assertion_count = assertion_count + 1;
            if (dut.cp0_reg.cause_exc_code !== 5'd10)
                $fatal(1, "CP0_DECODE_TB_FAIL CP0 Cause.ExcCode expected RI got %0d",
                       dut.cp0_reg.cause_exc_code);
            case (eret_events)
                0: if (dut.cp0_epc !== BAD_MFC0_LOW + 32'd4)
                       $fatal(1, "CP0_DECODE_TB_FAIL first ERET target %08x", dut.cp0_epc);
                1: if (dut.cp0_epc !== BAD_MFC0_HIGH + 32'd4)
                       $fatal(1, "CP0_DECODE_TB_FAIL second ERET target %08x", dut.cp0_epc);
                2: if (dut.cp0_epc !== BAD_MTC0_LOW + 32'd4)
                       $fatal(1, "CP0_DECODE_TB_FAIL third ERET target %08x", dut.cp0_epc);
                3: if (dut.cp0_epc !== BAD_MTC0_HIGH + 32'd4)
                       $fatal(1, "CP0_DECODE_TB_FAIL fourth ERET target %08x", dut.cp0_epc);
                default: $fatal(1, "CP0_DECODE_TB_FAIL unexpected extra ERET");
            endcase
            eret_events = eret_events + 1;
        end

        if ((debug_wb_pc == BAD_MFC0_LOW || debug_wb_pc == BAD_MFC0_HIGH) &&
            (|debug_wb_rf_wen))
            $fatal(1, "CP0_DECODE_TB_FAIL reserved MFC0 wrote GPR at PC %08x", debug_wb_pc);

        if (dut.cp0_we && dut.mem_stage.ms_pc == BAD_MTC0_LOW)
            $fatal(1, "CP0_DECODE_TB_FAIL low-reserved MTC0 wrote CP0");
        if (dut.cp0_we && dut.mem_stage.ms_pc == BAD_MTC0_HIGH)
            $fatal(1, "CP0_DECODE_TB_FAIL high-reserved MTC0 wrote CP0");
        if (dut.cp0_we && dut.cp0_waddr == 8'h60 && dut.mem_stage.ms_pc == 32'hbfc0_0008)
            legal_status_writes = legal_status_writes + 1;
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
    legal_status_writes = 0;
    assertion_count = 0;

    for (i = 0; i < 256; i = i + 1) begin
        instruction_memory[i] = 32'b0;
        data_memory[i] = 32'b0;
    end

    instruction_memory[8'h00] = 32'h2408_1234; // addiu t0,zero,0x1234 (MFC0 sentinel)
    instruction_memory[8'h01] = 32'h240a_0100; // addiu t2,zero,0x100 (Status.IM[0])
    instruction_memory[8'h02] = 32'h408a_6000; // mtc0 t2,Status (legal)
    instruction_memory[8'h03] = 32'h4009_6000; // mfc0 t1,Status (legal)
    instruction_memory[8'h04] = 32'h4008_6008; // MFC0 with reserved [5:3] bit
    instruction_memory[8'h05] = 32'h400b_6040; // MFC0 with reserved [10:6] bit
    instruction_memory[8'h06] = 32'h4088_6008; // MTC0 with reserved [5:3] bit
    instruction_memory[8'h07] = 32'h4088_6040; // MTC0 with reserved [10:6] bit
    instruction_memory[8'h08] = 32'h2410_0055; // addiu s0,zero,0x55 (completion marker)
    instruction_memory[8'h09] = 32'h0bf0_0009; // j 0xbfc00024
    instruction_memory[8'h0a] = 32'h0000_0000; // nop

    // Each RI handler advances EPC by one instruction and returns.
    instruction_memory[8'he0] = 32'h401a_7000; // mfc0 k0,EPC
    instruction_memory[8'he1] = 32'h275a_0004; // addiu k0,k0,4
    instruction_memory[8'he2] = 32'h409a_7000; // mtc0 k0,EPC
    instruction_memory[8'he3] = 32'h4200_0018; // eret

    repeat (4) @(posedge clk);
    @(negedge clk);
    resetn = 1'b1;

    wait (dut.id_stage.u_regfile.rf[16] === 32'h0000_0055);
    wait (trap_events == 4 && eret_events == 4);
    repeat (10) @(posedge clk);
    #1;

    assertion_count = assertion_count + 1;
    if (trap_events != 4 || eret_events != 4)
        $fatal(1, "CP0_DECODE_TB_FAIL trap/ERET counts trap=%0d eret=%0d", trap_events, eret_events);
    assertion_count = assertion_count + 1;
    if (legal_status_writes != 1 || dut.id_stage.u_regfile.rf[9] !== 32'h0000_0100)
        $fatal(1, "CP0_DECODE_TB_FAIL legal MTC0/MFC0 behavior writes=%0d read=%08x",
               legal_status_writes, dut.id_stage.u_regfile.rf[9]);
    assertion_count = assertion_count + 1;
    if (dut.id_stage.u_regfile.rf[8] !== 32'h0000_1234)
        $fatal(1, "CP0_DECODE_TB_FAIL invalid MFC0 changed its destination GPR");
    assertion_count = assertion_count + 1;
    if (dut.cp0_reg.status_ie !== 1'b0 || dut.cp0_reg.status_im !== 8'h01 ||
        dut.cp0_reg.status_exl !== 1'b0)
        $fatal(1, "CP0_DECODE_TB_FAIL invalid MTC0 changed Status or ERET left EXL set");

    $display("CASE_NAME=cp0_reserved_decode");
    $display("ASSERTIONS_PASS=%0d", assertion_count);
    $display("TRAPS_OBSERVED=%0d", trap_events);
    $display("ERETS_OBSERVED=%0d", eret_events);
    $display("STATUS=PASS");
    $display("CP0_DECODE_TB_PASS legal_mfc0=1 legal_mtc0=1 invalid_mfc0=2 invalid_mtc0=2");
    $finish;
end

initial begin
    #100000;
    $fatal(1, "CP0_DECODE_TB_FAIL watchdog timeout trap=%0d eret=%0d marker=%08x",
           trap_events, eret_events, dut.id_stage.u_regfile.rf[16]);
end

endmodule
