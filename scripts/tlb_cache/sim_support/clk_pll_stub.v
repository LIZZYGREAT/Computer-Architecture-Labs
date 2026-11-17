`default_nettype none

// Unit-test clock shim. The Lab13/Lab16 benches use the PLL only to feed the
// DUT's clock; this pass-through keeps their cycle-based test logic intact
// while the legacy 2019.2 PLL IP is checked separately in the official XPR.
module clk_pll(
    input  wire clk_in1,
    output wire clk_out1
);
    assign clk_out1 = clk_in1;
endmodule

`default_nettype wire
