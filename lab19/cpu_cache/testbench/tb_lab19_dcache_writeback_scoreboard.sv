`timescale 1ns/1ps

module tb_lab19_dcache_writeback_scoreboard;
    localparam [6:0] TEST_SET = 7'h35;

    reg clk = 1'b0;
    reg resetn = 1'b0;

    reg cpu_req = 1'b0;
    reg cpu_cacheable = 1'b1;
    reg cpu_wr = 1'b0;
    reg [1:0] cpu_size = 2'b10;
    reg [3:0] cpu_wstrb = 4'hf;
    reg [31:0] cpu_addr = 32'b0;
    reg [31:0] cpu_wdata = 32'b0;
    wire cpu_addr_ok;
    wire cpu_data_ok;
    wire [31:0] cpu_rdata;

    reg maint_req = 1'b0;
    reg [4:0] maint_op = 5'b0;
    reg [31:0] maint_vaddr = 32'b0;
    reg [31:0] maint_paddr = 32'b0;
    reg [31:0] maint_taglo = 32'b0;
    wire maint_addr_ok;
    wire maint_done;

    wire refill_req;
    wire [31:0] refill_addr;
    wire refill_addr_ok;
    wire refill_data_valid;
    wire refill_data_last;
    wire [31:0] refill_data;
    wire writeback_req;
    wire [31:0] writeback_addr;
    wire [255:0] writeback_data;
    wire writeback_addr_ok;
    wire writeback_done;
    wire uncache_req;
    wire uncache_wr;
    wire [1:0] uncache_size;
    wire [3:0] uncache_wstrb;
    wire [31:0] uncache_addr;
    wire [31:0] uncache_wdata;
    wire axi_fault;
    wire [31:0] stat_hit;
    wire [31:0] stat_miss;
    wire [31:0] stat_writeback;
    wire [31:0] stat_uncache;
    wire cache_fault;

    reg arready = 1'b0;
    wire [3:0] arid;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire arvalid;
    reg [3:0] rid = 4'b0;
    reg [31:0] rdata = 32'b0;
    reg [1:0] rresp = 2'b0;
    reg rlast = 1'b0;
    reg rvalid = 1'b0;
    wire rready;

    reg awready = 1'b0;
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
    reg wready = 1'b0;
    reg [3:0] bid = 4'b0;
    reg [1:0] bresp = 2'b0;
    reg bvalid = 1'b0;
    wire bready;

    wire [31:0] stat_ar_transactions;
    wire [31:0] stat_r_beats;
    wire [31:0] stat_aw_transactions;
    wire [31:0] stat_w_beats;
    wire [31:0] stat_b_responses;

    reg [31:0] reference_memory [0:31];
    integer timeout_count;
    integer refill_count = 0;
    integer store_count = 0;
    integer maint_count = 0;
    integer way;
    integer beat;
    integer word_index;
    reg [19:0] tag_value;
    reg [31:0] store_addr;
    reg [31:0] store_value;
    reg [255:0] expected_line;

    always #5 clk = ~clk;

    function [31:0] model_word(input [31:0] address);
        begin
            model_word = 32'h6d2b_79f5 ^ address ^ {address[18:0], address[31:19]};
        end
    endfunction

    dcache u_dcache (
        .clk(clk), .resetn(resetn),
        .cpu_req(cpu_req), .cpu_cacheable(cpu_cacheable), .cpu_wr(cpu_wr),
        .cpu_size(cpu_size), .cpu_wstrb(cpu_wstrb), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_addr_ok(cpu_addr_ok),
        .cpu_data_ok(cpu_data_ok), .cpu_rdata(cpu_rdata),
        .maint_req(maint_req), .maint_op(maint_op), .maint_vaddr(maint_vaddr),
        .maint_paddr(maint_paddr), .maint_taglo(maint_taglo),
        .maint_addr_ok(maint_addr_ok), .maint_done(maint_done),
        .refill_req(refill_req), .refill_addr(refill_addr),
        .refill_addr_ok(refill_addr_ok), .refill_data_valid(refill_data_valid),
        .refill_data_last(refill_data_last), .refill_data(refill_data),
        .writeback_req(writeback_req), .writeback_addr(writeback_addr),
        .writeback_data(writeback_data), .writeback_addr_ok(writeback_addr_ok),
        .writeback_done(writeback_done), .uncache_req(uncache_req),
        .uncache_wr(uncache_wr), .uncache_size(uncache_size),
        .uncache_wstrb(uncache_wstrb), .uncache_addr(uncache_addr),
        .uncache_wdata(uncache_wdata), .uncache_addr_ok(1'b0),
        .uncache_data_ok(1'b0), .uncache_rdata(32'b0),
        .bridge_fault(axi_fault), .stat_hit(stat_hit), .stat_miss(stat_miss),
        .stat_writeback(stat_writeback), .stat_uncache(stat_uncache),
        .cache_fault(cache_fault)
    );

    cache_axi3_bridge u_bridge (
        .aclk(clk), .aresetn(resetn),
        .ic_refill_req(1'b0), .ic_refill_addr(32'b0),
        .ic_refill_addr_ok(), .ic_ret_valid(), .ic_ret_last(), .ic_ret_data(),
        .dc_refill_req(refill_req), .dc_refill_addr(refill_addr),
        .dc_refill_addr_ok(refill_addr_ok), .dc_ret_valid(refill_data_valid),
        .dc_ret_last(refill_data_last), .dc_ret_data(refill_data),
        .inst_req(1'b0), .inst_size(2'b0), .inst_addr(32'b0),
        .inst_addr_ok(), .inst_data_ok(), .inst_rdata(),
        .data_req(1'b0), .data_wr(1'b0), .data_size(2'b0),
        .data_wstrb(4'b0), .data_addr(32'b0), .data_wdata(32'b0),
        .data_addr_ok(), .data_data_ok(), .data_rdata(),
        .dc_writeback_req(writeback_req), .dc_writeback_addr(writeback_addr),
        .dc_writeback_data(writeback_data),
        .dc_writeback_addr_ok(writeback_addr_ok),
        .dc_writeback_done(writeback_done), .axi_fault(axi_fault),
        .stat_ar_transactions(stat_ar_transactions), .stat_r_beats(stat_r_beats),
        .stat_aw_transactions(stat_aw_transactions), .stat_w_beats(stat_w_beats),
        .stat_b_responses(stat_b_responses),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize),
        .arburst(arburst), .arlock(), .arcache(), .arprot(), .arvalid(arvalid),
        .arready(arready), .rid(rid), .rdata(rdata), .rresp(rresp),
        .rlast(rlast), .rvalid(rvalid), .rready(rready),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
        .awburst(awburst), .awlock(), .awcache(), .awprot(), .awvalid(awvalid),
        .awready(awready), .wid(wid), .wdata(wdata), .wstrb(wstrb),
        .wlast(wlast), .wvalid(wvalid), .wready(wready), .bid(bid),
        .bresp(bresp), .bvalid(bvalid), .bready(bready)
    );

    task serve_refill(input integer line_way, input [31:0] line_base);
        integer refill_beat;
        begin
            timeout_count = 0;
            while (arvalid !== 1'b1) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
                if (timeout_count > 100)
                    $fatal(1, "WB_SCOREBOARD_FAIL=ar_timeout way=%0d", line_way);
            end
            if (arid !== 4'h1 || araddr !== line_base || arlen !== 8'd7 ||
                arsize !== 3'b010 || arburst !== 2'b01)
                $fatal(1, "WB_SCOREBOARD_FAIL=refill_ar_payload way=%0d addr=%08x expected=%08x id=%x len=%0d",
                       line_way, araddr, line_base, arid, arlen);
            @(negedge clk); arready = 1'b1;
            @(posedge clk); #1 arready = 1'b0;
            for (refill_beat = 0; refill_beat < 8; refill_beat = refill_beat + 1) begin
                @(negedge clk);
                rid = 4'h1;
                rdata = model_word(line_base + refill_beat * 4);
                rresp = 2'b00;
                rlast = (refill_beat == 7);
                rvalid = 1'b1;
                reference_memory[line_way * 8 + refill_beat] = rdata;
                if (rready !== 1'b1)
                    $fatal(1, "WB_SCOREBOARD_FAIL=refill_rready way=%0d beat=%0d", line_way, refill_beat);
                @(posedge clk); #1 rvalid = 1'b0;
            end
            refill_count = refill_count + 1;
        end
    endtask

    task cpu_store_line(input integer line_way, input [31:0] address,
                        input [31:0] value);
        begin
            @(negedge clk);
            cpu_addr = address;
            cpu_wdata = value;
            cpu_wr = 1'b1;
            cpu_wstrb = 4'hf;
            cpu_req = 1'b1;
            timeout_count = 0;
            while (cpu_addr_ok !== 1'b1) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
                if (timeout_count > 100)
                    $fatal(1, "WB_SCOREBOARD_FAIL=cpu_store_accept_timeout way=%0d", line_way);
            end
            @(posedge clk); #1 cpu_req = 1'b0;
            serve_refill(line_way, {address[31:5], 5'b0});
            timeout_count = 0;
            while (cpu_data_ok !== 1'b1) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
                if (timeout_count > 100)
                    $fatal(1, "WB_SCOREBOARD_FAIL=cpu_store_complete_timeout way=%0d", line_way);
            end
            reference_memory[line_way * 8 + address[4:2]] = value;
            @(posedge clk); #1;
            store_count = store_count + 1;
        end
    endtask

    task check_way_line(input integer line_way, input [19:0] expected_tag,
                        input [255:0] expected_data, input integer expected_valid);
        begin
            case (line_way)
                0: begin
                    if (u_dcache.tag_way0[TEST_SET] !== expected_tag ||
                        u_dcache.valid_way0[TEST_SET] !== expected_valid[0] ||
                        (expected_valid && (!u_dcache.dirty_way0[TEST_SET] || u_dcache.line_way0[TEST_SET] !== expected_data)) ||
                        (!expected_valid && u_dcache.dirty_way0[TEST_SET]))
                        $fatal(1, "WB_SCOREBOARD_FAIL=way0_state valid=%0d dirty=%0d tag=%05x",
                               u_dcache.valid_way0[TEST_SET], u_dcache.dirty_way0[TEST_SET], u_dcache.tag_way0[TEST_SET]);
                end
                1: begin
                    if (u_dcache.tag_way1[TEST_SET] !== expected_tag ||
                        u_dcache.valid_way1[TEST_SET] !== expected_valid[0] ||
                        (expected_valid && (!u_dcache.dirty_way1[TEST_SET] || u_dcache.line_way1[TEST_SET] !== expected_data)) ||
                        (!expected_valid && u_dcache.dirty_way1[TEST_SET]))
                        $fatal(1, "WB_SCOREBOARD_FAIL=way1_state valid=%0d dirty=%0d tag=%05x",
                               u_dcache.valid_way1[TEST_SET], u_dcache.dirty_way1[TEST_SET], u_dcache.tag_way1[TEST_SET]);
                end
                2: begin
                    if (u_dcache.tag_way2[TEST_SET] !== expected_tag ||
                        u_dcache.valid_way2[TEST_SET] !== expected_valid[0] ||
                        (expected_valid && (!u_dcache.dirty_way2[TEST_SET] || u_dcache.line_way2[TEST_SET] !== expected_data)) ||
                        (!expected_valid && u_dcache.dirty_way2[TEST_SET]))
                        $fatal(1, "WB_SCOREBOARD_FAIL=way2_state valid=%0d dirty=%0d tag=%05x",
                               u_dcache.valid_way2[TEST_SET], u_dcache.dirty_way2[TEST_SET], u_dcache.tag_way2[TEST_SET]);
                end
                default: begin
                    if (u_dcache.tag_way3[TEST_SET] !== expected_tag ||
                        u_dcache.valid_way3[TEST_SET] !== expected_valid[0] ||
                        (expected_valid && (!u_dcache.dirty_way3[TEST_SET] || u_dcache.line_way3[TEST_SET] !== expected_data)) ||
                        (!expected_valid && u_dcache.dirty_way3[TEST_SET]))
                        $fatal(1, "WB_SCOREBOARD_FAIL=way3_state valid=%0d dirty=%0d tag=%05x",
                               u_dcache.valid_way3[TEST_SET], u_dcache.dirty_way3[TEST_SET], u_dcache.tag_way3[TEST_SET]);
                end
            endcase
        end
    endtask

    task check_other_way_validity(input integer invalid_way);
        integer check_way;
        reg observed_valid;
        begin
            for (check_way = 0; check_way < 4; check_way = check_way + 1) begin
                case (check_way)
                    0: observed_valid = u_dcache.valid_way0[TEST_SET];
                    1: observed_valid = u_dcache.valid_way1[TEST_SET];
                    2: observed_valid = u_dcache.valid_way2[TEST_SET];
                    default: observed_valid = u_dcache.valid_way3[TEST_SET];
                endcase
                if (observed_valid !== (check_way > invalid_way))
                    $fatal(1, "WB_SCOREBOARD_FAIL=other_way_mutated target=%0d way=%0d valid=%0d",
                           invalid_way, check_way, observed_valid);
            end
        end
    endtask

    task issue_index_wbinv(input integer line_way, input [19:0] line_tag,
                           input [255:0] expected_data);
        integer write_beat;
        integer aw_count;
        integer w_count;
        integer b_count;
        reg [31:0] expected_addr;
        reg [31:0] expected_word;
        begin
            aw_count = 0;
            w_count = 0;
            b_count = 0;
            expected_addr = {line_tag, TEST_SET, 5'b0};
            @(negedge clk);
            maint_op = 5'h01;
            maint_vaddr = (line_way << 12) | (TEST_SET << 5);
            maint_paddr = 32'b0;
            maint_req = 1'b1;
            timeout_count = 0;
            while (maint_addr_ok !== 1'b1) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
                if (timeout_count > 100)
                    $fatal(1, "WB_SCOREBOARD_FAIL=maint_accept_timeout way=%0d", line_way);
            end
            @(posedge clk); #1 maint_req = 1'b0;

            timeout_count = 0;
            while (awvalid !== 1'b1) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
                if (timeout_count > 100)
                    $fatal(1, "WB_SCOREBOARD_FAIL=aw_timeout way=%0d", line_way);
            end
            if (awaddr !== expected_addr || awlen !== 8'd7 || awsize !== 3'b010 ||
                awburst !== 2'b01 || awid !== 4'h1)
                $fatal(1, "WB_SCOREBOARD_FAIL=aw_payload way=%0d addr=%08x expected=%08x len=%0d size=%0d burst=%0d id=%x",
                       line_way, awaddr, expected_addr, awlen, awsize, awburst, awid);
            if (wvalid !== 1'b1 || wdata !== expected_data[31:0] ||
                wstrb !== 4'hf || wlast !== 1'b0)
                $fatal(1, "WB_SCOREBOARD_FAIL=first_w_payload way=%0d data=%08x expected=%08x",
                       line_way, wdata, expected_data[31:0]);

            // Hold both channels under backpressure, checking stable payloads.
            repeat (2) begin
                @(posedge clk); #1;
                if (!awvalid || awaddr !== expected_addr || awlen !== 8'd7 ||
                    !wvalid || wdata !== expected_data[31:0] || wstrb !== 4'hf || wlast)
                    $fatal(1, "WB_SCOREBOARD_FAIL=aw_w_stability way=%0d", line_way);
            end
            @(negedge clk); awready = 1'b1;
            @(posedge clk); #1 awready = 1'b0;
            aw_count = aw_count + 1;

            w_count = 0;
            for (write_beat = 0; write_beat < 8; write_beat = write_beat + 1) begin
                expected_word = reference_memory[line_way * 8 + write_beat];
                timeout_count = 0;
                while (wvalid !== 1'b1) begin
                    @(negedge clk);
                    timeout_count = timeout_count + 1;
                    if (timeout_count > 100)
                        $fatal(1, "WB_SCOREBOARD_FAIL=w_timeout way=%0d beat=%0d", line_way, write_beat);
                end
                if (wid !== 4'h1 || wdata !== expected_word || wstrb !== 4'hf ||
                    wlast !== (write_beat == 7))
                    $fatal(1, "WB_SCOREBOARD_FAIL=w_payload way=%0d beat=%0d id=%x data=%08x expected=%08x strb=%x last=%0d",
                           line_way, write_beat, wid, wdata, expected_word, wstrb, wlast);
                repeat (2) begin
                    @(posedge clk); #1;
                    if (!wvalid || wid !== 4'h1 || wdata !== expected_word ||
                        wstrb !== 4'hf || wlast !== (write_beat == 7))
                        $fatal(1, "WB_SCOREBOARD_FAIL=w_stability way=%0d beat=%0d", line_way, write_beat);
                end
                @(negedge clk); wready = 1'b1;
                @(posedge clk); #1 wready = 1'b0;
                w_count = w_count + 1;
            end
            if (w_count != 8 || maint_done || !bready)
                $fatal(1, "WB_SCOREBOARD_FAIL=before_b way=%0d w=%0d done=%0d bready=%0d",
                       line_way, w_count, maint_done, bready);

            @(negedge clk);
            bid = 4'h1;
            bresp = 2'b00;
            bvalid = 1'b1;
            if (maint_done)
                $fatal(1, "WB_SCOREBOARD_FAIL=done_before_b way=%0d", line_way);
            @(posedge clk); #1 bvalid = 1'b0;
            b_count = b_count + 1;
            if (maint_done !== 1'b1 || axi_fault || cache_fault)
                $fatal(1, "WB_SCOREBOARD_FAIL=b_completion way=%0d done=%0d axi_fault=%0d cache_fault=%0d",
                       line_way, maint_done, axi_fault, cache_fault);
            if (aw_count != 1 || w_count != 8 || b_count != 1)
                $fatal(1, "WB_SCOREBOARD_FAIL=transaction_counts way=%0d aw=%0d w=%0d b=%0d",
                       line_way, aw_count, w_count, b_count);
            check_way_line(line_way, line_tag, expected_data, 0);
            check_other_way_validity(line_way);
            maint_count = maint_count + 1;
            $display("WRITEBACK_WAY_PASS way=%0d tag=%05x set=35 awaddr=%08x beats=%0d store=1 before_b_done=0 after_b_done=1",
                     line_way, line_tag, awaddr, w_count);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        resetn = 1'b1;
        timeout_count = 0;
        while (!u_dcache.reset_done) begin
            @(negedge clk);
            timeout_count = timeout_count + 1;
            if (timeout_count > 1000)
                $fatal(1, "WB_SCOREBOARD_FAIL=cache_reset_timeout");
        end

        for (way = 0; way < 4; way = way + 1) begin
            tag_value = 20'h10001 + way;
            store_addr = {tag_value, TEST_SET, 5'b0} + (way + 1) * 4;
            store_value = 32'hcafe_0000 | (way * 32'h101 + way);
            cpu_store_line(way, store_addr, store_value);
            expected_line = 256'b0;
            for (beat = 0; beat < 8; beat = beat + 1)
                expected_line[beat*32 +: 32] = reference_memory[way * 8 + beat];
            check_way_line(way, tag_value, expected_line, 1);
            $display("CPU_STORE_WAY_PASS way=%0d tag=%05x addr=%08x store=%08x line_dirty=1",
                     way, tag_value, store_addr, store_value);
        end

        for (way = 0; way < 4; way = way + 1) begin
            tag_value = 20'h10001 + way;
            expected_line = 256'b0;
            for (beat = 0; beat < 8; beat = beat + 1)
                expected_line[beat*32 +: 32] = reference_memory[way * 8 + beat];
            issue_index_wbinv(way, tag_value, expected_line);
        end

        if (refill_count != 4 || store_count != 4 || maint_count != 4 ||
            stat_ar_transactions != 4 || stat_r_beats != 32 ||
            stat_aw_transactions != 4 || stat_w_beats != 32 ||
            stat_b_responses != 4 || stat_writeback != 4 ||
            axi_fault || cache_fault)
            $fatal(1, "WB_SCOREBOARD_FAIL=final_counts refill=%0d store=%0d maint=%0d ar=%0d r=%0d aw=%0d w=%0d b=%0d cache_wb=%0d fault=%0d/%0d",
                   refill_count, store_count, maint_count, stat_ar_transactions,
                   stat_r_beats, stat_aw_transactions, stat_w_beats,
                   stat_b_responses, stat_writeback, axi_fault, cache_fault);
        $display("LAB19_DCache_WRITEBACK_SCOREBOARD_PASS ways=4 cpu_stores=4 refills=4 AW=4 W=32 B=4 full_data_compare=1 backpressure=stable");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "WB_SCOREBOARD_FAIL=watchdog_timeout");
    end
endmodule
