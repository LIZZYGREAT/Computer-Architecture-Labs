`timescale 1ns/1ps

module tb_tlb_directed;
    localparam TLBNUM = 16;
    localparam INDEX_WIDTH = 4;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg [18:0] s0_vpn2 = 0;
    reg s0_odd_page = 0;
    reg [7:0] s0_asid = 0;
    wire s0_found;
    wire [INDEX_WIDTH-1:0] s0_index;
    wire [19:0] s0_pfn;
    wire [2:0] s0_c;
    wire s0_d, s0_v;

    reg [18:0] s1_vpn2 = 0;
    reg s1_odd_page = 0;
    reg [7:0] s1_asid = 0;
    wire s1_found;
    wire [INDEX_WIDTH-1:0] s1_index;
    wire [19:0] s1_pfn;
    wire [2:0] s1_c;
    wire s1_d, s1_v;

    reg we = 0;
    reg [INDEX_WIDTH-1:0] w_index = 0;
    reg [18:0] w_vpn2 = 0;
    reg [7:0] w_asid = 0;
    reg w_g = 0;
    reg [19:0] w_pfn0 = 0;
    reg [2:0] w_c0 = 0;
    reg w_d0 = 0, w_v0 = 0;
    reg [19:0] w_pfn1 = 0;
    reg [2:0] w_c1 = 0;
    reg w_d1 = 0, w_v1 = 0;

    reg [INDEX_WIDTH-1:0] r_index = 0;
    wire [18:0] r_vpn2;
    wire [7:0] r_asid;
    wire r_g;
    wire [19:0] r_pfn0, r_pfn1;
    wire [2:0] r_c0, r_c1;
    wire r_d0, r_v0, r_d1, r_v1;

    integer checks = 0;

    tlb #(.TLBNUM(TLBNUM)) dut (
        .clk(clk),
        .s0_vpn2(s0_vpn2), .s0_odd_page(s0_odd_page), .s0_asid(s0_asid),
        .s0_found(s0_found), .s0_index(s0_index), .s0_pfn(s0_pfn),
        .s0_c(s0_c), .s0_d(s0_d), .s0_v(s0_v),
        .s1_vpn2(s1_vpn2), .s1_odd_page(s1_odd_page), .s1_asid(s1_asid),
        .s1_found(s1_found), .s1_index(s1_index), .s1_pfn(s1_pfn),
        .s1_c(s1_c), .s1_d(s1_d), .s1_v(s1_v),
        .we(we), .w_index(w_index), .w_vpn2(w_vpn2), .w_asid(w_asid),
        .w_g(w_g), .w_pfn0(w_pfn0), .w_c0(w_c0), .w_d0(w_d0), .w_v0(w_v0),
        .w_pfn1(w_pfn1), .w_c1(w_c1), .w_d1(w_d1), .w_v1(w_v1),
        .r_index(r_index), .r_vpn2(r_vpn2), .r_asid(r_asid), .r_g(r_g),
        .r_pfn0(r_pfn0), .r_c0(r_c0), .r_d0(r_d0), .r_v0(r_v0),
        .r_pfn1(r_pfn1), .r_c1(r_c1), .r_d1(r_d1), .r_v1(r_v1)
    );

    task write_entry;
        input [INDEX_WIDTH-1:0] index;
        input [18:0] vpn2;
        input [7:0] asid;
        input global_bit;
        input [19:0] pfn0;
        input [2:0] c0;
        input d0, v0;
        input [19:0] pfn1;
        input [2:0] c1;
        input d1, v1;
        begin
            @(negedge clk);
            we = 1;
            w_index = index;
            w_vpn2 = vpn2;
            w_asid = asid;
            w_g = global_bit;
            w_pfn0 = pfn0;
            w_c0 = c0;
            w_d0 = d0;
            w_v0 = v0;
            w_pfn1 = pfn1;
            w_c1 = c1;
            w_d1 = d1;
            w_v1 = v1;
            @(posedge clk);
            #1;
            we = 0;
        end
    endtask

    task expect_s0;
        input found;
        input [INDEX_WIDTH-1:0] index;
        input [19:0] pfn;
        input [2:0] c;
        input d, v;
        begin
            #1;
            if (s0_found !== found || s0_index !== index || s0_pfn !== pfn ||
                s0_c !== c || s0_d !== d || s0_v !== v) begin
                $display("S0_MISMATCH found=%b index=%h pfn=%h c=%h d=%b v=%b", s0_found, s0_index, s0_pfn, s0_c, s0_d, s0_v);
                $fatal(1, "S0 lookup mismatch");
            end
            checks = checks + 1;
        end
    endtask

    task expect_s1;
        input found;
        input [INDEX_WIDTH-1:0] index;
        input [19:0] pfn;
        input [2:0] c;
        input d, v;
        begin
            #1;
            if (s1_found !== found || s1_index !== index || s1_pfn !== pfn ||
                s1_c !== c || s1_d !== d || s1_v !== v) begin
                $display("S1_MISMATCH found=%b index=%h pfn=%h c=%h d=%b v=%b", s1_found, s1_index, s1_pfn, s1_c, s1_d, s1_v);
                $fatal(1, "S1 lookup mismatch");
            end
            checks = checks + 1;
        end
    endtask

    initial begin
        #20000;
        $fatal(1, "WATCHDOG_TIMEOUT");
    end

    initial begin
        write_entry(4'd0, 19'h12345, 8'haa, 1'b0, 20'h12345, 3'h3, 1'b1, 1'b1, 20'h54321, 3'h5, 1'b0, 1'b1);
        write_entry(4'd1, 19'h12345, 8'hbb, 1'b0, 20'hbb001, 3'h2, 1'b0, 1'b1, 20'hbb002, 3'h6, 1'b1, 1'b1);
        write_entry(4'd2, 19'h23456, 8'h11, 1'b1, 20'h23456, 3'h4, 1'b1, 1'b0, 20'h65432, 3'h7, 1'b1, 1'b1);

        // Both search ports hit different entries in the same cycle.
        s0_vpn2 = 19'h12345; s0_asid = 8'haa; s0_odd_page = 1'b0;
        s1_vpn2 = 19'h12345; s1_asid = 8'hbb; s1_odd_page = 1'b1;
        expect_s0(1'b1, 4'd0, 20'h12345, 3'h3, 1'b1, 1'b1);
        expect_s1(1'b1, 4'd1, 20'hbb002, 3'h6, 1'b1, 1'b1);

        // ASID mismatch misses; global entries ignore ASID on each port.
        s0_asid = 8'hcc;
        expect_s0(1'b0, 4'd0, 20'b0, 3'b0, 1'b0, 1'b0);
        s1_vpn2 = 19'h23456; s1_asid = 8'hfe; s1_odd_page = 1'b1;
        expect_s1(1'b1, 4'd2, 20'h65432, 3'h7, 1'b1, 1'b1);
        s0_vpn2 = 19'h23456; s0_asid = 8'h00; s0_odd_page = 1'b0;
        expect_s0(1'b1, 4'd2, 20'h23456, 3'h4, 1'b1, 1'b0);

        // Direct read returns every stored field; unwritten entries are zero.
        r_index = 4'd0; #1;
        if (r_vpn2 !== 19'h12345 || r_asid !== 8'haa || r_g !== 1'b0 ||
            r_pfn0 !== 20'h12345 || r_c0 !== 3'h3 || r_d0 !== 1'b1 || r_v0 !== 1'b1 ||
            r_pfn1 !== 20'h54321 || r_c1 !== 3'h5 || r_d1 !== 1'b0 || r_v1 !== 1'b1)
            $fatal(1, "READBACK_ENTRY0_MISMATCH");
        checks = checks + 1;
        r_index = 4'd7; #1;
        if (r_vpn2 !== 19'b0 || r_asid !== 8'b0 || r_g !== 1'b0 || r_pfn0 !== 20'b0 || r_pfn1 !== 20'b0)
            $fatal(1, "UNWRITTEN_ENTRY_NOT_ZERO");
        checks = checks + 1;

        // Rewriting an index replaces its old mapping completely.
        write_entry(4'd0, 19'h33333, 8'h44, 1'b0, 20'h33330, 3'h1, 1'b0, 1'b1, 20'h33331, 3'h2, 1'b1, 1'b1);
        s0_vpn2 = 19'h12345; s0_asid = 8'haa; s0_odd_page = 1'b0;
        expect_s0(1'b0, 4'd0, 20'b0, 3'b0, 1'b0, 1'b0);
        s0_vpn2 = 19'h33333; s0_asid = 8'h44; s0_odd_page = 1'b1;
        expect_s0(1'b1, 4'd0, 20'h33331, 3'h2, 1'b1, 1'b1);

        $display("DIRECTED_CHECKS=%0d", checks);
        $display("DIRECTED_PASS");
        $finish;
    end
endmodule
