`timescale 1ns/1ps

module tb_lab18_cache_arbitration;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    always #5 clk = ~clk;

    reg ic_cpu_req = 1'b0;
    reg [31:0] ic_cpu_addr = 32'b0;
    wire ic_cpu_addr_ok;
    wire ic_cpu_data_ok;
    wire [31:0] ic_cpu_rdata;
    wire ic_refill_req;
    wire [31:0] ic_refill_addr;
    wire ic_refill_addr_ok;
    wire ic_ret_valid;
    wire ic_ret_last;
    wire [31:0] ic_ret_data;
    wire ic_uncache_req;
    wire [31:0] ic_uncache_addr;
    wire ic_uncache_addr_ok;
    wire ic_uncache_data_ok;
    wire [31:0] ic_uncache_data;
    wire [31:0] ic_hit;
    wire [31:0] ic_miss;
    wire [31:0] ic_refill_count;
    wire [31:0] ic_uncache_count;
    wire ic_fault;

    reg dc_cpu_req = 1'b0;
    reg [31:0] dc_cpu_addr = 32'b0;
    wire dc_cpu_addr_ok;
    wire dc_cpu_data_ok;
    wire [31:0] dc_cpu_rdata;
    wire dc_refill_req;
    wire [31:0] dc_refill_addr;
    wire dc_refill_addr_ok;
    wire dc_ret_valid;
    wire dc_ret_last;
    wire [31:0] dc_ret_data;
    wire dc_wb_req;
    wire [31:0] dc_wb_addr;
    wire [255:0] dc_wb_data;
    wire dc_wb_addr_ok;
    wire dc_wb_done;
    wire dc_unc_req;
    wire dc_unc_wr;
    wire [1:0] dc_unc_size;
    wire [3:0] dc_unc_strb;
    wire [31:0] dc_unc_addr;
    wire [31:0] dc_unc_wdata;
    wire dc_unc_addr_ok;
    wire dc_unc_data_ok;
    wire [31:0] dc_unc_rdata;
    wire [31:0] dc_hit;
    wire [31:0] dc_miss;
    wire [31:0] dc_writeback_count;
    wire [31:0] dc_uncache_count;
    wire dc_fault;

    wire axi_fault;
    wire [31:0] stat_ar;
    wire [31:0] stat_r;
    wire [31:0] stat_aw;
    wire [31:0] stat_w;
    wire [31:0] stat_b;
    wire [3:0] arid;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire [1:0] arlock;
    wire [3:0] arcache;
    wire [2:0] arprot;
    wire arvalid;
    reg arready = 1'b0;
    reg [3:0] rid = 4'b0;
    reg [31:0] rdata = 32'b0;
    reg [1:0] rresp = 2'b0;
    reg rlast = 1'b0;
    reg rvalid = 1'b0;
    wire rready;
    wire [3:0] awid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire [1:0] awlock;
    wire [3:0] awcache;
    wire [2:0] awprot;
    wire awvalid;
    reg awready = 1'b0;
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

    integer timeout;
    integer beat;
    reg [31:0] first_addr;
    reg [3:0] first_id;

    icache icache_dut(
        .clk(clk), .resetn(resetn), .cpu_req(ic_cpu_req), .cpu_cacheable(1'b1),
        .cpu_addr(ic_cpu_addr), .cpu_addr_ok(ic_cpu_addr_ok),
        .cpu_data_ok(ic_cpu_data_ok), .cpu_rdata(ic_cpu_rdata),
        .refill_req(ic_refill_req), .refill_addr(ic_refill_addr),
        .refill_addr_ok(ic_refill_addr_ok), .refill_data_valid(ic_ret_valid),
        .refill_data_last(ic_ret_last), .refill_data(ic_ret_data),
        .bridge_fault(axi_fault),
        .uncache_req(ic_uncache_req), .uncache_addr(ic_uncache_addr),
        .uncache_addr_ok(ic_uncache_addr_ok), .uncache_data_ok(ic_uncache_data_ok),
        .uncache_data(ic_uncache_data), .stat_hit(ic_hit), .stat_miss(ic_miss),
        .stat_refill(ic_refill_count), .stat_uncache_read(ic_uncache_count),
        .cache_fault(ic_fault)
    );

    dcache dcache_dut(
        .clk(clk), .resetn(resetn), .cpu_req(dc_cpu_req), .cpu_cacheable(1'b1),
        .cpu_wr(1'b0), .cpu_size(2'd2), .cpu_wstrb(4'b0), .cpu_addr(dc_cpu_addr),
        .cpu_wdata(32'b0), .cpu_addr_ok(dc_cpu_addr_ok),
        .cpu_data_ok(dc_cpu_data_ok), .cpu_rdata(dc_cpu_rdata),
        .refill_req(dc_refill_req), .refill_addr(dc_refill_addr),
        .refill_addr_ok(dc_refill_addr_ok), .refill_data_valid(dc_ret_valid),
        .refill_data_last(dc_ret_last), .refill_data(dc_ret_data),
        .writeback_req(dc_wb_req), .writeback_addr(dc_wb_addr),
        .writeback_data(dc_wb_data), .writeback_addr_ok(dc_wb_addr_ok),
        .writeback_done(dc_wb_done), .uncache_req(dc_unc_req),
        .uncache_wr(dc_unc_wr), .uncache_size(dc_unc_size),
        .uncache_wstrb(dc_unc_strb), .uncache_addr(dc_unc_addr),
        .uncache_wdata(dc_unc_wdata), .uncache_addr_ok(dc_unc_addr_ok),
        .uncache_data_ok(dc_unc_data_ok), .uncache_rdata(dc_unc_rdata),
        .bridge_fault(axi_fault), .stat_hit(dc_hit), .stat_miss(dc_miss),
        .stat_writeback(dc_writeback_count), .stat_uncache(dc_uncache_count),
        .cache_fault(dc_fault)
    );

    cache_axi3_bridge bridge(
        .aclk(clk), .aresetn(resetn),
        .ic_refill_req(ic_refill_req), .ic_refill_addr(ic_refill_addr),
        .ic_refill_addr_ok(ic_refill_addr_ok), .ic_ret_valid(ic_ret_valid),
        .ic_ret_last(ic_ret_last), .ic_ret_data(ic_ret_data),
        .dc_refill_req(dc_refill_req), .dc_refill_addr(dc_refill_addr),
        .dc_refill_addr_ok(dc_refill_addr_ok), .dc_ret_valid(dc_ret_valid),
        .dc_ret_last(dc_ret_last), .dc_ret_data(dc_ret_data),
        .inst_req(ic_uncache_req), .inst_size(2'd2), .inst_addr(ic_uncache_addr),
        .inst_addr_ok(ic_uncache_addr_ok), .inst_data_ok(ic_uncache_data_ok),
        .inst_rdata(ic_uncache_data), .data_req(dc_unc_req), .data_wr(dc_unc_wr),
        .data_size(dc_unc_size), .data_wstrb(dc_unc_strb), .data_addr(dc_unc_addr),
        .data_wdata(dc_unc_wdata), .data_addr_ok(dc_unc_addr_ok),
        .data_data_ok(dc_unc_data_ok), .data_rdata(dc_unc_rdata),
        .dc_writeback_req(dc_wb_req), .dc_writeback_addr(dc_wb_addr),
        .dc_writeback_data(dc_wb_data), .dc_writeback_addr_ok(dc_wb_addr_ok),
        .dc_writeback_done(dc_wb_done), .axi_fault(axi_fault),
        .stat_ar_transactions(stat_ar), .stat_r_beats(stat_r),
        .stat_aw_transactions(stat_aw), .stat_w_beats(stat_w),
        .stat_b_responses(stat_b),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize),
        .arburst(arburst), .arlock(arlock), .arcache(arcache), .arprot(arprot),
        .arvalid(arvalid), .arready(arready), .rid(rid), .rdata(rdata),
        .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
        .awburst(awburst), .awlock(awlock), .awcache(awcache), .awprot(awprot),
        .awvalid(awvalid), .awready(awready), .wid(wid), .wdata(wdata),
        .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready)
    );

    function [31:0] model_word;
        input [31:0] addr;
        begin model_word = 32'h5a00_0000 ^ {addr[31:2], 2'b00}; end
    endfunction

    task service_line;
        input [31:0] expected_addr;
        input [3:0] expected_id;
        begin
            timeout = 0;
            while (!arvalid && timeout < 2000) begin @(negedge clk); timeout = timeout + 1; end
            if (!arvalid || araddr !== expected_addr || arlen !== 8'd7 ||
                arsize !== 3'b010 || arburst !== 2'b01 || arid !== expected_id)
                $fatal(1, "ARBITRATION_FAIL=wrong_read_owner expected=%08x/%x observed=%08x/%x len=%0d",
                       expected_addr, expected_id, araddr, arid, arlen);
            @(negedge clk); arready = 1'b1;
            @(posedge clk); #1; arready = 1'b0;
            for (beat = 0; beat < 8; beat = beat + 1) begin
                @(negedge clk);
                rid = expected_id;
                rdata = model_word(expected_addr + (beat * 4));
                rresp = 2'b00;
                rlast = (beat == 7);
                rvalid = 1'b1;
                @(posedge clk); #1; rvalid = 1'b0;
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk); resetn = 1'b1;
        timeout = 0;
        while ((!ic_cpu_addr_ok || !dc_cpu_addr_ok) && timeout < 1000) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (!ic_cpu_addr_ok || !dc_cpu_addr_ok)
            $fatal(1, "ARBITRATION_FAIL=cache_reset_clear_timeout");

        ic_cpu_addr = 32'h0000_0044;
        dc_cpu_addr = 32'h0000_2048;
        ic_cpu_req = 1'b1;
        dc_cpu_req = 1'b1;
        @(posedge clk); #1;
        ic_cpu_req = 1'b0;
        dc_cpu_req = 1'b0;

        timeout = 0;
        while ((!ic_refill_req || !dc_refill_req) && timeout < 100) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (!ic_refill_req || !dc_refill_req)
            $fatal(1, "ARBITRATION_FAIL=simultaneous_misses_not_issued");

        service_line(32'h0000_0040, 4'h0);
        timeout = 0;
        while (!ic_cpu_data_ok && timeout < 100) begin @(negedge clk); timeout = timeout + 1; end
        if (!ic_cpu_data_ok || ic_cpu_rdata !== model_word(32'h44))
            $fatal(1, "ARBITRATION_FAIL=icache_owner_response");

        service_line(32'h0000_2040, 4'h1);
        timeout = 0;
        while (!dc_cpu_data_ok && timeout < 100) begin @(negedge clk); timeout = timeout + 1; end
        if (!dc_cpu_data_ok || dc_cpu_rdata !== model_word(32'h2048))
            $fatal(1, "ARBITRATION_FAIL=dcache_owner_response");

        if (stat_ar != 2 || stat_r != 16 || axi_fault || ic_fault || dc_fault ||
            ic_miss != 1 || ic_refill_count != 1 || dc_miss != 1 || dc_writeback_count != 0)
            $fatal(1, "ARBITRATION_FAIL=metrics ar=%0d r=%0d ic=%0d/%0d dc=%0d/%0d fault=%b",
                   stat_ar, stat_r, ic_miss, ic_refill_count, dc_miss,
                   dc_writeback_count, axi_fault);
        $display("LAB18_SIMULTANEOUS_MISS_PASS ic_ar=1 dc_ar=1 id_owner_checked=1 r_beats=16");
        $display("LAB18_ARBITRATION_PASS");
        $finish;
    end
endmodule
