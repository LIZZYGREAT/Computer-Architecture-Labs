`timescale 1ns/1ps

module tb_lab18_dcache_fault_directed;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg bridge_fault = 1'b0;
    reg cpu_req = 1'b0;
    reg cpu_cacheable = 1'b1;
    reg cpu_wr = 1'b0;
    reg [1:0] cpu_size = 2'd2;
    reg [3:0] cpu_wstrb = 4'b0;
    reg [31:0] cpu_addr = 32'b0;
    reg [31:0] cpu_wdata = 32'b0;
    wire cpu_addr_ok;
    wire cpu_data_ok;
    wire [31:0] cpu_rdata;
    wire refill_req;
    wire [31:0] refill_addr;
    reg refill_addr_ok = 1'b0;
    reg refill_data_valid = 1'b0;
    reg refill_data_last = 1'b0;
    reg [31:0] refill_data = 32'b0;
    wire writeback_req;
    wire [31:0] writeback_addr;
    wire [255:0] writeback_data;
    reg writeback_addr_ok = 1'b0;
    reg writeback_done = 1'b0;
    wire uncache_req;
    wire uncache_wr;
    wire [1:0] uncache_size;
    wire [3:0] uncache_wstrb;
    wire [31:0] uncache_addr;
    wire [31:0] uncache_wdata;
    reg uncache_addr_ok = 1'b0;
    reg uncache_data_ok = 1'b0;
    reg [31:0] uncache_rdata = 32'b0;
    wire [31:0] stat_hit;
    wire [31:0] stat_miss;
    wire [31:0] stat_writeback;
    wire [31:0] stat_uncache;
    wire cache_fault;
    integer timeout;
    integer checks = 0;

    always #5 clk = ~clk;

    dcache dut (
        .clk(clk), .resetn(resetn), .cpu_req(cpu_req), .cpu_cacheable(cpu_cacheable),
        .cpu_wr(cpu_wr), .cpu_size(cpu_size), .cpu_wstrb(cpu_wstrb),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_addr_ok(cpu_addr_ok),
        .cpu_data_ok(cpu_data_ok), .cpu_rdata(cpu_rdata),
        .refill_req(refill_req), .refill_addr(refill_addr),
        .refill_addr_ok(refill_addr_ok), .refill_data_valid(refill_data_valid),
        .refill_data_last(refill_data_last), .refill_data(refill_data),
        .writeback_req(writeback_req), .writeback_addr(writeback_addr),
        .writeback_data(writeback_data), .writeback_addr_ok(writeback_addr_ok),
        .writeback_done(writeback_done), .uncache_req(uncache_req),
        .uncache_wr(uncache_wr), .uncache_size(uncache_size),
        .uncache_wstrb(uncache_wstrb), .uncache_addr(uncache_addr),
        .uncache_wdata(uncache_wdata), .uncache_addr_ok(uncache_addr_ok),
        .uncache_data_ok(uncache_data_ok), .uncache_rdata(uncache_rdata),
        .bridge_fault(bridge_fault), .stat_hit(stat_hit), .stat_miss(stat_miss),
        .stat_writeback(stat_writeback), .stat_uncache(stat_uncache),
        .cache_fault(cache_fault)
    );

    task reset_cache;
        begin
            resetn = 1'b0;
            bridge_fault = 1'b0;
            cpu_req = 1'b0;
            refill_addr_ok = 1'b0;
            refill_data_valid = 1'b0;
            refill_data_last = 1'b0;
            writeback_addr_ok = 1'b0;
            writeback_done = 1'b0;
            uncache_addr_ok = 1'b0;
            uncache_data_ok = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk); resetn = 1'b1;
            timeout = 0;
            while (cpu_addr_ok !== 1'b1) begin
                @(negedge clk);
                timeout = timeout + 1;
                if (timeout > 1000) $fatal(1, "DFAULT_FAIL=reset_timeout");
            end
        end
    endtask

    task start_cacheable_request(input [31:0] address);
        begin
            @(negedge clk);
            cpu_addr = address;
            cpu_cacheable = 1'b1;
            cpu_wr = 1'b0;
            cpu_wstrb = 4'b0;
            cpu_req = 1'b1;
            @(posedge clk);
            if (!cpu_addr_ok) $fatal(1, "DFAULT_FAIL=request_not_accepted");
            #1 cpu_req = 1'b0;
        end
    endtask

    task assert_terminal_fault(input [127:0] case_name);
        begin
            @(posedge clk); #1;
            if (!cache_fault || dut.state !== 4'd10 || cpu_data_ok || cpu_addr_ok)
                $fatal(1, "DFAULT_FAIL=not_fail_stop case=%0s state=%0d fault=%0d data_ok=%0d addr_ok=%0d",
                       case_name, dut.state, cache_fault, cpu_data_ok, cpu_addr_ok);
            checks = checks + 1;
        end
    endtask

    initial begin
        reset_cache();

        // Idle: a sticky bridge error must block a new hit/request.
        @(negedge clk); bridge_fault = 1'b1;
        assert_terminal_fault("IDLE");
        if (stat_hit != 0 || stat_miss != 0)
            $fatal(1, "DFAULT_FAIL=idle_fault_changed_stats");
        $display("DFAULT_IDLE_PASS state=ST_FAULT new_request_blocked=1");

        reset_cache();
        start_cacheable_request(32'h0000_1000);
        if (dut.state !== 4'd2) $fatal(1, "DFAULT_FAIL=lookup_setup state=%0d", dut.state);
        @(negedge clk); bridge_fault = 1'b1;
        assert_terminal_fault("LOOKUP");
        if (stat_miss != 0 || cpu_data_ok)
            $fatal(1, "DFAULT_FAIL=lookup_completed_after_fault");
        $display("DFAULT_LOOKUP_PASS state=ST_FAULT normal_completion=0");

        reset_cache();
        dut.tag_way0[7'h00] = 20'h00000;
        dut.line_way0[7'h00] = 256'h12345678;
        dut.valid_way0[7'h00] = 1'b1;
        dut.dirty_way0[7'h00] = 1'b1;
        dut.valid_way1[7'h00] = 1'b1;
        dut.valid_way2[7'h00] = 1'b1;
        dut.valid_way3[7'h00] = 1'b1;
        start_cacheable_request(32'h0000_1000);
        @(posedge clk); #1;
        if (!writeback_req || dut.state !== 4'd3)
            $fatal(1, "DFAULT_FAIL=writeback_req_setup");
        @(negedge clk); writeback_addr_ok = 1'b1;
        @(posedge clk); #1; writeback_addr_ok = 1'b0;
        if (dut.state !== 4'd4) $fatal(1, "DFAULT_FAIL=writeback_wait_setup");
        @(negedge clk); bridge_fault = 1'b1;
        assert_terminal_fault("WB_WAIT");
        if (stat_writeback != 0 || !dut.valid_way0[7'h00] || !dut.dirty_way0[7'h00])
            $fatal(1, "DFAULT_FAIL=failed_writeback_mutated_victim");
        $display("DFAULT_WB_WAIT_PASS state=ST_FAULT writeback_done=0 victim_preserved=1");

        reset_cache();
        start_cacheable_request(32'h0000_2000);
        @(posedge clk); #1;
        if (dut.state !== 4'd5) $fatal(1, "DFAULT_FAIL=refill_req_setup");
        @(negedge clk); refill_addr_ok = 1'b1;
        @(posedge clk); #1; refill_addr_ok = 1'b0;
        if (dut.state !== 4'd6) $fatal(1, "DFAULT_FAIL=refill_data_setup");
        @(negedge clk); bridge_fault = 1'b1;
        assert_terminal_fault("REFILL_DATA");
        if (dut.valid_way0[7'h00] || dut.valid_way1[7'h00] ||
            dut.valid_way2[7'h00] || dut.valid_way3[7'h00] || cpu_data_ok)
            $fatal(1, "DFAULT_FAIL=refill_error_allocated_line");
        $display("DFAULT_REFILL_DATA_PASS state=ST_FAULT valid_line=0 completion=0");

        $display("LAB18_DCACHE_FAULT_PASS checks=%0d", checks);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "DFAULT_FAIL=watchdog_timeout");
    end
endmodule
