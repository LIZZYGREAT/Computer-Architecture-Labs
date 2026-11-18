`timescale 1ns/1ps
`include "mycpu.h"

module tb_lab19_if_redirect_directed;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg ds_allowin = 1'b1;
    reg br_taken = 1'b0;
    reg [31:0] br_target = 32'b0;
    reg br_delay_slot = 1'b0;
    wire [33:0] br_bus = {br_taken, br_target, br_delay_slot};
    reg trap_redirect = 1'b0;
    reg eret_redirect = 1'b0;
    reg cache_redirect = 1'b0;
    reg tlb_redirect = 1'b0;
    reg cache_resume_valid = 1'b0;
    reg [31:0] cache_resume_pc = 32'b0;
    reg [31:0] trap_vector = 32'hbfc0_0380;
    reg [31:0] eret_target = 32'b0;
    wire fs_to_ds_valid;
    wire [`FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus;
    wire inst_sram_req;
    wire inst_sram_wr;
    wire [1:0] inst_sram_size;
    wire [3:0] inst_sram_wstrb;
    wire [31:0] inst_sram_addr;
    wire [31:0] inst_sram_wdata;
    reg inst_sram_addr_ok = 1'b0;
    reg inst_sram_data_ok = 1'b0;
    reg [31:0] inst_sram_rdata = 32'b0;
    integer checks = 0;

    always #5 clk = ~clk;

    if_stage dut (
        .clk(clk), .reset(reset), .ds_allowin(ds_allowin), .br_bus(br_bus),
        .trap_redirect(trap_redirect), .eret_redirect(eret_redirect),
        .cache_redirect(cache_redirect), .tlb_redirect(tlb_redirect),
        .cache_resume_valid(cache_resume_valid), .cache_resume_pc(cache_resume_pc),
        .trap_vector(trap_vector), .eret_target(eret_target),
        .fs_to_ds_valid(fs_to_ds_valid), .fs_to_ds_bus(fs_to_ds_bus),
        .inst_sram_req(inst_sram_req), .inst_sram_wr(inst_sram_wr),
        .inst_sram_size(inst_sram_size), .inst_sram_wstrb(inst_sram_wstrb),
        .inst_sram_addr(inst_sram_addr), .inst_sram_wdata(inst_sram_wdata),
        .inst_sram_addr_ok(inst_sram_addr_ok),
        .inst_sram_data_ok(inst_sram_data_ok), .inst_sram_rdata(inst_sram_rdata)
    );

    task reset_if;
        begin
            @(negedge clk); reset = 1'b1;
            trap_redirect = 1'b0; eret_redirect = 1'b0;
            cache_redirect = 1'b0; tlb_redirect = 1'b0;
            cache_resume_valid = 1'b0;
            inst_sram_addr_ok = 1'b0; inst_sram_data_ok = 1'b0;
            br_taken = 1'b0; br_delay_slot = 1'b0;
            repeat (2) @(posedge clk);
            @(negedge clk); reset = 1'b0;
        end
    endtask

    task redirect_to(input [31:0] pc);
        begin
            @(negedge clk);
            trap_vector = pc;
            trap_redirect = 1'b1;
            @(posedge clk); #1;
            trap_redirect = 1'b0;
            if (dut.request_pc !== pc || dut.state !== 2'd0)
                $fatal(1, "IF_REPLAY_FAIL=initial_redirect pc=%08x actual=%08x", pc, dut.request_pc);
        end
    endtask

    task test_branch_slot(input reg taken, input [31:0] target, input [31:0] next_pc);
        reg [31:0] slot_pc;
        begin
            reset_if();
            slot_pc = 32'hbfc0_1000;
            redirect_to(slot_pc);
            @(negedge clk);
            br_taken = taken;
            br_target = target;
            br_delay_slot = 1'b1;
            inst_sram_addr_ok = 1'b1;
            inst_sram_data_ok = 1'b1;
            inst_sram_rdata = 32'h2402_0001;
            @(posedge clk); #1;
            inst_sram_addr_ok = 1'b0;
            inst_sram_data_ok = 1'b0;
            br_delay_slot = 1'b0;
            br_taken = 1'b0;
            if (!fs_to_ds_valid || dut.response_pc !== slot_pc ||
                dut.response_inst !== 32'h2402_0001 || !dut.response_is_delay_slot)
                $fatal(1, "IF_REPLAY_FAIL=delay_slot_taken_%0d", taken);
            @(posedge clk); #1;
            if (inst_sram_addr !== next_pc || !inst_sram_req)
                $fatal(1, "IF_REPLAY_FAIL=branch_next_taken_%0d expected=%08x actual=%08x",
                       taken, next_pc, inst_sram_addr);
            checks = checks + 1;
            $display("IF_BRANCH_SLOT_PASS taken=%0d slot_pc=%08x next_pc=%08x", taken, slot_pc, next_pc);
        end
    endtask

    task test_stale_redirect(input reg tlb_change);
        reg [31:0] old_pc;
        reg [31:0] resume_pc;
        begin
            reset_if();
            old_pc = 32'h0040_1000;
            resume_pc = tlb_change ? old_pc : 32'h0040_2000;
            redirect_to(old_pc);
            @(negedge clk);
            // An accepted fetch remains unanswered while the mapping or
            // cache-maintenance commit redirects the front end.
            inst_sram_addr_ok = 1'b1;
            inst_sram_data_ok = 1'b0;
            br_taken = 1'b1;
            br_target = 32'h0040_3000;
            br_delay_slot = 1'b1;
            @(posedge clk); #1;
            inst_sram_addr_ok = 1'b0;
            br_taken = 1'b0;
            br_delay_slot = 1'b0;
            if (dut.state !== 2'd1) $fatal(1, "IF_REPLAY_FAIL=fetch_not_outstanding");

            @(negedge clk);
            cache_resume_valid = 1'b1;
            cache_resume_pc = resume_pc;
            if (tlb_change) tlb_redirect = 1'b1;
            else cache_redirect = 1'b1;
            @(posedge clk); #1;
            cache_redirect = 1'b0;
            tlb_redirect = 1'b0;
            if (!dut.stale_response || dut.restart_pc !== resume_pc || fs_to_ds_valid)
                $fatal(1, "IF_REPLAY_FAIL=redirect_not_latched tlb=%0d restart=%08x",
                       tlb_change, dut.restart_pc);

            @(negedge clk);
            cache_resume_valid = 1'b0;
            inst_sram_data_ok = 1'b1;
            inst_sram_rdata = 32'hdead_beef;
            @(posedge clk); #1;
            inst_sram_data_ok = 1'b0;
            if (fs_to_ds_valid || dut.response_valid || dut.request_pc !== resume_pc ||
                dut.state !== 2'd0 || !inst_sram_req || inst_sram_addr !== resume_pc ||
                dut.delay_slot_pending || dut.branch_target_valid)
                $fatal(1, "IF_REPLAY_FAIL=stale_response_exposed tlb=%0d pc=%08x valid=%0d",
                       tlb_change, inst_sram_addr, fs_to_ds_valid);
            checks = checks + 1;
            if (tlb_change)
                $display("IF_STALE_RESPONSE_DROPPED kind=TLB_WRITE old_pc=%08x replay_pc=%08x delay_slot_cleared=1",
                         old_pc, resume_pc);
            else
                $display("IF_STALE_RESPONSE_DROPPED kind=CACHE_MAINT old_pc=%08x replay_pc=%08x delay_slot_cleared=1",
                         old_pc, resume_pc);

            // The replay request must deliver the instruction associated
            // with the new translation/cache state, not the stale payload.
            @(negedge clk);
            inst_sram_addr_ok = 1'b1;
            @(posedge clk); #1;
            inst_sram_addr_ok = 1'b0;
            @(negedge clk);
            inst_sram_data_ok = 1'b1;
            inst_sram_rdata = 32'h1234_5678;
            @(posedge clk); #1;
            inst_sram_data_ok = 1'b0;
            if (!fs_to_ds_valid || dut.response_pc !== resume_pc ||
                dut.response_inst !== 32'h1234_5678)
                $fatal(1, "IF_REPLAY_FAIL=replay_result tlb=%0d pc=%08x inst=%08x",
                       tlb_change, dut.response_pc, dut.response_inst);
            checks = checks + 1;
        end
    endtask

    initial begin
        test_branch_slot(1'b1, 32'hbfc0_2000, 32'hbfc0_2000);
        test_branch_slot(1'b0, 32'hbfc0_2000, 32'hbfc0_1004);
        test_stale_redirect(1'b0);
        test_stale_redirect(1'b1);

        reset_if();
        @(negedge clk);
        trap_vector = 32'hbfc0_0380;
        cache_resume_valid = 1'b1;
        cache_resume_pc = 32'h0040_4000;
        cache_redirect = 1'b1;
        tlb_redirect = 1'b1;
        trap_redirect = 1'b1;
        @(posedge clk); #1;
        trap_redirect = 1'b0; cache_redirect = 1'b0; tlb_redirect = 1'b0;
        cache_resume_valid = 1'b0;
        if (dut.request_pc !== 32'hbfc0_0380)
            $fatal(1, "IF_REPLAY_FAIL=trap_priority pc=%08x", dut.request_pc);
        checks = checks + 1;
        $display("IF_REDIRECT_PRIORITY_PASS trap_over_eret_cache_tlb=1");
        $display("LAB19_IF_REDIRECT_PASS checks=%0d", checks);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "IF_REPLAY_FAIL=watchdog_timeout");
    end
endmodule
