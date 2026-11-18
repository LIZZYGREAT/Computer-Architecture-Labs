`timescale 1ns/1ps

module tb_lab19_maint_directed;
    reg clk = 1'b0;
    reg resetn = 1'b0;

    reg i_maint_req = 1'b0;
    reg [4:0] i_maint_op = 5'b0;
    reg [31:0] i_maint_vaddr = 32'b0;
    reg [31:0] i_maint_paddr = 32'b0;
    reg [31:0] i_taglo = 32'b0;
    wire i_maint_addr_ok;
    wire i_maint_done;

    reg d_maint_req = 1'b0;
    reg [4:0] d_maint_op = 5'b0;
    reg [31:0] d_maint_vaddr = 32'b0;
    reg [31:0] d_maint_paddr = 32'b0;
    reg [31:0] d_taglo = 32'b0;
    wire d_maint_addr_ok;
    wire d_maint_done;
    wire d_writeback_req;
    wire [31:0] d_writeback_addr;
    wire [255:0] d_writeback_data;
    reg d_writeback_addr_ok = 1'b0;
    reg d_writeback_done = 1'b0;
    wire [31:0] d_stat_writeback;
    wire d_cache_fault;

    integer checks = 0;
    integer timeout_count;
    always #5 clk = ~clk;

    icache u_icache (
        .clk(clk), .resetn(resetn), .cpu_req(1'b0), .cpu_cacheable(1'b0),
        .cpu_addr(32'b0), .cpu_addr_ok(), .cpu_data_ok(), .cpu_rdata(),
        .maint_req(i_maint_req), .maint_op(i_maint_op),
        .maint_vaddr(i_maint_vaddr), .maint_paddr(i_maint_paddr),
        .maint_taglo(i_taglo), .maint_addr_ok(i_maint_addr_ok), .maint_done(i_maint_done),
        .refill_req(), .refill_addr(), .refill_addr_ok(1'b0),
        .refill_data_valid(1'b0), .refill_data_last(1'b0), .refill_data(32'b0),
        .uncache_req(), .uncache_addr(), .uncache_addr_ok(1'b0),
        .uncache_data_ok(1'b0), .uncache_data(32'b0),
        .stat_hit(), .stat_miss(), .stat_refill(), .stat_uncache_read(), .cache_fault()
    );

    dcache u_dcache (
        .clk(clk), .resetn(resetn), .cpu_req(1'b0), .cpu_cacheable(1'b0),
        .cpu_wr(1'b0), .cpu_size(2'b0), .cpu_wstrb(4'b0),
        .cpu_addr(32'b0), .cpu_wdata(32'b0), .cpu_addr_ok(), .cpu_data_ok(), .cpu_rdata(),
        .maint_req(d_maint_req), .maint_op(d_maint_op),
        .maint_vaddr(d_maint_vaddr), .maint_paddr(d_maint_paddr),
        .maint_taglo(d_taglo), .maint_addr_ok(d_maint_addr_ok), .maint_done(d_maint_done),
        .refill_req(), .refill_addr(), .refill_addr_ok(1'b0),
        .refill_data_valid(1'b0), .refill_data_last(1'b0), .refill_data(32'b0),
        .writeback_req(d_writeback_req), .writeback_addr(d_writeback_addr),
        .writeback_data(d_writeback_data), .writeback_addr_ok(d_writeback_addr_ok),
        .writeback_done(d_writeback_done), .uncache_req(), .uncache_wr(),
        .uncache_size(), .uncache_wstrb(), .uncache_addr(), .uncache_wdata(),
        .uncache_addr_ok(1'b0), .uncache_data_ok(1'b0), .uncache_rdata(32'b0),
        .bridge_fault(1'b0), .stat_hit(), .stat_miss(),
        .stat_writeback(d_stat_writeback), .stat_uncache(), .cache_fault(d_cache_fault)
    );

    task issue_i(input [4:0] op, input [31:0] vaddr, input [31:0] taglo);
        begin
            @(negedge clk);
            i_maint_op = op;
            i_maint_vaddr = vaddr;
            i_taglo = taglo;
            i_maint_req = 1'b1;
            timeout_count = 0;
            while (i_maint_addr_ok !== 1'b1) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
                if (timeout_count > 100)
                    $fatal(1, "LAB19_MAINT_FAIL=icache_accept_timeout op=%02x", op);
            end
            @(posedge clk); #1 i_maint_req = 1'b0;
            timeout_count = 0;
            while (i_maint_done !== 1'b1) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
                if (timeout_count > 100)
                    $fatal(1, "LAB19_MAINT_FAIL=icache_done_timeout op=%02x", op);
            end
        end
    endtask

    task issue_d(input [4:0] op, input [31:0] vaddr,
                 input [31:0] paddr, input [31:0] taglo);
        begin
            @(negedge clk);
            d_maint_op = op;
            d_maint_vaddr = vaddr;
            d_maint_paddr = paddr;
            d_taglo = taglo;
            d_maint_req = 1'b1;
            timeout_count = 0;
            while (d_maint_addr_ok !== 1'b1) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
                if (timeout_count > 100)
                    $fatal(1, "LAB19_MAINT_FAIL=dcache_accept_timeout op=%02x", op);
            end
            @(posedge clk); #1 d_maint_req = 1'b0;
        end
    endtask

    task wait_d_done(input [4:0] op);
        begin
            timeout_count = 0;
            while (d_maint_done !== 1'b1) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
                if (timeout_count > 100)
                    $fatal(1, "LAB19_MAINT_FAIL=dcache_done_timeout op=%02x", op);
            end
        end
    endtask

    task complete_writeback(input [31:0] expected_addr, input [4:0] op);
        begin
            timeout_count = 0;
            while (d_writeback_req !== 1'b1) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
                if (timeout_count > 100)
                    $fatal(1, "LAB19_MAINT_FAIL=writeback_request_timeout op=%02x", op);
            end
            if (d_writeback_addr !== expected_addr)
                $fatal(1, "LAB19_MAINT_FAIL=writeback_address op=%02x expected=%08x observed=%08x",
                       op, expected_addr, d_writeback_addr);
            @(negedge clk); d_writeback_addr_ok = 1'b1;
            @(posedge clk); #1 d_writeback_addr_ok = 1'b0;
            repeat (3) begin
                @(posedge clk); #1;
                if (d_maint_done)
                    $fatal(1, "LAB19_MAINT_FAIL=retired_before_b op=%02x", op);
            end
            @(negedge clk); d_writeback_done = 1'b1;
            @(posedge clk); #1 d_writeback_done = 1'b0;
            if (d_maint_done !== 1'b1)
                $fatal(1, "LAB19_MAINT_FAIL=did_not_complete_after_b op=%02x", op);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        resetn = 1'b1;
        timeout_count = 0;
        while (i_maint_addr_ok !== 1'b1 || d_maint_addr_ok !== 1'b1) begin
            @(negedge clk);
            timeout_count = timeout_count + 1;
            if (timeout_count > 1000)
                $fatal(1, "LAB19_MAINT_FAIL=reset_clear_timeout");
        end

        // ICache index/tag paths explicitly cover ways two and three.
        issue_i(5'h08, {18'b0, 2'd2, 7'h35, 5'b0}, {20'h12345, 4'b0, 2'b10, 6'b0});
        if (!u_icache.valid_way2[7'h35] || u_icache.tag_way2[7'h35] !== 20'h12345)
            $fatal(1, "LAB19_MAINT_FAIL=icache_way2_tag_state");
        checks = checks + 1;
        issue_i(5'h00, {18'b0, 2'd2, 7'h35, 5'b0}, 32'b0);
        if (u_icache.valid_way2[7'h35])
            $fatal(1, "LAB19_MAINT_FAIL=icache_way2_index_invalidate");
        checks = checks + 1;
        issue_i(5'h08, {18'b0, 2'd3, 7'h56, 5'b0}, {20'hABCDE, 4'b0, 2'b11, 6'b0});
        if (!u_icache.valid_way3[7'h56] || u_icache.tag_way3[7'h56] !== 20'hABCDE)
            $fatal(1, "LAB19_MAINT_FAIL=icache_way3_tag_state");
        checks = checks + 1;
        issue_i(5'h00, {18'b0, 2'd3, 7'h56, 5'b0}, 32'b0);
        if (u_icache.valid_way3[7'h56])
            $fatal(1, "LAB19_MAINT_FAIL=icache_way3_index_invalidate");
        checks = checks + 1;

        // A dirty TagLo line can be invalidated without writing back for HitInv.
        issue_d(5'h09, {18'b0, 2'd2, 7'h35, 5'b0}, 32'b0,
                {20'h12345, 4'b0, 2'b11, 6'b0});
        wait_d_done(5'h09);
        if (!u_dcache.valid_way2[7'h35] || !u_dcache.dirty_way2[7'h35])
            $fatal(1, "LAB19_MAINT_FAIL=dcache_way2_dirty_taglo");
        checks = checks + 1;
        issue_d(5'h11, 32'h8000_06a0, {20'h12345, 7'h35, 5'b0}, 32'b0);
        wait_d_done(5'h11);
        if (u_dcache.valid_way2[7'h35] || u_dcache.dirty_way2[7'h35] || d_writeback_req)
            $fatal(1, "LAB19_MAINT_FAIL=hitinv_must_discard_without_writeback");
        checks = checks + 1;

        // IndexWBInv of a dirty way-three line waits for B before retirement.
        issue_d(5'h09, {18'b0, 2'd3, 7'h56, 5'b0}, 32'b0,
                {20'hABCDE, 4'b0, 2'b11, 6'b0});
        wait_d_done(5'h09);
        checks = checks + 1;
        issue_d(5'h01, {18'b0, 2'd3, 7'h56, 5'b0}, {20'hABCDE, 7'h56, 5'b0}, 32'b0);
        complete_writeback({20'hABCDE, 7'h56, 5'b0}, 5'h01);
        if (u_dcache.valid_way3[7'h56] || u_dcache.dirty_way3[7'h56])
            $fatal(1, "LAB19_MAINT_FAIL=index_wbinv_way3_final_state");
        checks = checks + 1;

        // HitWBInv uses physical tag matching and also waits for B.
        issue_d(5'h09, {18'b0, 2'd2, 7'h35, 5'b0}, 32'b0,
                {20'h12345, 4'b0, 2'b11, 6'b0});
        wait_d_done(5'h09);
        issue_d(5'h15, 32'h8000_06a0, {20'h12345, 7'h35, 5'b0}, 32'b0);
        complete_writeback({20'h12345, 7'h35, 5'b0}, 5'h15);
        if (u_dcache.valid_way2[7'h35] || u_dcache.dirty_way2[7'h35] ||
            d_stat_writeback != 2 || d_cache_fault)
            $fatal(1, "LAB19_MAINT_FAIL=hit_wbinv_way2_final_state");
        checks = checks + 1;

        $display("DIRECTED_CHECKS=%0d", checks);
        $display("LAB19_MAINT_DIRECTED_PASS checks=%0d icache_way=2,3 dcache_way=2,3 taglo=valid_dirty hitinv_no_writeback=1 writebacks=2 B_wait=1",
                 checks);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "LAB19_MAINT_FAIL=watchdog_timeout");
    end
endmodule
