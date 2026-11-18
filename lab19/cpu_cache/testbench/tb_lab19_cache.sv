`timescale 1ns/1ps

module tb_lab19_cache;
    reg resetn = 1'b0;
    reg clk = 1'b0;
    wire [15:0] led;
    wire [1:0] led_rg0;
    wire [1:0] led_rg1;
    wire [7:0] num_csn;
    wire [6:0] num_a_g;
    reg [7:0] switch = 8'hff;
    reg [3:0] btn_key_row = 4'd0;
    reg [1:0] btn_step = 2'd3;
    wire [3:0] btn_key_col;

    integer cycles = 0;
    integer score_points = 0;
    integer retired_instructions = 0;
    integer accepted_data = 0;
    integer completed_data = 0;
    integer accepted_stores = 0;
    integer completed_stores = 0;
    integer pending_data = 0;
    integer pending_store = 0;
    integer cache_ops [0:31];
    reg [31:0] last_num_data = 32'b0;
    integer i;

    always #5 clk = ~clk;

    initial begin
        for (i = 0; i < 32; i = i + 1)
            cache_ops[i] = 0;
        #2000 resetn = 1'b1;
    end

    soc_axi_lite_top #(
        .SIMULATION(1'b1),
        .ICACHE_ENABLE(1'b1),
        .DCACHE_ENABLE(1'b1)
    ) soc_lite (
        .resetn(resetn), .clk(clk), .led(led), .led_rg0(led_rg0), .led_rg1(led_rg1),
        .num_csn(num_csn), .num_a_g(num_a_g), .switch(switch),
        .btn_key_col(btn_key_col), .btn_key_row(btn_key_row), .btn_step(btn_step)
    );

    always @(posedge clk) begin
        if (resetn) begin
            cycles = cycles + 1;
            if (soc_lite.u_cpu.ms_to_ws_valid)
                retired_instructions = retired_instructions + 1;
            if (soc_lite.u_cpu.cache_maint_commit) begin
                cache_ops[soc_lite.u_cpu.cache_maint_op] =
                    cache_ops[soc_lite.u_cpu.cache_maint_op] + 1;
                if (soc_lite.u_cpu.data_sram_req)
                    $fatal(1, "LAB19_FAIL=cache_op_issued_data_request");
            end
            if (soc_lite.u_cpu.data_sram_req && soc_lite.u_cpu.data_sram_addr_ok) begin
                if (pending_data)
                    $fatal(1, "LAB19_FAIL=overlapping_data_requests");
                pending_data = 1;
                pending_store = soc_lite.u_cpu.data_sram_wr;
                accepted_data = accepted_data + 1;
                if (pending_store)
                    accepted_stores = accepted_stores + 1;
            end
            if (soc_lite.u_cpu.data_sram_data_ok) begin
                if (!pending_data)
                    $fatal(1, "LAB19_FAIL=duplicate_or_unmatched_data_response");
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
            if (soc_lite.u_confreg.num_data[7:0] !== last_num_data[7:0] + 8'd1 ||
                soc_lite.u_confreg.num_data[31:24] !== last_num_data[31:24] + 8'd1 ||
                soc_lite.u_confreg.num_data[23:8] !== 16'b0)
                $fatal(1, "LAB19_FAIL=score_sequence previous=%08x observed=%08x",
                       last_num_data, soc_lite.u_confreg.num_data);
            last_num_data = soc_lite.u_confreg.num_data;
            score_points = score_points + 1;
            $display("LAB19_TESTPOINT=%0d VALUE=%08x", score_points, last_num_data);
        end
    end

    initial begin
        repeat (20_000_000) begin
            @(posedge clk);
            #2;
            if ((led_rg0 === 2'b01) && (led_rg1 === 2'b01)) begin
                if (soc_lite.u_confreg.num_data !== 32'h0700_0007 || score_points != 7)
                    $fatal(1, "LAB19_FAIL=score_mismatch num_data=%08x points=%0d",
                           soc_lite.u_confreg.num_data, score_points);
                if (!pending_data && accepted_data == completed_data &&
                    accepted_stores == completed_stores) begin
                if (soc_lite.u_cpu.axi_fault || soc_lite.u_cpu.icache_fault ||
                    soc_lite.u_cpu.dcache_fault)
                    $fatal(1, "LAB19_FAIL=cache_or_axi_fault");
                if (cache_ops[5'h00] != 2 || cache_ops[5'h08] != 2 ||
                    cache_ops[5'h10] != 1 || cache_ops[5'h01] != 2 ||
                    cache_ops[5'h09] != 2 || cache_ops[5'h11] != 1 ||
                    cache_ops[5'h15] != 1)
                    $fatal(1, "LAB19_FAIL=cache_operation_counts iidxinv=%0d iidxsttag=%0d ihitinv=%0d didxwbinv=%0d didxsttag=%0d dhitinv=%0d dhitwbinv=%0d",
                           cache_ops[5'h00], cache_ops[5'h08], cache_ops[5'h10],
                           cache_ops[5'h01], cache_ops[5'h09], cache_ops[5'h11],
                           cache_ops[5'h15]);
                if (soc_lite.u_cpu.dc_stat_writeback < 2 ||
                    soc_lite.u_cpu.ic_stat_miss == 0 || soc_lite.u_cpu.dc_stat_miss == 0)
                    $fatal(1, "LAB19_FAIL=cache_maintenance_statistics");
                $display("CACHE_MAINTENANCE_COUNTS ic_idxinv=%0d ic_idxsttag=%0d ic_hitinv=%0d dc_idxwbinv=%0d dc_idxsttag=%0d dc_hitinv=%0d dc_hitwbinv=%0d",
                         cache_ops[5'h00], cache_ops[5'h08], cache_ops[5'h10],
                         cache_ops[5'h01], cache_ops[5'h09], cache_ops[5'h11],
                         cache_ops[5'h15]);
                $display("CACHE_STATS ic_hit=%0d ic_miss=%0d ic_refill=%0d ic_uncache_read=%0d dc_hit=%0d dc_miss=%0d dc_writeback=%0d dc_uncache=%0d",
                         soc_lite.u_cpu.ic_stat_hit, soc_lite.u_cpu.ic_stat_miss,
                         soc_lite.u_cpu.ic_stat_refill, soc_lite.u_cpu.ic_stat_uncache_read,
                         soc_lite.u_cpu.dc_stat_hit, soc_lite.u_cpu.dc_stat_miss,
                         soc_lite.u_cpu.dc_stat_writeback, soc_lite.u_cpu.dc_stat_uncache);
                $display("AXI_METRICS ar=%0d r=%0d aw=%0d w=%0d b=%0d",
                         soc_lite.u_cpu.axi_stat_ar_transactions,
                         soc_lite.u_cpu.axi_stat_r_beats,
                         soc_lite.u_cpu.axi_stat_aw_transactions,
                         soc_lite.u_cpu.axi_stat_w_beats,
                         soc_lite.u_cpu.axi_stat_b_responses);
                $display("STORE_COUNTS accepted=%0d completed=%0d duplicate_store=0",
                         accepted_stores, completed_stores);
                $display("RETIRED_INSTRUCTIONS=%0d", retired_instructions);
                $display("LAB19_CACHE_FUNCTIONAL_PASS score=7/7 cycles=%0d", cycles);
                $finish;
                end
            end
            if ((led_rg0 === 2'b10) && (led_rg1 === 2'b10))
                $fatal(1, "LAB19_FAIL=software_failure num_data=%08x",
                       soc_lite.u_confreg.num_data);
        end
        $fatal(1, "LAB19_FAIL=watchdog_timeout pc=%08x num_data=%08x",
               soc_lite.debug_wb_pc, soc_lite.u_confreg.num_data);
    end
endmodule
