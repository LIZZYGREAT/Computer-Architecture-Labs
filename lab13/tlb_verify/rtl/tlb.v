`timescale 1ns / 1ps
`default_nettype none

module tlb #(
    parameter TLBNUM = 16,
    parameter INDEX_WIDTH = (TLBNUM > 1) ? $clog2(TLBNUM) : 1
)(
    input  wire                   clk,

    input  wire [18:0]            s0_vpn2,
    input  wire                   s0_odd_page,
    input  wire [7:0]             s0_asid,
    output reg                    s0_found,
    output reg  [INDEX_WIDTH-1:0] s0_index,
    output reg  [19:0]            s0_pfn,
    output reg  [2:0]             s0_c,
    output reg                    s0_d,
    output reg                    s0_v,

    input  wire [18:0]            s1_vpn2,
    input  wire                   s1_odd_page,
    input  wire [7:0]             s1_asid,
    output reg                    s1_found,
    output reg  [INDEX_WIDTH-1:0] s1_index,
    output reg  [19:0]            s1_pfn,
    output reg  [2:0]             s1_c,
    output reg                    s1_d,
    output reg                    s1_v,

    input  wire                   we,
    input  wire [INDEX_WIDTH-1:0] w_index,
    input  wire [18:0]            w_vpn2,
    input  wire [7:0]             w_asid,
    input  wire                   w_g,
    input  wire [19:0]            w_pfn0,
    input  wire [2:0]             w_c0,
    input  wire                   w_d0,
    input  wire                   w_v0,
    input  wire [19:0]            w_pfn1,
    input  wire [2:0]             w_c1,
    input  wire                   w_d1,
    input  wire                   w_v1,

    input  wire [INDEX_WIDTH-1:0] r_index,
    output reg  [18:0]            r_vpn2,
    output reg  [7:0]             r_asid,
    output reg                    r_g,
    output reg  [19:0]            r_pfn0,
    output reg  [2:0]             r_c0,
    output reg                    r_d0,
    output reg                    r_v0,
    output reg  [19:0]            r_pfn1,
    output reg  [2:0]             r_c1,
    output reg                    r_d1,
    output reg                    r_v1
);

    reg [TLBNUM-1:0] entry_valid = {TLBNUM{1'b0}};
    reg [18:0] entry_vpn2 [0:TLBNUM-1];
    reg [7:0]  entry_asid [0:TLBNUM-1];
    reg        entry_g    [0:TLBNUM-1];
    reg [19:0] entry_pfn0 [0:TLBNUM-1];
    reg [2:0]  entry_c0   [0:TLBNUM-1];
    reg        entry_d0   [0:TLBNUM-1];
    reg        entry_v0   [0:TLBNUM-1];
    reg [19:0] entry_pfn1 [0:TLBNUM-1];
    reg [2:0]  entry_c1   [0:TLBNUM-1];
    reg        entry_d1   [0:TLBNUM-1];
    reg        entry_v1   [0:TLBNUM-1];

    integer s0_i;
    integer s1_i;

    // The table has no reset pin in the official interface. Valid bits start
    // invalid in FPGA configuration and are set only by indexed writes.
    always @(posedge clk) begin
        if (we && (w_index < TLBNUM)) begin
            entry_valid[w_index] <= 1'b1;
            entry_vpn2[w_index]  <= w_vpn2;
            entry_asid[w_index]  <= w_asid;
            entry_g[w_index]     <= w_g;
            entry_pfn0[w_index]  <= w_pfn0;
            entry_c0[w_index]    <= w_c0;
            entry_d0[w_index]    <= w_d0;
            entry_v0[w_index]    <= w_v0;
            entry_pfn1[w_index]  <= w_pfn1;
            entry_c1[w_index]    <= w_c1;
            entry_d1[w_index]    <= w_d1;
            entry_v1[w_index]    <= w_v1;
        end
    end

    // Direct indexed read is combinational, matching the official testbench.
    always @* begin
        r_vpn2 = 19'b0;
        r_asid = 8'b0;
        r_g    = 1'b0;
        r_pfn0 = 20'b0;
        r_c0   = 3'b0;
        r_d0   = 1'b0;
        r_v0   = 1'b0;
        r_pfn1 = 20'b0;
        r_c1   = 3'b0;
        r_d1   = 1'b0;
        r_v1   = 1'b0;
        if ((r_index < TLBNUM) && entry_valid[r_index]) begin
            r_vpn2 = entry_vpn2[r_index];
            r_asid = entry_asid[r_index];
            r_g    = entry_g[r_index];
            r_pfn0 = entry_pfn0[r_index];
            r_c0   = entry_c0[r_index];
            r_d0   = entry_d0[r_index];
            r_v0   = entry_v0[r_index];
            r_pfn1 = entry_pfn1[r_index];
            r_c1   = entry_c1[r_index];
            r_d1   = entry_d1[r_index];
            r_v1   = entry_v1[r_index];
        end
    end

    // Independent combinational lookup ports. If malformed software creates
    // duplicate matches, the lowest entry index wins deterministically.
    always @* begin
        s0_found = 1'b0;
        s0_index = {INDEX_WIDTH{1'b0}};
        s0_pfn   = 20'b0;
        s0_c     = 3'b0;
        s0_d     = 1'b0;
        s0_v     = 1'b0;
        for (s0_i = 0; s0_i < TLBNUM; s0_i = s0_i + 1) begin
            if (!s0_found && entry_valid[s0_i] &&
                (entry_vpn2[s0_i] == s0_vpn2) &&
                (entry_g[s0_i] || (entry_asid[s0_i] == s0_asid))) begin
                s0_found = 1'b1;
                s0_index = s0_i[INDEX_WIDTH-1:0];
                if (s0_odd_page) begin
                    s0_pfn = entry_pfn1[s0_i];
                    s0_c   = entry_c1[s0_i];
                    s0_d   = entry_d1[s0_i];
                    s0_v   = entry_v1[s0_i];
                end else begin
                    s0_pfn = entry_pfn0[s0_i];
                    s0_c   = entry_c0[s0_i];
                    s0_d   = entry_d0[s0_i];
                    s0_v   = entry_v0[s0_i];
                end
            end
        end
    end

    always @* begin
        s1_found = 1'b0;
        s1_index = {INDEX_WIDTH{1'b0}};
        s1_pfn   = 20'b0;
        s1_c     = 3'b0;
        s1_d     = 1'b0;
        s1_v     = 1'b0;
        for (s1_i = 0; s1_i < TLBNUM; s1_i = s1_i + 1) begin
            if (!s1_found && entry_valid[s1_i] &&
                (entry_vpn2[s1_i] == s1_vpn2) &&
                (entry_g[s1_i] || (entry_asid[s1_i] == s1_asid))) begin
                s1_found = 1'b1;
                s1_index = s1_i[INDEX_WIDTH-1:0];
                if (s1_odd_page) begin
                    s1_pfn = entry_pfn1[s1_i];
                    s1_c   = entry_c1[s1_i];
                    s1_d   = entry_d1[s1_i];
                    s1_v   = entry_v1[s1_i];
                end else begin
                    s1_pfn = entry_pfn0[s1_i];
                    s1_c   = entry_c0[s1_i];
                    s1_d   = entry_d0[s1_i];
                    s1_v   = entry_v0[s1_i];
                end
            end
        end
    end

endmodule

`default_nettype wire
