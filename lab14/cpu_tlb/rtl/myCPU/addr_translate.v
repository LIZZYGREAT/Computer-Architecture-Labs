`default_nettype none

// MIPS 32-bit virtual to physical address translation for the supported
// kseg0/kseg1 direct-mapped windows and 4 KiB TLB pages.
module addr_translate(
    input  wire [31:0] vaddr,
    input  wire        is_write,
    input  wire        tlb_found,
    input  wire [19:0] tlb_pfn,
    input  wire [2:0]  tlb_c,
    input  wire        tlb_d,
    input  wire        tlb_v,
    output wire [31:0] paddr,
    output wire        translation_valid,
    output wire        cacheable
);

wire kseg0;
wire kseg1;
wire mapped_page_valid;

assign kseg0 = (vaddr[31:29] == 3'b100);
assign kseg1 = (vaddr[31:29] == 3'b101);
assign mapped_page_valid = tlb_found && tlb_v && (!is_write || tlb_d);

assign translation_valid = kseg0 || kseg1 || mapped_page_valid;
assign paddr = (kseg0 || kseg1) ? {3'b000, vaddr[28:0]} :
               mapped_page_valid ? {tlb_pfn, vaddr[11:0]} : 32'b0;

// MIPS coherent cacheable pages use C=3. KSEG0 is cached and KSEG1 is not.
assign cacheable = kseg0 || (!kseg1 && mapped_page_valid && (tlb_c == 3'b011));

endmodule

`default_nettype wire
