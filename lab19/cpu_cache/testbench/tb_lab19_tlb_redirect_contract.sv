`timescale 1ns/1ps
`include "mycpu.h"

module tb_lab19_tlb_redirect_contract;
    localparam [31:0] TEST_VADDR = 32'h0040_2100;
    localparam [19:0] OLD_PFN = 20'habcd_e;
    localparam [19:0] NEW_PFN = 20'h12345;

    reg aclk = 1'b0;
    reg aresetn = 1'b0;
    reg arready = 1'b0;
    reg [3:0] rid = 4'b0;
    reg [31:0] rdata = 32'b0;
    reg [1:0] rresp = 2'b0;
    reg rlast = 1'b0;
    reg rvalid = 1'b0;
    wire [3:0] arid;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire arvalid;
    wire rready;
    integer timeout_count;
    integer beat;

    always #5 aclk = ~aclk;

    mycpu_top dut (
        .aclk(aclk), .aresetn(aresetn), .hw_int(6'b0),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize),
        .arburst(arburst), .arlock(), .arcache(), .arprot(), .arvalid(arvalid),
        .arready(arready), .rid(rid), .rdata(rdata), .rresp(rresp),
        .rlast(rlast), .rvalid(rvalid), .rready(rready),
        .awid(), .awaddr(), .awlen(), .awsize(), .awburst(), .awlock(),
        .awcache(), .awprot(), .awvalid(), .awready(1'b0), .wid(), .wdata(),
        .wstrb(), .wlast(), .wvalid(), .wready(1'b0), .bid(4'b0),
        .bresp(2'b0), .bvalid(1'b0), .bready(), .debug_wb_pc(),
        .debug_wb_rf_wen(), .debug_wb_rf_wnum(), .debug_wb_rf_wdata()
    );

    task accept_ar(input [31:0] expected_addr);
        begin
            timeout_count = 0;
            while (!arvalid && timeout_count < 1000) begin
                @(negedge aclk);
                timeout_count = timeout_count + 1;
            end
            if (!arvalid || araddr !== expected_addr || arlen !== 8'd7 ||
                arid !== 4'h0 || arsize !== 3'b010 || arburst !== 2'b01)
                $fatal(1, "TLB_REPLAY_FAIL=ar_payload expected=%08x actual=%08x len=%0d id=%x",
                       expected_addr, araddr, arlen, arid);
            @(negedge aclk); arready = 1'b1;
            @(posedge aclk);
            if (!arvalid || !arready) $fatal(1, "TLB_REPLAY_FAIL=ar_handshake");
            @(negedge aclk); arready = 1'b0;
        end
    endtask

    task return_old_line;
        begin
            for (beat = 0; beat < 8; beat = beat + 1) begin
                @(negedge aclk);
                rid = 4'h0;
                rresp = 2'b00;
                rdata = 32'hb000_0000 + beat;
                rlast = (beat == 7);
                rvalid = 1'b1;
                @(posedge aclk);
                if (!rready) $fatal(1, "TLB_REPLAY_FAIL=old_rready beat=%0d", beat);
                @(negedge aclk);
                rvalid = 1'b0;
                rlast = 1'b0;
            end
        end
    endtask

    initial begin
        force dut.inst_sram_req = 1'b0;
        repeat (5) @(posedge aclk);
        @(negedge aclk); aresetn = 1'b1;
        timeout_count = 0;
        while (!(dut.u_icache.reset_done && dut.u_dcache.reset_done)) begin
            @(negedge aclk);
            timeout_count = timeout_count + 1;
            if (timeout_count > 1000) $fatal(1, "TLB_REPLAY_FAIL=cache_reset_timeout");
        end

        // Seed a valid, cacheable old mapping for the in-flight instruction.
        dut.u_tlb.entry_valid[0] = 1'b1;
        dut.u_tlb.entry_vpn2[0] = TEST_VADDR[31:13];
        dut.u_tlb.entry_asid[0] = 8'b0;
        dut.u_tlb.entry_g[0] = 1'b1;
        dut.u_tlb.entry_pfn0[0] = OLD_PFN;
        dut.u_tlb.entry_c0[0] = 3'b011;
        dut.u_tlb.entry_d0[0] = 1'b1;
        dut.u_tlb.entry_v0[0] = 1'b1;
        dut.u_tlb.entry_pfn1[0] = OLD_PFN + 20'd1;
        dut.u_tlb.entry_c1[0] = 3'b011;
        dut.u_tlb.entry_d1[0] = 1'b1;
        dut.u_tlb.entry_v1[0] = 1'b1;
        dut.if_stage.request_pc = TEST_VADDR;
        release dut.inst_sram_req;

        accept_ar({OLD_PFN, TEST_VADDR[11:5], 5'b0});
        if (dut.if_stage.state !== 2'd1 || dut.if_stage.request_pc !== TEST_VADDR)
            $fatal(1, "TLB_REPLAY_FAIL=old_fetch_not_outstanding");

        // Model a committed TLBWI while the old physical read is outstanding.
        // The actual TLB write port is exercised on this edge as well.
        @(negedge aclk);
        force dut.tlb_write_enable = 1'b1;
        force dut.ds_current_valid = 1'b1;
        force dut.ds_current_pc = TEST_VADDR;
        force dut.u_tlb.w_index = 4'd0;
        force dut.u_tlb.w_vpn2 = TEST_VADDR[31:13];
        force dut.u_tlb.w_asid = 8'b0;
        force dut.u_tlb.w_g = 1'b1;
        force dut.u_tlb.w_pfn0 = NEW_PFN;
        force dut.u_tlb.w_c0 = 3'b011;
        force dut.u_tlb.w_d0 = 1'b1;
        force dut.u_tlb.w_v0 = 1'b1;
        force dut.u_tlb.w_pfn1 = NEW_PFN + 20'd1;
        force dut.u_tlb.w_c1 = 3'b011;
        force dut.u_tlb.w_d1 = 1'b1;
        force dut.u_tlb.w_v1 = 1'b1;
        @(posedge aclk); #1;
        if (!dut.pipeline_flush || !dut.if_stage.stale_response ||
            dut.if_stage.restart_pc !== TEST_VADDR ||
            dut.u_tlb.entry_pfn0[0] !== NEW_PFN)
            $fatal(1, "TLB_REPLAY_FAIL=commit_flush stale=%0d restart=%08x pfn=%05x",
                   dut.if_stage.stale_response, dut.if_stage.restart_pc,
                   dut.u_tlb.entry_pfn0[0]);
        release dut.tlb_write_enable;
        release dut.ds_current_valid;
        release dut.ds_current_pc;
        release dut.u_tlb.w_index;
        release dut.u_tlb.w_vpn2;
        release dut.u_tlb.w_asid;
        release dut.u_tlb.w_g;
        release dut.u_tlb.w_pfn0;
        release dut.u_tlb.w_c0;
        release dut.u_tlb.w_d0;
        release dut.u_tlb.w_v0;
        release dut.u_tlb.w_pfn1;
        release dut.u_tlb.w_c1;
        release dut.u_tlb.w_d1;
        release dut.u_tlb.w_v1;

        return_old_line();
        timeout_count = 0;
        while (dut.if_stage.stale_response && timeout_count < 100) begin
            @(negedge aclk);
            timeout_count = timeout_count + 1;
        end
        if (dut.if_stage.stale_response || dut.if_stage.response_valid || dut.fs_to_ds_valid)
            $fatal(1, "TLB_REPLAY_FAIL=old_instruction_reached_decode");

        accept_ar({NEW_PFN, TEST_VADDR[11:5], 5'b0});
        if (dut.if_stage.request_pc !== TEST_VADDR ||
            dut.u_tlb.entry_pfn0[0] !== NEW_PFN)
            $fatal(1, "TLB_REPLAY_FAIL=new_mapping_not_used");
        $display("IF_TLB_REPLAY_PASS old_pa=%08x new_pa=%08x old_stale_dropped=1 replay_pc=%08x",
                 {OLD_PFN, TEST_VADDR[11:0]}, {NEW_PFN, TEST_VADDR[11:0]}, TEST_VADDR);
        $display("LAB19_TLB_REPLAY_CROSSCHECK_PASS old_pa=%08x new_pa=%08x force_based=1 old_stale_dropped=1",
                 {OLD_PFN, TEST_VADDR[11:0]}, {NEW_PFN, TEST_VADDR[11:0]});
        $display("LAB19_TLB_REDIRECT_PASS checks=3");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "TLB_REPLAY_FAIL=watchdog_timeout");
    end
endmodule

module lab6_mult33(
    input CLK, input [32:0] A, input [32:0] B, input CE, output reg [65:0] P
);
    always @(posedge CLK) if (CE) P <= A * B;
endmodule

module lab6_div32(
    input aclk, input aresetn,
    input s_axis_divisor_tvalid, output s_axis_divisor_tready,
    input [31:0] s_axis_divisor_tdata,
    input s_axis_dividend_tvalid, output s_axis_dividend_tready,
    input [31:0] s_axis_dividend_tdata,
    output reg m_axis_dout_tvalid, output reg [63:0] m_axis_dout_tdata
);
    assign s_axis_divisor_tready = aresetn;
    assign s_axis_dividend_tready = aresetn;
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_dout_tvalid <= 1'b0;
            m_axis_dout_tdata <= 64'b0;
        end else begin
            m_axis_dout_tvalid <= 1'b0;
            if (s_axis_divisor_tvalid && s_axis_dividend_tvalid) begin
                m_axis_dout_tvalid <= 1'b1;
                if (s_axis_divisor_tdata != 32'b0)
                    m_axis_dout_tdata <= {s_axis_dividend_tdata / s_axis_divisor_tdata,
                                          s_axis_dividend_tdata % s_axis_divisor_tdata};
                else
                    m_axis_dout_tdata <= 64'b0;
            end
        end
    end
endmodule
