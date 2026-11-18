`timescale 1ns/1ps

module lab17_functional_check #(
    parameter ICACHE_ENABLE = 1'b1
);
    reg resetn = 1'b0;
    reg clk = 1'b0;
    wire [15:0] led;
    wire [1:0] led_rg0;
    wire [1:0] led_rg1;
    wire [7:0] num_csn;
    wire [6:0] num_a_g;
    wire [3:0] btn_key_col;
    reg [7:0] switch = 8'hff;
    reg [3:0] btn_key_row = 4'd0;
    reg [1:0] btn_step = 2'd3;

    reg [31:0] last_num_data = 32'b0;
    integer score_points = 0;
    integer cycles = 0;
    integer accepted_data = 0;
    integer completed_data = 0;
    integer accepted_stores = 0;
    integer completed_stores = 0;
    integer pending_data = 0;
    integer pending_store = 0;

    always #5 clk = ~clk;

    initial begin
        #2000;
        resetn = 1'b1;
    end

    soc_axi_lite_top #(
        .SIMULATION(1'b1),
        .ICACHE_ENABLE(ICACHE_ENABLE)
    ) soc_lite (
        .resetn(resetn),
        .clk(clk),
        .led(led),
        .led_rg0(led_rg0),
        .led_rg1(led_rg1),
        .num_csn(num_csn),
        .num_a_g(num_a_g),
        .switch(switch),
        .btn_key_col(btn_key_col),
        .btn_key_row(btn_key_row),
        .btn_step(btn_step)
    );

    // The reference program writes (test number << 24) | score once per test.
    always @(posedge clk) begin
        if (resetn) begin
            if (soc_lite.u_cpu.data_sram_req && soc_lite.u_cpu.data_sram_addr_ok) begin
                if (pending_data)
                    $fatal(1, "LAB17_FAIL=overlapping_data_requests");
                pending_data = 1;
                pending_store = soc_lite.u_cpu.data_sram_wr;
                accepted_data = accepted_data + 1;
                if (pending_store)
                    accepted_stores = accepted_stores + 1;
            end
            if (soc_lite.u_cpu.data_sram_data_ok) begin
                if (!pending_data)
                    $fatal(1, "LAB17_FAIL=duplicate_or_unmatched_data_response");
                completed_data = completed_data + 1;
                if (pending_store)
                    completed_stores = completed_stores + 1;
                pending_data = 0;
                pending_store = 0;
            end
        end else begin
            pending_data = 0;
            pending_store = 0;
        end
    end

    always @(posedge clk) begin
        #1;
        if (!resetn) begin
            last_num_data = 32'b0;
            score_points = 0;
        end else if (soc_lite.u_confreg.num_data !== last_num_data) begin
            if (soc_lite.u_confreg.num_data[7:0] !== last_num_data[7:0] + 8'd1)
                $fatal(1, "LAB17_FAIL=score_sequence low_expected=%02x observed=%02x",
                       last_num_data[7:0] + 8'd1, soc_lite.u_confreg.num_data[7:0]);
            if (soc_lite.u_confreg.num_data[31:24] !== last_num_data[31:24] + 8'd1)
                $fatal(1, "LAB17_FAIL=test_sequence high_expected=%02x observed=%02x",
                       last_num_data[31:24] + 8'd1,
                       soc_lite.u_confreg.num_data[31:24]);
            if (soc_lite.u_confreg.num_data[23:8] !== 16'b0)
                $fatal(1, "LAB17_FAIL=score_reserved_bits value=%04x",
                       soc_lite.u_confreg.num_data[23:8]);
            last_num_data = soc_lite.u_confreg.num_data;
            score_points = score_points + 1;
            $display("LAB17_TESTPOINT=%0d VALUE=%08x", score_points, last_num_data);
        end
    end

    initial begin
        repeat (20_000_000) begin
            @(posedge clk);
            #2;
            cycles = cycles + 1;
            if ((led_rg0 === 2'b01) && (led_rg1 === 2'b01)) begin
                if (soc_lite.u_confreg.num_data !== 32'h5e00_005e ||
                    score_points != 94)
                    $fatal(1, "LAB17_FAIL=score_mismatch num_data=%08x points=%0d",
                           soc_lite.u_confreg.num_data, score_points);
                // CONFREG exposes the LED write before the corresponding AXI B
                // response retires through MEM. Let that final request drain.
                if (!pending_data && accepted_data == completed_data &&
                    accepted_stores == completed_stores) begin
                    if (soc_lite.u_cpu.axi_fault || soc_lite.u_cpu.icache_fault)
                        $fatal(1, "LAB17_FAIL=cache_or_axi_fault");
                    if (ICACHE_ENABLE) begin
                        if (soc_lite.u_cpu.ic_stat_hit == 0 ||
                            soc_lite.u_cpu.ic_stat_miss == 0 ||
                            soc_lite.u_cpu.ic_stat_refill == 0 ||
                            soc_lite.u_cpu.ic_stat_uncache_read == 0)
                            $fatal(1, "LAB17_FAIL=cache_statistics_missing");
                    end else if (soc_lite.u_cpu.ic_stat_hit != 0 ||
                                 soc_lite.u_cpu.ic_stat_miss != 0 ||
                                 soc_lite.u_cpu.ic_stat_refill != 0 ||
                                 soc_lite.u_cpu.ic_stat_uncache_read == 0) begin
                        $fatal(1, "LAB17_FAIL=uncached_baseline_statistics");
                    end

                    $display("CACHE_STATS ic_hit=%0d ic_miss=%0d ic_refill=%0d ic_uncache_read=%0d",
                             soc_lite.u_cpu.ic_stat_hit, soc_lite.u_cpu.ic_stat_miss,
                             soc_lite.u_cpu.ic_stat_refill,
                             soc_lite.u_cpu.ic_stat_uncache_read);
                    $display("AXI_METRICS ar=%0d r=%0d aw=%0d w=%0d b=%0d",
                             soc_lite.u_cpu.axi_stat_ar_transactions,
                             soc_lite.u_cpu.axi_stat_r_beats,
                             soc_lite.u_cpu.axi_stat_aw_transactions,
                             soc_lite.u_cpu.axi_stat_w_beats,
                             soc_lite.u_cpu.axi_stat_b_responses);
                    $display("STORE_COUNTS accepted=%0d completed=%0d duplicate_store=0",
                             accepted_stores, completed_stores);
                    if (ICACHE_ENABLE)
                        $display("LAB17_ICACHE_FUNCTIONAL_PASS score=94/94 cycles=%0d", cycles);
                    else
                        $display("LAB17_BASELINE_FUNCTIONAL_PASS score=94/94 cycles=%0d", cycles);
                    $finish;
                end
            end
            if ((led_rg0 === 2'b10) && (led_rg1 === 2'b10))
                $fatal(1, "LAB17_FAIL=software_failure num_data=%08x",
                       soc_lite.u_confreg.num_data);
        end
        $fatal(1, "LAB17_FAIL=watchdog_timeout pc=%08x num_data=%08x",
               soc_lite.debug_wb_pc, soc_lite.u_confreg.num_data);
    end
endmodule

module tb_lab17_icache;
    lab17_functional_check #(.ICACHE_ENABLE(1'b1)) check();
endmodule

module tb_lab17_baseline;
    lab17_functional_check #(.ICACHE_ENABLE(1'b0)) check();
endmodule
