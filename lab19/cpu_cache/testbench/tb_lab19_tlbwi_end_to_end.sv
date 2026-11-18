`timescale 1ns/1ps

module tb_lab19_tlbwi_end_to_end;
    localparam [31:0] TARGET_VA = 32'h0040_0100;
    localparam [31:0] TARGET_PA = 32'h0000_0100;

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

    integer cycles = 0;
    integer tlbwi_commits = 0;
    integer mapped_fetch_accepts = 0;
    integer target_wb_count = 0;

    always #5 clk = ~clk;

    initial begin
        #2000 resetn = 1'b1;
    end

    soc_axi_lite_top #(
        .SIMULATION(1'b1),
        .ICACHE_ENABLE(1'b1),
        .DCACHE_ENABLE(1'b1)
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

    always @(posedge clk) begin
        if (!resetn) begin
            cycles = 0;
            tlbwi_commits = 0;
            mapped_fetch_accepts = 0;
            target_wb_count = 0;
        end else begin
            cycles = cycles + 1;

            if (soc_lite.u_cpu.tlb_commit &&
                soc_lite.u_cpu.tlb_op_commit == 3'b010) begin
                tlbwi_commits = tlbwi_commits + 1;
                if (tlbwi_commits != 1)
                    $fatal(1, "LAB19_TLBWI_E2E_FAIL=duplicate_tlbwi_commit count=%0d",
                           tlbwi_commits);
                if (!soc_lite.u_cpu.tlb_write_enable ||
                    !soc_lite.u_cpu.pipeline_flush ||
                    soc_lite.u_cpu.tlb_w_index !== 4'd0 ||
                    soc_lite.u_cpu.cp0_index[3:0] !== 4'd0 ||
                    soc_lite.u_cpu.cp0_entryhi !== 32'h0040_0000 ||
                    soc_lite.u_cpu.cp0_entrylo0 !== 32'h0000_001e ||
                    soc_lite.u_cpu.cp0_entrylo1 !== 32'h0000_001e)
                    $fatal(1, "LAB19_TLBWI_E2E_FAIL=commit_payload index=%x entryhi=%08x lo0=%08x lo1=%08x flush=%b",
                           soc_lite.u_cpu.cp0_index[3:0],
                           soc_lite.u_cpu.cp0_entryhi,
                           soc_lite.u_cpu.cp0_entrylo0,
                           soc_lite.u_cpu.cp0_entrylo1,
                           soc_lite.u_cpu.pipeline_flush);
                $display("LAB19_TLBWI_COMMIT_OBSERVED pc=%08x index=%x vpn2=%05x lo0=%08x lo1=%08x",
                         soc_lite.u_cpu.mem_stage.ms_pc,
                         soc_lite.u_cpu.tlb_w_index,
                         soc_lite.u_cpu.cp0_entryhi[31:13],
                         soc_lite.u_cpu.cp0_entrylo0,
                         soc_lite.u_cpu.cp0_entrylo1);
                #1;
                if (!soc_lite.u_cpu.u_tlb.entry_valid[0] ||
                    soc_lite.u_cpu.u_tlb.entry_vpn2[0] !== 19'h00200 ||
                    soc_lite.u_cpu.u_tlb.entry_pfn0[0] !== 20'h00000 ||
                    soc_lite.u_cpu.u_tlb.entry_c0[0] !== 3'b011 ||
                    soc_lite.u_cpu.u_tlb.entry_d0[0] !== 1'b1 ||
                    soc_lite.u_cpu.u_tlb.entry_v0[0] !== 1'b1)
                    $fatal(1, "LAB19_TLBWI_E2E_FAIL=tlb_entry_not_installed");
            end

            if (soc_lite.u_cpu.inst_sram_req &&
                soc_lite.u_cpu.inst_sram_addr_ok &&
                soc_lite.u_cpu.inst_sram_addr === TARGET_VA) begin
                mapped_fetch_accepts = mapped_fetch_accepts + 1;
                if (!soc_lite.u_cpu.inst_translation_valid ||
                    !soc_lite.u_cpu.tlb_s0_found ||
                    soc_lite.u_cpu.inst_sram_pa !== TARGET_PA ||
                    !soc_lite.u_cpu.inst_cacheable)
                    $fatal(1, "LAB19_TLBWI_E2E_FAIL=translated_fetch va=%08x pa=%08x valid=%b tlb_found=%b cacheable=%b",
                           soc_lite.u_cpu.inst_sram_addr,
                           soc_lite.u_cpu.inst_sram_pa,
                           soc_lite.u_cpu.inst_translation_valid,
                           soc_lite.u_cpu.tlb_s0_found,
                           soc_lite.u_cpu.inst_cacheable);
                $display("LAB19_TLBWI_MAPPED_FETCH va=%08x pa=%08x tlb_index=%x",
                         soc_lite.u_cpu.inst_sram_addr,
                         soc_lite.u_cpu.inst_sram_pa,
                         soc_lite.u_cpu.tlb_s0_index);
            end

            if (soc_lite.debug_wb_rf_wen != 4'b0 &&
                soc_lite.debug_wb_rf_wnum == 5'd23 &&
                soc_lite.debug_wb_rf_wdata == 32'h0000_0019) begin
                target_wb_count = target_wb_count + 1;
                if (soc_lite.debug_wb_pc !== TARGET_VA)
                    $fatal(1, "LAB19_TLBWI_E2E_FAIL=unexpected_target_value pc=%08x value=%08x",
                           soc_lite.debug_wb_pc, soc_lite.debug_wb_rf_wdata);
            end

            if (soc_lite.u_cpu.axi_fault || soc_lite.u_cpu.icache_fault ||
                soc_lite.u_cpu.dcache_fault)
                $fatal(1, "LAB19_TLBWI_E2E_FAIL=cache_or_axi_fault");

            if (target_wb_count != 0) begin
                if (tlbwi_commits != 1 || mapped_fetch_accepts == 0 ||
                    target_wb_count != 1)
                    $fatal(1, "LAB19_TLBWI_E2E_FAIL=coverage commits=%0d mapped_fetches=%0d target_wb=%0d",
                           tlbwi_commits, mapped_fetch_accepts, target_wb_count);
                $display("LAB19_TLBWI_ARCH_COMMIT_PASS commits=1 index=0 va=00400000 pfn=00000");
                $display("LAB19_TLBWI_MAPPED_FETCH_PASS va=00400100 pa=00000100 target_wb=00400100");
                $display("TLBWI_ARCH_SCOPE=software_mtc0_entryhi_entrylo_index_then_tlbwi_commit_then_translated_if_fetch");
                $display("TLB_REPLAY_SCOPE=stale_outstanding_response_is_separately_checked_by_forced_event_crosscheck");
                $display("LAB19_TLBWI_E2E_PASS cycles=%0d", cycles);
                $finish;
            end
        end
    end

    initial begin
        repeat (200_000) begin
            @(posedge clk);
            #2;
        end
        $fatal(1, "LAB19_TLBWI_E2E_FAIL=watchdog_timeout commits=%0d mapped_fetches=%0d target_wb=%0d pc=%08x",
               tlbwi_commits, mapped_fetch_accepts, target_wb_count,
               soc_lite.debug_wb_pc);
    end
endmodule
