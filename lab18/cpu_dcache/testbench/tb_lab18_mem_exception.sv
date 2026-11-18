`timescale 1ns/1ps
`include "mycpu.h"

module tb_lab18_mem_exception;
    reg clk = 1'b0;
    reg reset = 1'b1;
    always #5 clk = ~clk;

    reg ws_allowin = 1'b1;
    wire ms_allowin;
    reg es_to_ms_valid = 1'b0;
    reg [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus = {`ES_TO_MS_BUS_WD{1'b0}};
    reg [31:0] cp0_rdata = 32'b0;
    wire cp0_we;
    wire [7:0] cp0_waddr;
    wire [31:0] cp0_wdata;
    wire [7:0] cp0_raddr;
    wire cp0_serial_busy;
    wire tlb_commit;
    wire [`TLB_OP_WD-1:0] tlb_op_commit;
    wire trap_commit;
    wire [4:0] trap_code;
    wire [31:0] trap_pc;
    wire trap_bd;
    wire [31:0] trap_bad_vaddr;
    wire eret_commit;
    wire data_sram_req;
    wire data_sram_wr;
    wire [1:0] data_sram_size;
    wire [3:0] data_sram_wstrb;
    wire [31:0] data_sram_addr;
    wire [31:0] data_sram_wdata;
    reg data_sram_addr_ok = 1'b0;
    reg data_sram_data_ok = 1'b0;
    reg [31:0] data_sram_rdata = 32'b0;
    wire ms_to_ws_valid;
    wire [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus;
    wire [38:0] ms_producer_bus;
    integer store_accepts = 0;
    integer store_completions = 0;
    integer timeout;

    mem_stage dut(
        .clk(clk), .reset(reset), .ws_allowin(ws_allowin), .ms_allowin(ms_allowin),
        .es_to_ms_valid(es_to_ms_valid), .es_to_ms_bus(es_to_ms_bus),
        .cp0_rdata(cp0_rdata), .cp0_we(cp0_we), .cp0_waddr(cp0_waddr),
        .cp0_wdata(cp0_wdata), .cp0_raddr(cp0_raddr),
        .cp0_serial_busy(cp0_serial_busy), .tlb_commit(tlb_commit),
        .tlb_op_commit(tlb_op_commit), .trap_commit(trap_commit),
        .trap_code(trap_code), .trap_pc(trap_pc), .trap_bd(trap_bd),
        .trap_bad_vaddr(trap_bad_vaddr), .eret_commit(eret_commit),
        .data_sram_req(data_sram_req), .data_sram_wr(data_sram_wr),
        .data_sram_size(data_sram_size), .data_sram_wstrb(data_sram_wstrb),
        .data_sram_addr(data_sram_addr), .data_sram_wdata(data_sram_wdata),
        .data_sram_addr_ok(data_sram_addr_ok),
        .data_sram_data_ok(data_sram_data_ok), .data_sram_rdata(data_sram_rdata),
        .ms_to_ws_valid(ms_to_ws_valid), .ms_to_ws_bus(ms_to_ws_bus),
        .ms_producer_bus(ms_producer_bus)
    );

    always @(posedge clk) begin
        if (!reset) begin
            if (data_sram_req && data_sram_addr_ok)
                store_accepts = store_accepts + 1;
            if (data_sram_data_ok)
                store_completions = store_completions + 1;
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk); reset = 1'b0;

        // Exception-bearing store in MEM must trap without issuing a memory request.
        es_to_ms_bus = {`ES_TO_MS_BUS_WD{1'b0}};
        es_to_ms_bus[152] = 1'b1; // ms_exception_valid
        es_to_ms_bus[109] = 1'b1; // MEM_OP_SW at bus bit 102+7
        es_to_ms_bus[95:64] = 32'h0000_1040;
        es_to_ms_bus[63:32] = 32'hdead_beef;
        es_to_ms_bus[31:0] = 32'h8000_1234;
        es_to_ms_valid = 1'b1;
        @(posedge clk); #1; es_to_ms_valid = 1'b0;
        #1;
        if (!trap_commit || data_sram_req || data_sram_wr || store_accepts != 0)
            $fatal(1, "MEM_EXCEPTION_FAIL=store_issued_on_exception trap=%b req=%b accepted=%0d",
                   trap_commit, data_sram_req, store_accepts);
        $display("D09_EXCEPTION_PASS trap_no_store=1 pc=%08x", trap_pc);
        @(posedge clk); #1;

        // A valid committed store holds its complete request under backpressure,
        // is accepted once, and retires after one completion response.
        @(negedge clk);
        es_to_ms_bus = {`ES_TO_MS_BUS_WD{1'b0}};
        es_to_ms_bus[109] = 1'b1;
        es_to_ms_bus[95:64] = 32'h0000_2084;
        es_to_ms_bus[63:32] = 32'hcafe_babe;
        es_to_ms_bus[31:0] = 32'h8000_1238;
        es_to_ms_valid = 1'b1;
        @(posedge clk); #1; es_to_ms_valid = 1'b0;
        timeout = 0;
        while (!data_sram_req && timeout < 20) begin @(negedge clk); timeout = timeout + 1; end
        if (!data_sram_req || !data_sram_wr || data_sram_addr !== 32'h0000_2084 ||
            data_sram_wstrb !== 4'b1111 || data_sram_wdata !== 32'hcafe_babe)
            $fatal(1, "MEM_EXCEPTION_FAIL=committed_store_payload");
        repeat (3) begin
            @(negedge clk);
            if (!data_sram_req || data_sram_addr !== 32'h0000_2084 ||
                data_sram_wstrb !== 4'b1111 || data_sram_wdata !== 32'hcafe_babe)
                $fatal(1, "MEM_EXCEPTION_FAIL=request_payload_not_stable");
        end
        @(negedge clk); data_sram_addr_ok = 1'b1;
        @(posedge clk); #1; data_sram_addr_ok = 1'b0;
        if (data_sram_req || store_accepts != 1)
            $fatal(1, "MEM_EXCEPTION_FAIL=store_accept_count req=%b accepted=%0d",
                   data_sram_req, store_accepts);
        @(negedge clk); data_sram_data_ok = 1'b1;
        @(posedge clk); #1; data_sram_data_ok = 1'b0;
        #1;
        if (!ms_to_ws_valid || store_completions != 1)
            $fatal(1, "MEM_EXCEPTION_FAIL=store_completion_count ws=%b completed=%0d",
                   ms_to_ws_valid, store_completions);
        $display("D09_COMMITTED_STORE_PASS accepted=1 completed=1 stable_payload=1");
        $display("D09_MEM_PASS");
        $finish;
    end
endmodule
