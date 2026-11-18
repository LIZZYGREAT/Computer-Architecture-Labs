`timescale 1ns/1ps

module tb_lab19_index_maint_contract;
    reg aclk = 1'b0;
    reg aresetn = 1'b0;
    reg arready = 1'b0;
    reg awready = 1'b0;
    reg wready = 1'b0;
    reg bvalid = 1'b0;
    reg [3:0] bid = 4'b0;
    reg [1:0] bresp = 2'b0;
    reg force_maint_req = 1'b0;
    reg [4:0] force_maint_op = 5'b0;
    reg [31:0] force_maint_vaddr = 32'b0;

    wire [3:0] awid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire awvalid;
    wire [3:0] wid;
    wire [31:0] wdata;
    wire [3:0] wstrb;
    wire wlast;
    wire wvalid;
    wire bready;

    integer top_accepts = 0;
    integer icache_accepts = 0;
    integer dcache_accepts = 0;
    integer icache_completions = 0;
    integer dcache_completions = 0;
    integer timeout_count;
    integer beat;
    reg [31:0] expected_word;
    reg [255:0] expected_line;
    reg [255:0] sentinel_line;

    always #5 aclk = ~aclk;

    mycpu_top dut (
        .aclk(aclk), .aresetn(aresetn), .hw_int(6'b0),
        .arready(arready), .rid(4'b0), .rdata(32'b0), .rresp(2'b0),
        .rlast(1'b0), .rvalid(1'b0),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
        .awburst(awburst), .awlock(), .awcache(), .awprot(),
        .awvalid(awvalid), .awready(awready),
        .wid(wid), .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
        .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready)
    );

    task set_maintenance(input [4:0] op, input [31:0] vaddr);
        begin
            force_maint_op = op;
            force_maint_vaddr = vaddr;
            force_maint_req = 1'b1;
            force dut.cache_maint_req = force_maint_req;
            force dut.cache_maint_op = force_maint_op;
            force dut.cache_maint_vaddr = force_maint_vaddr;
            force dut.data_sram_addr = force_maint_vaddr;
        end
    endtask

    task release_maintenance;
        begin
            force_maint_req = 1'b0;
            @(negedge aclk);
            release dut.cache_maint_req;
            release dut.cache_maint_op;
            release dut.cache_maint_vaddr;
            release dut.data_sram_addr;
        end
    endtask

    task check_and_accept(input integer expect_i, input integer expect_d);
        begin
            #1;
            if (dut.data_translation_valid !== 1'b0)
                $fatal(1, "IDX_CONTRACT_FAIL=expected_unmapped_translation op=%02x", force_maint_op);
            if (dut.cache_maint_addr_ok !== 1'b1)
                $fatal(1, "IDX_CONTRACT_FAIL=top_accept_missing op=%02x permit=%0d", force_maint_op,
                       dut.cache_maint_permit);
            if (dut.cache_maint_req !== 1'b1)
                $fatal(1, "IDX_CONTRACT_FAIL=request_not_held op=%02x", force_maint_op);
            if (expect_i && (dut.u_icache.maint_req !== 1'b1 || dut.u_dcache.maint_req !== 1'b0))
                $fatal(1, "IDX_CONTRACT_FAIL=icache_route_mismatch op=%02x", force_maint_op);
            if (expect_d && (dut.u_dcache.maint_req !== 1'b1 || dut.u_icache.maint_req !== 1'b0))
                $fatal(1, "IDX_CONTRACT_FAIL=dcache_route_mismatch op=%02x", force_maint_op);
            @(posedge aclk); #1;
            top_accepts = top_accepts + 1;
            if (expect_i) icache_accepts = icache_accepts + 1;
            if (expect_d) dcache_accepts = dcache_accepts + 1;
            if (expect_i && dut.icache_maint_done) icache_completions = icache_completions + 1;
            if (expect_d && dut.dcache_maint_done) dcache_completions = dcache_completions + 1;
        end
    endtask

    initial begin
        force dut.inst_sram_req = 1'b0;
        force dut.data_sram_req = 1'b0;
        repeat (5) @(posedge aclk);
        aresetn = 1'b1;
        timeout_count = 0;
        while (!(dut.u_icache.reset_done && dut.u_dcache.reset_done)) begin
            @(negedge aclk);
            timeout_count = timeout_count + 1;
            if (timeout_count > 1000) $fatal(1, "IDX_CONTRACT_FAIL=cache_reset_timeout");
        end

        // IndexInv at an unmapped VA is accepted by the top and ICache once.
        set_maintenance(5'h00, 32'h0040_06a0);
        dut.u_icache.valid_way0[7'h35] = 1'b1;
        check_and_accept(1, 0);
        if (dut.u_icache.valid_way0[7'h35] !== 1'b0 ||
            top_accepts != 1 || icache_accepts != 1 || dcache_accepts != 0 ||
            icache_completions != 1)
            $fatal(1, "IDX_CONTRACT_FAIL=index_inv_accounting top=%0d ic=%0d dc=%0d done=%0d",
                   top_accepts, icache_accepts, dcache_accepts, icache_completions);
        $display("IDX-01_PASS unmapped_va=004006a0 top_accept=1 icache_accept=1 icache_done=1 side_effect=once");
        release_maintenance();

        // Busy target must withhold the upstream handshake. Keeping the
        // request/payload stable until ready must then accept exactly once.
        set_maintenance(5'h08, 32'h0040_06a0);
        force dut.u_icache.state = 4'd7;
        repeat (3) begin
            @(posedge aclk); #1;
            if (dut.cache_maint_addr_ok !== 1'b0 || dut.u_icache.maint_req !== 1'b1)
                $fatal(1, "IDX_CONTRACT_FAIL=busy_ready_contract");
        end
        // Model the busy engine becoming idle while the held request and
        // payload remain unchanged, then accept it on the next clock.
        force dut.u_icache.state = 4'd1;
        #1;
        check_and_accept(1, 0);
        release dut.u_icache.state;
        if (top_accepts != 2 || icache_accepts != 2 || icache_completions != 2)
            $fatal(1, "IDX_CONTRACT_FAIL=busy_duplicate_accept top=%0d ic=%0d done=%0d",
                   top_accepts, icache_accepts, icache_completions);
        $display("IDX-04_PASS busy_to_ready top_accepts=2 icache_accepts=2 completions=2");
        release_maintenance();

        // Hit operations without translation are explicitly unsupported and
        // must never reach a cache or mutate its tags.
        set_maintenance(5'h10, 32'h0040_06a0);
        #1;
        if (dut.cache_maint_unsupported !== 1'b1 || dut.cache_maint_addr_ok !== 1'b0 ||
            dut.u_icache.maint_req !== 1'b0 || dut.u_dcache.maint_req !== 1'b0)
            $fatal(1, "IDX_CONTRACT_FAIL=untranslated_hit_not_blocked");
        @(posedge aclk); #1;
        if (dut.icache_maint_done || dut.dcache_maint_done ||
            top_accepts != 2 || icache_accepts != 2 || dcache_accepts != 0)
            $fatal(1, "IDX_CONTRACT_FAIL=untranslated_hit_side_effect");
        $display("IDX-03_UNSUPPORTED_BY_SCOPE hit_translation_valid=0 downstream_accept=0 done=0");
        release_maintenance();

        expected_line = {32'h88888888, 32'h77777777, 32'h66666666, 32'h55555555,
                         32'h44444444, 32'h33333333, 32'h22222222, 32'h11111111};
        sentinel_line = {32'hfedcba98, 32'h76543210, 32'h01234567, 32'h89abcdef,
                         32'h0badc0de, 32'h55aa55aa, 32'ha5a5a5a5, 32'h5a5a5a5a};
        dut.u_dcache.tag_way3[7'h35] = 20'habcde;
        dut.u_dcache.line_way3[7'h35] = expected_line;
        dut.u_dcache.valid_way3[7'h35] = 1'b1;
        dut.u_dcache.dirty_way3[7'h35] = 1'b1;
        dut.u_dcache.tag_way0[7'h00] = 20'h54321;
        dut.u_dcache.line_way0[7'h00] = sentinel_line;
        dut.u_dcache.valid_way0[7'h00] = 1'b1;
        dut.u_dcache.dirty_way0[7'h00] = 1'b1;

        // Unmapped IndexWBInv must write the old victim Tag + VA index and
        // send all eight line words before it reports completion.
        set_maintenance(5'h01, 32'h0000_36a0);
        check_and_accept(0, 1);
        timeout_count = 0;
        while (!awvalid) begin
            @(negedge aclk);
            timeout_count = timeout_count + 1;
            if (timeout_count > 100) $fatal(1, "IDX_CONTRACT_FAIL=aw_timeout");
        end
        if (awaddr !== {20'habcde, 7'h35, 5'b0} || awlen !== 8'd7 ||
            awsize !== 3'b010 || awburst !== 2'b01 || awid !== 4'h1)
            $fatal(1, "IDX_CONTRACT_FAIL=aw_payload addr=%08x len=%0d size=%0d burst=%0d id=%0d",
                   awaddr, awlen, awsize, awburst, awid);
        @(negedge aclk); awready = 1'b1;
        @(posedge aclk); #1 awready = 1'b0;
        for (beat = 0; beat < 8; beat = beat + 1) begin
            timeout_count = 0;
            while (!wvalid) begin
                @(negedge aclk);
                timeout_count = timeout_count + 1;
                if (timeout_count > 100) $fatal(1, "IDX_CONTRACT_FAIL=w_timeout beat=%0d", beat);
            end
            expected_word = expected_line[beat*32 +: 32];
            if (wid !== 4'h1 || wdata !== expected_word || wstrb !== 4'hf ||
                wlast !== (beat == 7))
                $fatal(1, "IDX_CONTRACT_FAIL=w_payload beat=%0d data=%08x expected=%08x strb=%x last=%0d",
                       beat, wdata, expected_word, wstrb, wlast);
            @(negedge aclk);
            wready = 1'b0;
            repeat (2) begin
                @(posedge aclk); #1;
                if (!wvalid || wdata !== expected_word || wstrb !== 4'hf ||
                    wlast !== (beat == 7))
                    $fatal(1, "IDX_CONTRACT_FAIL=w_payload_not_stable beat=%0d", beat);
            end
            @(negedge aclk); wready = 1'b1;
            @(posedge aclk); #1 wready = 1'b0;
        end
        if (dut.dcache_maint_done || dcache_completions != 0)
            $fatal(1, "IDX_CONTRACT_FAIL=completed_before_b");
        bid = awid;
        bresp = 2'b00;
        bvalid = 1'b1;
        @(posedge aclk); #1 bvalid = 1'b0;
        if (!dut.dcache_maint_done || dut.u_dcache.valid_way3[7'h35] ||
            dut.u_dcache.dirty_way3[7'h35] ||
            dut.u_dcache.valid_way0[7'h00] !== 1'b1 ||
            dut.u_dcache.dirty_way0[7'h00] !== 1'b1 ||
            dut.u_dcache.tag_way0[7'h00] !== 20'h54321 ||
            dut.u_dcache.line_way0[7'h00] !== sentinel_line)
            $fatal(1, "IDX_CONTRACT_FAIL=target_clear_or_sentinel_changed");
        dcache_completions = dcache_completions + 1;
        if (top_accepts != 3 || dcache_accepts != 1 || dcache_completions != 1)
            $fatal(1, "IDX_CONTRACT_FAIL=wb_accounting top=%0d dc=%0d done=%0d",
                   top_accepts, dcache_accepts, dcache_completions);
        $display("IDX-02_PASS unmapped_va_set=35 way=3 awaddr=%08x beats=8 accept=1 done=1 sentinel_set0=preserved",
                 awaddr);
        release_maintenance();
        $display("LAB19_INDEX_CONTRACT_PASS checks=4 unsupported_hit=explicit dcache_accepts=1 dcache_done=1");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "IDX_CONTRACT_FAIL=watchdog_timeout");
    end
endmodule

// The contract test does not exercise HI/LO operations. These simple models
// let the complete CPU top elaborate without generating unrelated vendor IP.
module lab6_mult33(
    input CLK,
    input [32:0] A,
    input [32:0] B,
    input CE,
    output reg [65:0] P
);
    always @(posedge CLK) begin
        if (CE) P <= A * B;
    end
endmodule

module lab6_div32(
    input aclk,
    input aresetn,
    input s_axis_divisor_tvalid,
    output s_axis_divisor_tready,
    input [31:0] s_axis_divisor_tdata,
    input s_axis_dividend_tvalid,
    output s_axis_dividend_tready,
    input [31:0] s_axis_dividend_tdata,
    output reg m_axis_dout_tvalid,
    output reg [63:0] m_axis_dout_tdata
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
