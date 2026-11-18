`timescale 1ns/1ps

module tb_lab19_perf #(
    parameter integer PROGRAM_ID = 0
);
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
    integer retired_instructions = 0;
    integer drain_cycles;

    always #5 clk = ~clk;
    initial #2000 resetn = 1'b1;

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
            if (soc_lite.u_confreg.write_uart_valid)
                $write("%c", soc_lite.u_confreg.write_uart_data);
        end
    end

    initial begin
        repeat (200_000_000) begin
            @(posedge clk);
            #2;
            if ((led_rg0 === 2'b01) && (led_rg1 === 2'b01)) begin
                drain_cycles = 0;
                while ((soc_lite.u_cpu.axi_stat_aw_transactions != soc_lite.u_cpu.axi_stat_b_responses ||
                        soc_lite.u_cpu.axi_stat_w_beats < soc_lite.u_cpu.axi_stat_aw_transactions ||
                        soc_lite.u_cpu.ic_stat_miss != soc_lite.u_cpu.ic_stat_refill ||
                        soc_lite.u_cpu.u_cache_axi3_bridge.rd_state != 2'd0 ||
                        soc_lite.u_cpu.u_dcache.state != 4'd1 ||
                        soc_lite.u_cpu.u_cache_axi3_bridge.wr_state != 2'd0) &&
                       drain_cycles < 256) begin
                    @(posedge clk);
                    #2;
                    drain_cycles = drain_cycles + 1;
                end
                $display("PERF_DRAIN cycles=%0d ic_pending_misses=%0d rd_state=%0d dcache_state=%0d bridge_wr_state=%0d",
                         drain_cycles,
                         soc_lite.u_cpu.ic_stat_miss - soc_lite.u_cpu.ic_stat_refill,
                         soc_lite.u_cpu.u_cache_axi3_bridge.rd_state,
                         soc_lite.u_cpu.u_dcache.state,
                         soc_lite.u_cpu.u_cache_axi3_bridge.wr_state);
                $display("PERF_CACHE_CHECK program=%0d ic_hit=%0d ic_miss=%0d ic_refill=%0d dc_hit=%0d dc_miss=%0d dc_writeback=%0d dc_uncache=%0d",
                         PROGRAM_ID, soc_lite.u_cpu.ic_stat_hit, soc_lite.u_cpu.ic_stat_miss,
                         soc_lite.u_cpu.ic_stat_refill, soc_lite.u_cpu.dc_stat_hit,
                         soc_lite.u_cpu.dc_stat_miss, soc_lite.u_cpu.dc_stat_writeback,
                         soc_lite.u_cpu.dc_stat_uncache);
                if (soc_lite.u_cpu.axi_fault || soc_lite.u_cpu.icache_fault ||
                    soc_lite.u_cpu.dcache_fault)
                    $fatal(1, "LAB19_PERF_FAIL=cache_or_axi_fault program_id=%0d", PROGRAM_ID);
                if (soc_lite.u_cpu.ic_stat_miss == 0 || soc_lite.u_cpu.ic_stat_refill == 0 ||
                    soc_lite.u_cpu.dc_stat_miss == 0)
                    $fatal(1, "LAB19_PERF_FAIL=cache_activity_missing program_id=%0d ic_miss=%0d ic_refill=%0d dc_miss=%0d",
                           PROGRAM_ID, soc_lite.u_cpu.ic_stat_miss,
                           soc_lite.u_cpu.ic_stat_refill, soc_lite.u_cpu.dc_stat_miss);
                if (soc_lite.u_cpu.axi_stat_aw_transactions != soc_lite.u_cpu.axi_stat_b_responses ||
                    soc_lite.u_cpu.axi_stat_w_beats < soc_lite.u_cpu.axi_stat_aw_transactions ||
                    soc_lite.u_cpu.ic_stat_miss != soc_lite.u_cpu.ic_stat_refill ||
                    soc_lite.u_cpu.u_cache_axi3_bridge.rd_state != 2'd0 ||
                    soc_lite.u_cpu.u_dcache.state != 4'd1 ||
                    soc_lite.u_cpu.u_cache_axi3_bridge.wr_state != 2'd0)
                    $fatal(1, "LAB19_PERF_FAIL=transaction_drain program_id=%0d aw=%0d w=%0d b=%0d ic_miss=%0d ic_refill=%0d bridge_rd_state=%0d dcache_state=%0d bridge_wr_state=%0d",
                           PROGRAM_ID, soc_lite.u_cpu.axi_stat_aw_transactions,
                           soc_lite.u_cpu.axi_stat_w_beats, soc_lite.u_cpu.axi_stat_b_responses,
                           soc_lite.u_cpu.ic_stat_miss, soc_lite.u_cpu.ic_stat_refill,
                           soc_lite.u_cpu.u_cache_axi3_bridge.rd_state,
                           soc_lite.u_cpu.u_dcache.state,
                           soc_lite.u_cpu.u_cache_axi3_bridge.wr_state);
                $display("PERF_METRICS program=%0d cycles=%0d retired_instructions=%0d ic_hit=%0d ic_miss=%0d ic_refill=%0d dc_hit=%0d dc_miss=%0d dc_writeback=%0d dc_uncache=%0d axi_ar=%0d axi_r=%0d axi_aw=%0d axi_w=%0d axi_b=%0d simulation_ns=%0d cpu_frequency_hz=100000000 num_data=%08x",
                         PROGRAM_ID, cycles, retired_instructions,
                         soc_lite.u_cpu.ic_stat_hit, soc_lite.u_cpu.ic_stat_miss,
                         soc_lite.u_cpu.ic_stat_refill, soc_lite.u_cpu.dc_stat_hit,
                         soc_lite.u_cpu.dc_stat_miss, soc_lite.u_cpu.dc_stat_writeback,
                         soc_lite.u_cpu.dc_stat_uncache,
                         soc_lite.u_cpu.axi_stat_ar_transactions,
                         soc_lite.u_cpu.axi_stat_r_beats,
                         soc_lite.u_cpu.axi_stat_aw_transactions,
                         soc_lite.u_cpu.axi_stat_w_beats,
                         soc_lite.u_cpu.axi_stat_b_responses,
                         cycles * 10, soc_lite.u_confreg.num_data);
                if (PROGRAM_ID == 0)
                    $display("LAB19_PERF_PASS program=dhrystone");
                else
                    $display("LAB19_PERF_PASS program=coremark");
                $finish;
            end
            if ((led_rg0 === 2'b10) && (led_rg1 === 2'b10))
                $fatal(1, "LAB19_PERF_FAIL=software_failure program_id=%0d num_data=%08x",
                       PROGRAM_ID, soc_lite.u_confreg.num_data);
        end
        $fatal(1, "LAB19_PERF_FAIL=watchdog_timeout program_id=%0d pc=%08x",
               PROGRAM_ID, soc_lite.debug_wb_pc);
    end
endmodule

module tb_lab19_dhrystone;
    tb_lab19_perf #(.PROGRAM_ID(0)) check();
endmodule

module tb_lab19_coremark;
    tb_lab19_perf #(.PROGRAM_ID(1)) check();
endmodule
