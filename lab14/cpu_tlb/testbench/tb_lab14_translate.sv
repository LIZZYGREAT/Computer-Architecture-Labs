`timescale 1ns/1ps

module tb_lab14_translate;
    reg clk = 1'b0;
    reg [31:0] s0_vaddr = 32'b0;
    reg [31:0] s1_vaddr = 32'b0;
    reg [7:0] asid = 8'h12;
    reg is_write = 1'b0;
    reg tlb_we = 1'b0;
    reg [3:0] tlb_w_index = 4'd0;
    reg [18:0] tlb_w_vpn2 = 19'b0;
    reg [7:0] tlb_w_asid = 8'b0;
    reg tlb_w_g = 1'b0;
    reg [19:0] tlb_w_pfn0 = 20'b0;
    reg [2:0] tlb_w_c0 = 3'b0;
    reg tlb_w_d0 = 1'b0;
    reg tlb_w_v0 = 1'b0;
    reg [19:0] tlb_w_pfn1 = 20'b0;
    reg [2:0] tlb_w_c1 = 3'b0;
    reg tlb_w_d1 = 1'b0;
    reg tlb_w_v1 = 1'b0;
    wire s0_found, s0_d, s0_v;
    wire [3:0] s0_index;
    wire [19:0] s0_pfn;
    wire [2:0] s0_c;
    wire s1_found, s1_d, s1_v;
    wire [3:0] s1_index;
    wire [19:0] s1_pfn;
    wire [2:0] s1_c;
    wire [31:0] s0_paddr, s1_paddr;
    wire s0_valid, s0_cacheable;
    wire s1_valid, s1_cacheable;
    wire [18:0] r_vpn2;
    wire [7:0] r_asid;
    wire r_g, r_d0, r_v0, r_d1, r_v1;
    wire [19:0] r_pfn0, r_pfn1;
    wire [2:0] r_c0, r_c1;
    integer checks = 0;

    always #5 clk = ~clk;

    tlb #(.TLBNUM(16)) u_tlb(
        .clk(clk),
        .s0_vpn2(s0_vaddr[31:13]), .s0_odd_page(s0_vaddr[12]), .s0_asid(asid),
        .s0_found(s0_found), .s0_index(s0_index), .s0_pfn(s0_pfn),
        .s0_c(s0_c), .s0_d(s0_d), .s0_v(s0_v),
        .s1_vpn2(s1_vaddr[31:13]), .s1_odd_page(s1_vaddr[12]), .s1_asid(asid),
        .s1_found(s1_found), .s1_index(s1_index), .s1_pfn(s1_pfn),
        .s1_c(s1_c), .s1_d(s1_d), .s1_v(s1_v),
        .we(tlb_we), .w_index(tlb_w_index), .w_vpn2(tlb_w_vpn2),
        .w_asid(tlb_w_asid), .w_g(tlb_w_g),
        .w_pfn0(tlb_w_pfn0), .w_c0(tlb_w_c0), .w_d0(tlb_w_d0), .w_v0(tlb_w_v0),
        .w_pfn1(tlb_w_pfn1), .w_c1(tlb_w_c1), .w_d1(tlb_w_d1), .w_v1(tlb_w_v1),
        .r_index(4'd0), .r_vpn2(r_vpn2), .r_asid(r_asid), .r_g(r_g),
        .r_pfn0(r_pfn0), .r_c0(r_c0), .r_d0(r_d0), .r_v0(r_v0),
        .r_pfn1(r_pfn1), .r_c1(r_c1), .r_d1(r_d1), .r_v1(r_v1)
    );

    addr_translate u_s0_translate(
        .vaddr(s0_vaddr), .is_write(1'b0), .tlb_found(s0_found),
        .tlb_pfn(s0_pfn), .tlb_c(s0_c), .tlb_d(s0_d), .tlb_v(s0_v),
        .paddr(s0_paddr), .translation_valid(s0_valid), .cacheable(s0_cacheable)
    );
    addr_translate u_s1_translate(
        .vaddr(s1_vaddr), .is_write(is_write), .tlb_found(s1_found),
        .tlb_pfn(s1_pfn), .tlb_c(s1_c), .tlb_d(s1_d), .tlb_v(s1_v),
        .paddr(s1_paddr), .translation_valid(s1_valid), .cacheable(s1_cacheable)
    );

    task check;
        input condition;
        input [8*80-1:0] label;
        begin
            if (condition !== 1'b1)
                $fatal(1, "LAB14_TRANSLATE_FAIL %0s", label);
            checks = checks + 1;
            $display("LAB14_TRANSLATE_CHECK=%0d %0s", checks, label);
        end
    endtask

    task write_entry0;
        input global_entry;
        input [7:0] entry_asid;
        input valid0;
        input dirty0;
        begin
            @(negedge clk);
            tlb_we = 1'b1;
            tlb_w_index = 4'd0;
            tlb_w_vpn2 = 19'h00201;
            tlb_w_asid = entry_asid;
            tlb_w_g = global_entry;
            tlb_w_pfn0 = 20'h12345;
            tlb_w_c0 = 3'b011;
            tlb_w_d0 = dirty0;
            tlb_w_v0 = valid0;
            tlb_w_pfn1 = 20'h23456;
            tlb_w_c1 = 3'b011;
            tlb_w_d1 = 1'b1;
            tlb_w_v1 = 1'b1;
            @(negedge clk);
            tlb_we = 1'b0;
            #1;
        end
    endtask

    initial begin
        #1;
        s0_vaddr = 32'h8000_1234;
        #1;
        check(s0_valid && (s0_paddr == 32'h0000_1234) && s0_cacheable,
              "kseg0_direct_cached_alias");

        s0_vaddr = 32'ha000_1234;
        #1;
        check(s0_valid && (s0_paddr == 32'h0000_1234) && !s0_cacheable,
              "kseg1_direct_uncached_alias");

        s0_vaddr = 32'h0040_2123;
        s1_vaddr = 32'h0040_2123;
        #1;
        check(!s0_valid && !s1_valid && (s0_paddr == 32'b0),
              "tlb_miss_blocks_translation_without_va_fallback");

        write_entry0(1'b0, 8'h12, 1'b1, 1'b1);
        s0_vaddr = 32'h0040_2123;
        s1_vaddr = 32'h0040_2123;
        #1;
        check(s0_valid && (s0_paddr == 32'h1234_5123) && s0_cacheable,
              "mapped_even_page_translation");

        s0_vaddr = 32'h0040_3abc;
        s1_vaddr = 32'h0040_3abc;
        #1;
        check(s0_valid && (s0_paddr == 32'h2345_6abc),
              "mapped_odd_page_translation");

        asid = 8'h34;
        #1;
        check(!s0_found && !s0_valid && !s1_valid,
              "asid_mismatch_misses");

        write_entry0(1'b1, 8'h12, 1'b1, 1'b1);
        s0_vaddr = 32'h0040_2123;
        s1_vaddr = 32'h0040_2123;
        #1;
        check(s0_found && s0_valid,
              "global_entry_matches_any_asid");

        write_entry0(1'b1, 8'h12, 1'b0, 1'b1);
        #1;
        check(s0_found && !s0_v && !s0_valid,
              "invalid_page_blocks_translation");

        write_entry0(1'b1, 8'h12, 1'b1, 1'b0);
        s1_vaddr = 32'h0040_2123;
        is_write = 1'b0;
        #1;
        check(s1_valid, "clean_page_allows_load");
        is_write = 1'b1;
        #1;
        check(!s1_valid, "clean_page_blocks_store");

        write_entry0(1'b1, 8'h12, 1'b1, 1'b1);
        #1;
        check(s1_valid && (s1_paddr == 32'h1234_5123),
              "dirty_page_allows_store");

        if (checks != 11)
            $fatal(1, "LAB14_TRANSLATE_CHECK_COUNT expected=11 observed=%0d", checks);
        $display("DIRECTED_CHECKS=%0d", checks);
        $display("LAB14_TRANSLATE_PASS checks=%0d", checks);
        $finish;
    end
endmodule
