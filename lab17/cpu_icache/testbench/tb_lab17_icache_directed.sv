module tb_lab17_icache_directed;
    timeunit 1ns;
    timeprecision 1ps;

    reg clk;
    reg resetn;

    reg cpu_req;
    reg cpu_cacheable;
    reg [31:0] cpu_addr;
    wire cpu_addr_ok;
    wire cpu_data_ok;
    wire [31:0] cpu_rdata;

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
    wire [31:0] ic_stat_hit;
    wire [31:0] ic_stat_miss;
    wire [31:0] ic_stat_refill;
    wire [31:0] ic_stat_uncache_read;
    wire icache_fault;

    reg data_req;
    reg data_wr;
    reg [1:0] data_size;
    reg [3:0] data_wstrb;
    reg [31:0] data_addr;
    reg [31:0] data_wdata;
    wire data_addr_ok;
    wire data_data_ok;
    wire [31:0] data_rdata;

    reg dc_writeback_req;
    reg [31:0] dc_writeback_addr;
    reg [255:0] dc_writeback_data;
    wire dc_writeback_addr_ok;
    wire dc_writeback_done;

    wire axi_fault;
    wire [31:0] stat_ar_transactions;
    wire [31:0] stat_r_beats;
    wire [31:0] stat_aw_transactions;
    wire [31:0] stat_w_beats;
    wire [31:0] stat_b_responses;

    wire [3:0] arid;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire [1:0] arlock;
    wire [3:0] arcache;
    wire [2:0] arprot;
    wire arvalid;
    reg arready;
    reg [3:0] rid;
    reg [31:0] rdata;
    reg [1:0] rresp;
    reg rlast;
    reg rvalid;
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
    reg awready;
    wire [3:0] wid;
    wire [31:0] wdata;
    wire [3:0] wstrb;
    wire wlast;
    wire wvalid;
    reg wready;
    reg [3:0] bid;
    reg [1:0] bresp;
    reg bvalid;
    wire bready;

    integer cpu_accepts;
    integer cpu_completions;
    integer data_accepts;
    integer data_completions;
    reg data_done_seen;
    integer wb_accepts;
    integer wb_completions;
    integer rbeat_index;
    integer timeout;
    integer i;
    reg [31:0] expected;
    reg [31:0] ar_hold_addr;
    reg [7:0] ar_hold_len;
    reg [3:0] ar_hold_id;
    reg [31:0] aw_hold_addr;
    reg [7:0] aw_hold_len;
    reg [7:0] w_seen;

    icache dut_icache (
        .clk(clk),
        .resetn(resetn),
        .cpu_req(cpu_req),
        .cpu_cacheable(cpu_cacheable),
        .cpu_addr(cpu_addr),
        .cpu_addr_ok(cpu_addr_ok),
        .cpu_data_ok(cpu_data_ok),
        .cpu_rdata(cpu_rdata),
        .refill_req(ic_refill_req),
        .refill_addr(ic_refill_addr),
        .refill_addr_ok(ic_refill_addr_ok),
        .refill_data_valid(ic_ret_valid),
        .refill_data_last(ic_ret_last),
        .refill_data(ic_ret_data),
        .bridge_fault(axi_fault),
        .uncache_req(ic_uncache_req),
        .uncache_addr(ic_uncache_addr),
        .uncache_addr_ok(ic_uncache_addr_ok),
        .uncache_data_ok(ic_uncache_data_ok),
        .uncache_data(ic_uncache_data),
        .stat_hit(ic_stat_hit),
        .stat_miss(ic_stat_miss),
        .stat_refill(ic_stat_refill),
        .stat_uncache_read(ic_stat_uncache_read),
        .cache_fault(icache_fault)
    );

    cache_axi3_bridge dut_bridge (
        .aclk(clk),
        .aresetn(resetn),
        .ic_refill_req(ic_refill_req),
        .ic_refill_addr(ic_refill_addr),
        .ic_refill_addr_ok(ic_refill_addr_ok),
        .ic_ret_valid(ic_ret_valid),
        .ic_ret_last(ic_ret_last),
        .ic_ret_data(ic_ret_data),
        .dc_refill_req(1'b0),
        .dc_refill_addr(32'b0),
        .dc_refill_addr_ok(),
        .dc_ret_valid(),
        .dc_ret_last(),
        .dc_ret_data(),
        .inst_req(ic_uncache_req),
        .inst_size(2'd2),
        .inst_addr(ic_uncache_addr),
        .inst_addr_ok(ic_uncache_addr_ok),
        .inst_data_ok(ic_uncache_data_ok),
        .inst_rdata(ic_uncache_data),
        .data_req(data_req),
        .data_wr(data_wr),
        .data_size(data_size),
        .data_wstrb(data_wstrb),
        .data_addr(data_addr),
        .data_wdata(data_wdata),
        .data_addr_ok(data_addr_ok),
        .data_data_ok(data_data_ok),
        .data_rdata(data_rdata),
        .dc_writeback_req(dc_writeback_req),
        .dc_writeback_addr(dc_writeback_addr),
        .dc_writeback_data(dc_writeback_data),
        .dc_writeback_addr_ok(dc_writeback_addr_ok),
        .dc_writeback_done(dc_writeback_done),
        .axi_fault(axi_fault),
        .stat_ar_transactions(stat_ar_transactions),
        .stat_r_beats(stat_r_beats),
        .stat_aw_transactions(stat_aw_transactions),
        .stat_w_beats(stat_w_beats),
        .stat_b_responses(stat_b_responses),
        .arid(arid),
        .araddr(araddr),
        .arlen(arlen),
        .arsize(arsize),
        .arburst(arburst),
        .arlock(arlock),
        .arcache(arcache),
        .arprot(arprot),
        .arvalid(arvalid),
        .arready(arready),
        .rid(rid),
        .rdata(rdata),
        .rresp(rresp),
        .rlast(rlast),
        .rvalid(rvalid),
        .rready(rready),
        .awid(awid),
        .awaddr(awaddr),
        .awlen(awlen),
        .awsize(awsize),
        .awburst(awburst),
        .awlock(awlock),
        .awcache(awcache),
        .awprot(awprot),
        .awvalid(awvalid),
        .awready(awready),
        .wid(wid),
        .wdata(wdata),
        .wstrb(wstrb),
        .wlast(wlast),
        .wvalid(wvalid),
        .wready(wready),
        .bid(bid),
        .bresp(bresp),
        .bvalid(bvalid),
        .bready(bready)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!resetn)
            data_done_seen <= 1'b0;
        else if (data_data_ok)
            data_done_seen <= 1'b1;
    end

    task wait_cpu_ready;
        integer n;
        begin
            n = 0;
            while (!cpu_addr_ok && n < 200) begin
                @(negedge clk);
                n = n + 1;
            end
            if (!cpu_addr_ok) $fatal(1, "DIRECTED_FAIL=icache_reset_clear_timeout");
        end
    endtask

    task issue_cpu(input reg cacheable, input [31:0] address);
        begin
            wait_cpu_ready();
            @(negedge clk);
            cpu_req = 1'b1;
            cpu_cacheable = cacheable;
            cpu_addr = address;
            @(posedge clk);
            if (!cpu_addr_ok) $fatal(1, "DIRECTED_FAIL=icache_cpu_accept");
            cpu_accepts = cpu_accepts + 1;
            @(negedge clk);
            cpu_req = 1'b0;
        end
    endtask

    task wait_cpu_result(input [31:0] wanted);
        integer n;
        reg done;
        begin
            n = 0;
            done = cpu_data_ok;
            while (!done && n < 2000) begin
                @(negedge clk);
                done = cpu_data_ok;
                n = n + 1;
            end
            if (!done) $fatal(1, "DIRECTED_FAIL=icache_cpu_data_timeout");
            if (cpu_rdata !== wanted)
                $fatal(1, "DIRECTED_FAIL=icache_data_expected_%08x_actual_%08x",
                       wanted, cpu_rdata);
            cpu_completions = cpu_completions + 1;
        end
    endtask

    task accept_ar(
        input [31:0] wanted_addr,
        input [7:0] wanted_len,
        input [3:0] wanted_id,
        input [2:0] wanted_prot
    );
        integer n;
        begin
            arready = 1'b0;
            n = 0;
            while (!arvalid && n < 1000) begin
                @(negedge clk);
                n = n + 1;
            end
            if (!arvalid) $fatal(1, "DIRECTED_FAIL=arvalid_timeout");
            if (araddr !== wanted_addr || arlen !== wanted_len ||
                arid !== wanted_id || arsize !== 3'b010 ||
                arburst !== 2'b01 || arprot !== wanted_prot)
                $fatal(1, "DIRECTED_FAIL=ar_payload addr=%08x len=%0d id=%x size=%x burst=%x prot=%x",
                       araddr, arlen, arid, arsize, arburst, arprot);
            ar_hold_addr = araddr;
            ar_hold_len = arlen;
            ar_hold_id = arid;
            repeat (3) begin
                @(posedge clk);
                if (!arvalid || araddr !== ar_hold_addr ||
                    arlen !== ar_hold_len || arid !== ar_hold_id)
                    $fatal(1, "DIRECTED_FAIL=ar_payload_changed_under_stall");
            end
            @(negedge clk);
            arready = 1'b1;
            @(posedge clk);
            if (!arvalid || !arready) $fatal(1, "DIRECTED_FAIL=ar_handshake");
            @(negedge clk);
            arready = 1'b0;
        end
    endtask

    task send_r_beat(
        input [31:0] value,
        input reg last_value,
        input [3:0] id_value,
        input [1:0] response
    );
        begin
            @(negedge clk);
            rid = id_value;
            rdata = value;
            rresp = response;
            rlast = last_value;
            rvalid = 1'b1;
            @(posedge clk);
            if (!rready) $fatal(1, "DIRECTED_FAIL=r_ready_dropped");
            @(negedge clk);
            rvalid = 1'b0;
            rlast = 1'b0;
        end
    endtask

    task reset_fault_path;
        begin
            @(negedge clk);
            resetn = 1'b0;
            cpu_req = 1'b0;
            arready = 1'b0;
            rvalid = 1'b0;
            rlast = 1'b0;
            repeat (5) @(posedge clk);
            @(negedge clk);
            resetn = 1'b1;
            wait_cpu_ready();
        end
    endtask

    task wait_fault_terminal(input [127:0] case_name);
        integer n;
        begin
            n = 0;
            while ((!axi_fault || !icache_fault) && n < 100) begin
                @(negedge clk);
                n = n + 1;
            end
            if (!axi_fault || !icache_fault || dut_icache.state !== 4'd8 || cpu_data_ok)
                $fatal(1, "DIRECTED_FAIL=fault_not_terminal case=%0s axi=%0d ic=%0d state=%0d data_ok=%0d",
                       case_name, axi_fault, icache_fault, dut_icache.state, cpu_data_ok);
            $display("DIRECTED_FAULT_CASE=%0s accepted=1 completed=0 terminal_state=8", case_name);
        end
    endtask

    task read_icache_line;
        begin
            accept_ar(32'h1fc0_0140, 8'd7, 4'h0, 3'b110);
            for (rbeat_index = 0; rbeat_index < 8; rbeat_index = rbeat_index + 1)
                send_r_beat(32'ha500_0000 + rbeat_index,
                            (rbeat_index == 7), 4'h0, 2'b00);
        end
    endtask

    task wait_data_accept;
        integer n;
        begin
            data_done_seen = 1'b0;
            #1;
            n = 0;
            while (!data_addr_ok && n < 1000) begin
                @(negedge clk);
                n = n + 1;
            end
            if (!data_addr_ok) $fatal(1, "DIRECTED_FAIL=data_addr_accept_timeout");
            data_accepts = data_accepts + 1;
            @(negedge clk);
            data_req = 1'b0;
        end
    endtask

    task wait_data_done(input [31:0] wanted);
        integer n;
        reg done;
        begin
            n = 0;
            done = data_data_ok || data_done_seen;
            while (!done && n < 1000) begin
                @(negedge clk);
                done = data_data_ok || data_done_seen;
                n = n + 1;
            end
            if (!done) $fatal(1, "DIRECTED_FAIL=data_response_timeout");
            if (data_rdata !== wanted)
                $fatal(1, "DIRECTED_FAIL=data_result_expected_%08x_actual_%08x",
                       wanted, data_rdata);
            data_completions = data_completions + 1;
        end
    endtask

    task issue_uncache(input [31:0] address, input [31:0] wanted);
        begin
            issue_cpu(1'b0, address);
            accept_ar(address, 8'd0, 4'h2, 3'b110);
            send_r_beat(wanted, 1'b1, 4'h2, 2'b00);
            wait_cpu_result(wanted);
        end
    endtask

    initial begin
        clk = 1'b0;
        resetn = 1'b0;
        cpu_req = 1'b0;
        cpu_cacheable = 1'b1;
        cpu_addr = 32'b0;
        data_req = 1'b0;
        data_wr = 1'b0;
        data_size = 2'd2;
        data_wstrb = 4'b0;
        data_addr = 32'b0;
        data_wdata = 32'b0;
        dc_writeback_req = 1'b0;
        dc_writeback_addr = 32'b0;
        dc_writeback_data = 256'b0;
        arready = 1'b0;
        rid = 4'b0;
        rdata = 32'b0;
        rresp = 2'b0;
        rlast = 1'b0;
        rvalid = 1'b0;
        awready = 1'b0;
        wready = 1'b0;
        bid = 4'b0;
        bresp = 2'b0;
        bvalid = 1'b0;
        cpu_accepts = 0;
        cpu_completions = 0;
        data_accepts = 0;
        data_completions = 0;
        wb_accepts = 0;
        wb_completions = 0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;
        wait_cpu_ready();

        issue_cpu(1'b1, 32'h1fc0_0154);
        while (!ic_refill_req) @(negedge clk);
        data_req = 1'b1;
        data_wr = 1'b0;
        data_size = 2'd2;
        data_addr = 32'h0000_1234;
        accept_ar(32'h1fc0_0140, 8'd7, 4'h0, 3'b110);
        if (data_addr_ok)
            $fatal(1, "DIRECTED_FAIL=second_owner_claimed_during_refill");
        for (rbeat_index = 0; rbeat_index < 8; rbeat_index = rbeat_index + 1)
            send_r_beat(32'ha500_0000 + rbeat_index,
                        (rbeat_index == 7), 4'h0, 2'b00);
        wait_cpu_result(32'ha500_0005);
        wait_data_accept();
        accept_ar(32'h0000_1234, 8'd0, 4'h3, 3'b010);
        send_r_beat(32'hd00d_1234, 1'b1, 4'h3, 2'b00);
        wait_data_done(32'hd00d_1234);
        if (stat_ar_transactions != 2 || stat_r_beats != 9)
            $fatal(1, "DIRECTED_FAIL=concurrent_read_owner_metrics ar=%0d r=%0d",
                   stat_ar_transactions, stat_r_beats);
        $display("WAVE_CASE=ICACHE_8_BEAT_REFILL_AND_DATA_ARBITRATION time=%0t", $time);

        issue_cpu(1'b1, 32'h1fc0_0148);
        wait_cpu_result(32'ha500_0002);
        if (stat_ar_transactions != 2 || ic_stat_hit != 1 ||
            ic_stat_miss != 1 || ic_stat_refill != 1)
            $fatal(1, "DIRECTED_FAIL=icache_hit_statistics");
        $display("WAVE_CASE=ICACHE_SAME_LINE_HIT time=%0t", $time);

        issue_uncache(32'h1faf_8000, 32'hcafe_babe);
        issue_uncache(32'h1faf_8000, 32'hface_1234);
        if (stat_ar_transactions != 4 || stat_r_beats != 11 ||
            ic_stat_miss != 1 || ic_stat_uncache_read != 2)
            $fatal(1, "DIRECTED_FAIL=uncache_bypass_statistics");
        $display("WAVE_CASE=KSEG1_UNCACHE_SINGLE_BEAT time=%0t", $time);

        dc_writeback_addr = 32'h0000_20a0;
        for (i = 0; i < 8; i = i + 1)
            dc_writeback_data[i*32 +: 32] = 32'hb600_0000 + i;
        dc_writeback_req = 1'b1;
        #1;
        timeout = 0;
        while (!dc_writeback_addr_ok && timeout < 1000) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (!dc_writeback_addr_ok) $fatal(1, "DIRECTED_FAIL=writeback_accept_timeout");
        wb_accepts = wb_accepts + 1;
        @(negedge clk);
        dc_writeback_req = 1'b0;
        wready = 1'b1;
        w_seen = 8'b0;
        for (i = 0; i < 8; i = i + 1) begin
            timeout = 0;
            while (!wvalid && timeout < 1000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!wvalid || wid !== 4'h1 || wdata !== (32'hb600_0000 + i) ||
                wstrb !== 4'b1111 || wlast !== (i == 7))
                $fatal(1, "DIRECTED_FAIL=writeback_beat_%0d", i);
            @(posedge clk);
            if (!wvalid || !wready) $fatal(1, "DIRECTED_FAIL=writeback_w_handshake");
            @(negedge clk);
            w_seen[i] = 1'b1;
        end
        if (w_seen !== 8'hff) $fatal(1, "DIRECTED_FAIL=writeback_beat_count");
        wready = 1'b0;
        if (awvalid !== 1'b1 || awaddr !== 32'h0000_20a0 ||
            awlen !== 8'd7 || awid !== 4'h1 || awsize !== 3'b010)
            $fatal(1, "DIRECTED_FAIL=writeback_aw_payload");
        aw_hold_addr = awaddr;
        aw_hold_len = awlen;
        repeat (3) begin
            @(posedge clk);
            if (!awvalid || awaddr !== aw_hold_addr || awlen !== aw_hold_len)
                $fatal(1, "DIRECTED_FAIL=aw_payload_changed_under_stall");
        end
        @(negedge clk);
        awready = 1'b1;
        @(posedge clk);
        if (!awvalid || !awready) $fatal(1, "DIRECTED_FAIL=aw_handshake");
        @(negedge clk);
        awready = 1'b0;
        bid = 4'h1;
        bresp = 2'b00;
        bvalid = 1'b1;
        @(posedge clk);
        if (!bready || !dc_writeback_done)
            $fatal(1, "DIRECTED_FAIL=writeback_b_completion");
        wb_completions = wb_completions + 1;
        @(negedge clk);
        bvalid = 1'b0;
        if (stat_aw_transactions != 1 || stat_w_beats != 8 ||
            stat_b_responses != 1)
            $fatal(1, "DIRECTED_FAIL=writeback_metrics");
        $display("WAVE_CASE=DIRTY_WRITEBACK_8_BEATS_AND_B time=%0t", $time);

        data_req = 1'b1;
        data_wr = 1'b1;
        data_size = 2'd2;
        data_addr = 32'h1faf_8004;
        data_wstrb = 4'b0101;
        data_wdata = 32'h1234_5678;
        awready = 1'b0;
        wready = 1'b0;
        wait_data_accept();
        timeout = 0;
        while (!awvalid && timeout < 1000) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (!awvalid || awaddr !== 32'h1faf_8004 || awlen !== 0 ||
            awid !== 4'h3 || awsize !== 3'b010)
            $fatal(1, "DIRECTED_FAIL=uncache_store_aw_payload");
        repeat (2) begin
            @(posedge clk);
            if (!awvalid || awaddr !== 32'h1faf_8004 || awlen !== 0)
                $fatal(1, "DIRECTED_FAIL=uncache_aw_stability");
        end
        @(negedge clk);
        awready = 1'b1;
        @(posedge clk);
        if (!awvalid || !awready)
            $fatal(1, "DIRECTED_FAIL=uncache_aw_handshake");
        @(negedge clk);
        awready = 1'b0;
        wready = 1'b1;
        @(posedge clk);
        if (!wvalid || wid !== 4'h3 || wdata !== 32'h1234_5678 ||
            wstrb !== 4'b0101 || !wlast)
            $fatal(1, "DIRECTED_FAIL=uncache_store_w_payload");
        @(negedge clk);
        wready = 1'b0;
        bid = 4'h3;
        bresp = 2'b00;
        bvalid = 1'b1;
        @(posedge clk);
        if (!bready || !data_data_ok)
            $fatal(1, "DIRECTED_FAIL=uncache_store_b_completion");
        data_completions = data_completions + 1;
        @(negedge clk);
        bvalid = 1'b0;
        if (stat_aw_transactions != 2 || stat_w_beats != 9 ||
            stat_b_responses != 2)
            $fatal(1, "DIRECTED_FAIL=uncache_store_metrics");
        $display("WAVE_CASE=UNCACHE_STORE_AW_W_INDEPENDENT time=%0t", $time);

        if (cpu_accepts != cpu_completions || data_accepts != data_completions ||
            wb_accepts != wb_completions)
            $fatal(1, "DIRECTED_FAIL=completion_accounting cpu=%0d/%0d data=%0d/%0d wb=%0d/%0d",
                   cpu_accepts, cpu_completions, data_accepts, data_completions,
                   wb_accepts, wb_completions);
        if (axi_fault || icache_fault)
            $fatal(1, "DIRECTED_FAIL=unexpected_bridge_or_icache_fault");
        $display("DIRECTED_COUNTS_VALID cpu=%0d/%0d data=%0d/%0d writeback=%0d/%0d",
                 cpu_accepts, cpu_completions, data_accepts, data_completions,
                 wb_accepts, wb_completions);

        issue_cpu(1'b0, 32'h1faf_9000);
        accept_ar(32'h1faf_9000, 8'd0, 4'h2, 3'b110);
        send_r_beat(32'hbad0_0000, 1'b1, 4'hf, 2'b00);
        timeout = 0;
        while ((!axi_fault || !icache_fault) && timeout < 100) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (!axi_fault || !icache_fault || dut_icache.state !== 4'd8 || cpu_data_ok)
            $fatal(1, "DIRECTED_FAIL=icache_fault_not_terminal axi=%0d ic=%0d state=%0d data_ok=%0d",
                   axi_fault, icache_fault, dut_icache.state, cpu_data_ok);
        $display("WAVE_CASE=RID_MISMATCH_STICKY_AXI_FAULT time=%0t", $time);
        $display("DIRECTED_FAULT_CASE=RID_MISMATCH accepted=1 completed=0 terminal_state=8");
        $display("DIRECTED_FAULT_INJECTION=RID_MISMATCH accepted=%0d completed=%0d expected_pending=1 axi_fault=%0d icache_fault=%0d terminal_state=%0d",
                 cpu_accepts - 4, cpu_completions - 4, axi_fault, icache_fault,
                 dut_icache.state);

        reset_fault_path();
        issue_cpu(1'b0, 32'h1faf_a000);
        accept_ar(32'h1faf_a000, 8'd0, 4'h2, 3'b110);
        send_r_beat(32'hbad0_1000, 1'b1, 4'h2, 2'b10);
        wait_fault_terminal("RRESP_ERROR");

        reset_fault_path();
        issue_cpu(1'b1, 32'h1fc0_0240);
        timeout = 0;
        while (!ic_refill_req && timeout < 100) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (!ic_refill_req) $fatal(1, "DIRECTED_FAIL=early_rlast_refill_request_timeout");
        accept_ar(32'h1fc0_0240, 8'd7, 4'h0, 3'b110);
        send_r_beat(32'hbabe_0000, 1'b1, 4'h0, 2'b00);
        wait_fault_terminal("RLAST_EARLY");

        reset_fault_path();
        issue_cpu(1'b1, 32'h1fc0_0340);
        timeout = 0;
        while (!ic_refill_req && timeout < 100) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (!ic_refill_req) $fatal(1, "DIRECTED_FAIL=missing_rlast_refill_request_timeout");
        accept_ar(32'h1fc0_0340, 8'd7, 4'h0, 3'b110);
        for (rbeat_index = 0; rbeat_index < 8; rbeat_index = rbeat_index + 1)
            send_r_beat(32'hface_0000 + rbeat_index, 1'b0, 4'h0, 2'b00);
        wait_fault_terminal("RLAST_MISSING");

        $display("DIRECTED_CHECKS=28");
        $display("DIRECTED_FAULT_CASES=4 RID_MISMATCH,RRESP_ERROR,RLAST_EARLY,RLAST_MISSING");
        $display("DIRECTED_AXI ar=%0d r=%0d aw=%0d w=%0d b=%0d",
                 stat_ar_transactions, stat_r_beats, stat_aw_transactions,
                 stat_w_beats, stat_b_responses);
        $display("DIRECTED_PASS");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "DIRECTED_FAIL=watchdog_timeout");
    end
endmodule
