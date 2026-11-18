`timescale 1ns/1ps

module tb_lab18_dcache_directed;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    always #5 clk = ~clk;

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
    reg hold_refill_addr = 1'b0;
    reg hold_refill_data = 1'b0;
    reg refill_active = 1'b0;
    reg [31:0] refill_addr_latched = 32'b0;
    integer refill_beat = 0;
    integer refill_transactions = 0;

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
    reg hold_uncache_addr = 1'b0;
    reg uncache_active = 1'b0;
    reg uncache_wr_latched = 1'b0;
    reg [31:0] uncache_addr_latched = 32'b0;
    reg [31:0] uncache_wdata_latched = 32'b0;
    reg [3:0] uncache_wstrb_latched = 4'b0;
    integer uncache_writes = 0;
    integer uncache_reads = 0;

    reg bridge_fault = 1'b0;
    wire [31:0] stat_hit;
    wire [31:0] stat_miss;
    wire [31:0] stat_writeback;
    wire [31:0] stat_uncache;
    wire cache_fault;
    integer accepted = 0;
    integer completed = 0;
    integer timeout;
    integer i;
    reg [31:0] saved_refill_addr;
    reg [255:0] saved_writeback_data;

    dcache dut(
        .clk(clk), .resetn(resetn),
        .cpu_req(cpu_req), .cpu_cacheable(cpu_cacheable), .cpu_wr(cpu_wr),
        .cpu_size(cpu_size), .cpu_wstrb(cpu_wstrb), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_addr_ok(cpu_addr_ok),
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

    function [31:0] model_word;
        input [31:0] addr;
        begin model_word = 32'ha500_0000 ^ {addr[31:2], 2'b00}; end
    endfunction

    always @(negedge clk) begin
        if (!resetn) begin
            refill_addr_ok = 1'b0;
            refill_data_valid = 1'b0;
            refill_data_last = 1'b0;
            refill_data = 32'b0;
            refill_active = 1'b0;
            refill_beat = 0;
            uncache_addr_ok = 1'b0;
            uncache_data_ok = 1'b0;
            uncache_active = 1'b0;
            uncache_rdata = 32'b0;
        end else begin
            refill_addr_ok = 1'b0;
            refill_data_valid = 1'b0;
            refill_data_last = 1'b0;
            if (refill_active) begin
                if (!hold_refill_data) begin
                    refill_data_valid = 1'b1;
                    refill_data = model_word(refill_addr_latched + (refill_beat * 4));
                    refill_data_last = (refill_beat == 7);
                    if (refill_beat == 7) begin
                        refill_active = 1'b0;
                    end else begin
                        refill_beat = refill_beat + 1;
                    end
                end
            end else if (refill_req && !hold_refill_addr) begin
                refill_addr_ok = 1'b1;
                refill_addr_latched = refill_addr;
                refill_beat = 0;
                refill_active = 1'b1;
                refill_transactions = refill_transactions + 1;
            end

            uncache_addr_ok = 1'b0;
            uncache_data_ok = 1'b0;
            if (uncache_active) begin
                uncache_data_ok = 1'b1;
                uncache_rdata = model_word(uncache_addr_latched);
                if (uncache_wr_latched)
                    uncache_writes = uncache_writes + 1;
                else
                    uncache_reads = uncache_reads + 1;
                uncache_active = 1'b0;
            end else if (uncache_req && !hold_uncache_addr) begin
                uncache_addr_ok = 1'b1;
                uncache_active = 1'b1;
                uncache_wr_latched = uncache_wr;
                uncache_addr_latched = uncache_addr;
                uncache_wdata_latched = uncache_wdata;
                uncache_wstrb_latched = uncache_wstrb;
            end
        end
    end

    task begin_request;
        input cacheable;
        input wr;
        input [31:0] addr;
        input [1:0] size;
        input [3:0] strb;
        input [31:0] wdata;
        begin
            @(negedge clk);
            timeout = 0;
            while (!cpu_addr_ok && timeout < 2000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!cpu_addr_ok) $fatal(1, "DCache_FAIL=cpu_accept_timeout");
            cpu_cacheable = cacheable;
            cpu_wr = wr;
            cpu_addr = addr;
            cpu_size = size;
            cpu_wstrb = strb;
            cpu_wdata = wdata;
            cpu_req = 1'b1;
            @(posedge clk);
            #1;
            cpu_req = 1'b0;
            accepted = accepted + 1;
        end
    endtask

    task finish_request;
        input check_data;
        input [31:0] expected_data;
        begin
            timeout = 0;
            while (!cpu_data_ok && timeout < 4000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!cpu_data_ok) $fatal(1, "DCache_FAIL=cpu_completion_timeout");
            if (check_data && cpu_rdata !== expected_data)
                $fatal(1, "DCache_FAIL=read_data expected=%08x observed=%08x",
                       expected_data, cpu_rdata);
            completed = completed + 1;
            @(posedge clk);
            #1;
        end
    endtask

    task request;
        input cacheable;
        input wr;
        input [31:0] addr;
        input [1:0] size;
        input [3:0] strb;
        input [31:0] wdata;
        input check_data;
        input [31:0] expected_data;
        begin
            begin_request(cacheable, wr, addr, size, strb, wdata);
            finish_request(check_data, expected_data);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;
        timeout = 0;
        while (!cpu_addr_ok && timeout < 1000) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (!cpu_addr_ok) $fatal(1, "DCache_FAIL=reset_clear_timeout");

        // D01/D08: one line miss, stable refill address while bridge arbitration stalls.
        hold_refill_addr = 1'b1;
        begin_request(1'b1, 1'b0, 32'h0000_0044, 2'd2, 4'b0, 32'b0);
        timeout = 0;
        while (!refill_req && timeout < 100) begin @(negedge clk); timeout = timeout + 1; end
        if (!refill_req || refill_addr !== 32'h0000_0040)
            $fatal(1, "DCache_FAIL=refill_request_alignment");
        saved_refill_addr = refill_addr;
        repeat (3) begin
            @(negedge clk);
            if (!refill_req || refill_addr !== saved_refill_addr)
                $fatal(1, "DCache_FAIL=refill_payload_not_stable");
        end
        @(posedge clk); #1; hold_refill_addr = 1'b0;
        finish_request(1'b1, model_word(32'h44));
        if (refill_transactions != 1 || stat_miss != 1 || stat_writeback != 0)
            $fatal(1, "DCache_FAIL=first_refill_counts ar=%0d miss=%0d wb=%0d",
                   refill_transactions, stat_miss, stat_writeback);
        $display("D01_PASS first_miss=1 refill_beats=8");

        // D02: second word in the same line is a hit and performs no AR.
        request(1'b1, 1'b0, 32'h0000_0048, 2'd2, 4'b0, 32'b0,
                1'b1, model_word(32'h48));
        if (refill_transactions != 1) $fatal(1, "DCache_FAIL=hit_issued_refill");
        $display("D02_PASS same_line_hit ar=1");

        // D03/D04/D05: full, byte, halfword, SWL and SWR lane merges.
        request(1'b1, 1'b1, 32'h0000_0044, 2'd2, 4'b1111, 32'hdead_beef, 1'b0, 0);
        request(1'b1, 1'b0, 32'h0000_0044, 2'd2, 4'b0, 32'b0, 1'b1, 32'hdead_beef);
        request(1'b1, 1'b1, 32'h0000_0045, 2'd0, 4'b0010, 32'h0000_aa00, 1'b0, 0);
        request(1'b1, 1'b1, 32'h0000_0046, 2'd1, 4'b1100, 32'h1234_0000, 1'b0, 0);
        request(1'b1, 1'b1, 32'h0000_0044, 2'd2, 4'b0001, 32'h0000_0011, 1'b0, 0);
        request(1'b1, 1'b1, 32'h0000_0046, 2'd2, 4'b1100, 32'h3344_0000, 1'b0, 0);
        request(1'b1, 1'b0, 32'h0000_0044, 2'd2, 4'b0, 32'b0, 1'b1, 32'h3344_aa11);
        if (stat_hit < 7 || refill_transactions != 1)
            $fatal(1, "DCache_FAIL=store_hit_accounting");
        $display("D03_PASS store_then_load dirty=1");
        $display("D04_PASS byte_halfword_lanes word=3344aa11");
        $display("D05_PASS swl_swr_lane_merge");

        // D06: four tags occupy one set; the fifth waits for B before requesting refill.
        request(1'b1, 1'b0, 32'h0000_1044, 2'd2, 4'b0, 32'b0, 1'b1, model_word(32'h1044));
        request(1'b1, 1'b0, 32'h0000_2044, 2'd2, 4'b0, 32'b0, 1'b1, model_word(32'h2044));
        request(1'b1, 1'b0, 32'h0000_3044, 2'd2, 4'b0, 32'b0, 1'b1, model_word(32'h3044));
        begin_request(1'b1, 1'b0, 32'h0000_4044, 2'd2, 4'b0, 32'b0);
        timeout = 0;
        while (!writeback_req && timeout < 1000) begin @(negedge clk); timeout = timeout + 1; end
        if (!writeback_req || writeback_addr !== 32'h0000_0040 ||
            writeback_data[63:32] !== 32'h3344_aa11)
            $fatal(1, "DCache_FAIL=dirty_victim_payload addr=%08x word=%08x",
                   writeback_addr, writeback_data[63:32]);
        saved_writeback_data = writeback_data;
        repeat (3) begin
            @(negedge clk);
            if (!writeback_req || writeback_addr !== 32'h0000_0040 ||
                writeback_data !== saved_writeback_data || refill_req)
                $fatal(1, "DCache_FAIL=refill_started_before_writeback_b");
        end
        @(negedge clk); writeback_addr_ok = 1'b1;
        @(posedge clk); #1; writeback_addr_ok = 1'b0;
        repeat (2) begin
            @(negedge clk);
            if (refill_req) $fatal(1, "DCache_FAIL=refill_started_before_b_response");
        end
        @(negedge clk); writeback_done = 1'b1;
        @(posedge clk); #1; writeback_done = 1'b0;
        finish_request(1'b1, model_word(32'h4044));
        if (stat_writeback != 1 || refill_transactions != 5)
            $fatal(1, "DCache_FAIL=dirty_replace_counts wb=%0d ar=%0d",
                   stat_writeback, refill_transactions);
        $display("D06_PASS dirty_victim_writeback_before_refill addr=00000040");

        // D07/D08: uncache bypass does not allocate, payload holds under backpressure,
        // and one write completes only after the downstream response.
        hold_uncache_addr = 1'b1;
        begin_request(1'b0, 1'b1, 32'h0000_0085, 2'd0, 4'b0010, 32'h0000_5a00);
        timeout = 0;
        while (!uncache_req && timeout < 100) begin @(negedge clk); timeout = timeout + 1; end
        if (!uncache_req || uncache_addr !== 32'h0000_0085 ||
            !uncache_wr || uncache_wstrb !== 4'b0010 || uncache_wdata !== 32'h0000_5a00)
            $fatal(1, "DCache_FAIL=uncache_payload");
        repeat (3) begin
            @(negedge clk);
            if (!uncache_req || uncache_addr !== 32'h0000_0085 ||
                uncache_wstrb !== 4'b0010 || uncache_wdata !== 32'h0000_5a00 ||
                uncache_data_ok)
                $fatal(1, "DCache_FAIL=uncache_payload_not_stable");
        end
        @(posedge clk); #1; hold_uncache_addr = 1'b0;
        finish_request(1'b0, 0);
        if (uncache_writes != 1 || refill_transactions != 5 || stat_uncache != 1)
            $fatal(1, "DCache_FAIL=uncache_store_count write=%0d ar=%0d unc=%0d",
                   uncache_writes, refill_transactions, stat_uncache);
        request(1'b0, 1'b0, 32'h0000_0085, 2'd0, 4'b0, 32'b0,
                1'b1, model_word(32'h85));
        if (uncache_reads != 1 || refill_transactions != 5 || stat_uncache != 2)
            $fatal(1, "DCache_FAIL=uncache_read_allocated");
        $display("D07_PASS uncache_bypass peripheral_write_once");
        $display("D08_PASS refill_uncache_backpressure_payload_stable");

        // D09: every accepted CPU request has one completion; idle cycles have none.
        repeat (4) begin
            @(negedge clk);
            if (cpu_data_ok) $fatal(1, "DCache_FAIL=unsolicited_completion");
        end
        if (accepted != completed || cache_fault || bridge_fault)
            $fatal(1, "DCache_FAIL=completion_or_fault accepted=%0d completed=%0d fault=%b",
                   accepted, completed, cache_fault);
        $display("D09_PASS request_completion_accounting accepted=%0d completed=%0d", accepted, completed);
        $display("DCache_STATS hit=%0d miss=%0d refill=%0d writeback=%0d uncache=%0d",
                 stat_hit, stat_miss, refill_transactions, stat_writeback, stat_uncache);
        $display("DIRECTED_CHECKS=9");
        $display("DCache_DIRECTED_PASS checks=9");
        $finish;
    end
endmodule
