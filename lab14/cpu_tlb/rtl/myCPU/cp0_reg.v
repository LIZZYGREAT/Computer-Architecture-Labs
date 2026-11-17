module cp0_reg (
    input         clk,
    input         reset,
    input  [ 5:0] hw_int,
    input         cp0_we,
    input  [ 7:0] cp0_waddr,
    input  [31:0] cp0_wdata,
    input  [ 7:0] cp0_raddr,
    output reg [31:0] cp0_rdata,
    input         exc_commit,
    input  [ 4:0] exc_code,
    input  [31:0] exc_pc,
    input         exc_bd,
    input  [31:0] exc_bad_vaddr,
    input         eret_commit,
    input         tlbr_commit,
    input  [18:0] tlbr_vpn2,
    input  [ 7:0] tlbr_asid,
    input         tlbr_g,
    input  [19:0] tlbr_pfn0,
    input  [ 2:0] tlbr_c0,
    input         tlbr_d0,
    input         tlbr_v0,
    input  [19:0] tlbr_pfn1,
    input  [ 2:0] tlbr_c1,
    input         tlbr_d1,
    input         tlbr_v1,
    input         tlbp_commit,
    input         tlbp_found,
    input  [ 3:0] tlbp_index,
    output [31:0] cp0_epc,
    output [31:0] cp0_index,
    output [31:0] cp0_random,
    output [31:0] cp0_entryhi,
    output [31:0] cp0_entrylo0,
    output [31:0] cp0_entrylo1,
    output        cp0_bev,
    output        interrupt_pending
);

localparam [7:0] CP0_BADVADDR = {5'd8,  3'd0};
localparam [7:0] CP0_COUNT    = {5'd9,  3'd0};
localparam [7:0] CP0_COMPARE  = {5'd11, 3'd0};
localparam [7:0] CP0_STATUS   = {5'd12, 3'd0};
localparam [7:0] CP0_CAUSE    = {5'd13, 3'd0};
localparam [7:0] CP0_EPC      = {5'd14, 3'd0};
localparam [7:0] CP0_INDEX    = {5'd0,  3'd0};
localparam [7:0] CP0_RANDOM   = {5'd1,  3'd0};
localparam [7:0] CP0_ENTRYLO0 = {5'd2,  3'd0};
localparam [7:0] CP0_ENTRYLO1 = {5'd3,  3'd0};
localparam [7:0] CP0_WIRED    = {5'd6,  3'd0};
localparam [7:0] CP0_ENTRYHI  = {5'd10, 3'd0};

reg [31:0] bad_vaddr;
reg [31:0] count;
reg [31:0] compare;
reg [31:0] epc;
reg [31:0] index;
reg [3:0]  random_index;
reg [3:0]  wired;
reg [31:0] entryhi;
reg [31:0] entrylo0;
reg [31:0] entrylo1;
reg        status_ie;
reg        status_exl;
reg [7:0]  status_im;
reg        status_bev;
reg [1:0]  cause_sw_ip;
reg        cause_bd;
reg [4:0]  cause_exc_code;
reg        timer_pending;
reg        count_add_en;

wire cp0_write_allowed;
wire cp0_write_count;
wire cp0_write_compare;
wire cp0_write_status;
wire cp0_write_cause;
wire cp0_write_epc;
wire cp0_write_index;
wire cp0_write_entryhi;
wire cp0_write_entrylo0;
wire cp0_write_entrylo1;
wire cp0_write_wired;
wire [7:0] cause_ip;
wire [31:0] cause_value;

assign cp0_write_allowed = cp0_we && !exc_commit && !eret_commit &&
                           (cp0_waddr[2:0] == 3'b000);
assign cp0_write_count   = cp0_write_allowed && (cp0_waddr == CP0_COUNT);
assign cp0_write_compare = cp0_write_allowed && (cp0_waddr == CP0_COMPARE);
assign cp0_write_status  = cp0_write_allowed && (cp0_waddr == CP0_STATUS);
assign cp0_write_cause   = cp0_write_allowed && (cp0_waddr == CP0_CAUSE);
assign cp0_write_epc     = cp0_write_allowed && (cp0_waddr == CP0_EPC);
assign cp0_write_index   = cp0_write_allowed && (cp0_waddr == CP0_INDEX);
assign cp0_write_entryhi = cp0_write_allowed && (cp0_waddr == CP0_ENTRYHI);
assign cp0_write_entrylo0= cp0_write_allowed && (cp0_waddr == CP0_ENTRYLO0);
assign cp0_write_entrylo1= cp0_write_allowed && (cp0_waddr == CP0_ENTRYLO1);
assign cp0_write_wired   = cp0_write_allowed && (cp0_waddr == CP0_WIRED);

// Cause.IP[7:2] follows hw_int[5:0].  The timer request shares IP7 with
// the highest external interrupt input; neither source masks the other.
assign cause_ip = {hw_int[5] | timer_pending, hw_int[4:0], cause_sw_ip};
assign cause_value = {cause_bd, timer_pending, 2'b00, 1'b0, 11'b0,
                      cause_ip, 1'b0, cause_exc_code, 2'b00};

assign cp0_epc = epc;
assign cp0_index = index;
assign cp0_random = {28'b0, random_index};
assign cp0_entryhi = entryhi;
assign cp0_entrylo0 = entrylo0;
assign cp0_entrylo1 = entrylo1;
assign cp0_bev = status_bev;
assign interrupt_pending = status_ie && !status_exl &&
                           (|(cause_ip & status_im));

always @(*) begin
    cp0_rdata = 32'b0;
    if (cp0_raddr[2:0] == 3'b000) begin
        case (cp0_raddr[7:3])
            5'd0:  cp0_rdata = index;
            5'd1:  cp0_rdata = {28'b0, random_index};
            5'd2:  cp0_rdata = entrylo0;
            5'd3:  cp0_rdata = entrylo1;
            5'd8:  cp0_rdata = bad_vaddr;
            5'd9:  cp0_rdata = count;
            5'd11: cp0_rdata = compare;
            5'd12: begin
                cp0_rdata[22]    = status_bev;
                cp0_rdata[15:8]  = status_im;
                cp0_rdata[1]     = status_exl;
                cp0_rdata[0]     = status_ie;
            end
            5'd13: cp0_rdata = cause_value;
            5'd14: cp0_rdata = epc;
            5'd10: cp0_rdata = entryhi;
            5'd6:  cp0_rdata = {28'b0, wired};
            default: cp0_rdata = 32'b0;
        endcase
    end
end

always @(posedge clk) begin
    if (reset) begin
        bad_vaddr     <= 32'b0;
        count         <= 32'b0;
        compare       <= 32'b0;
        epc           <= 32'b0;
        index         <= 32'b0;
        random_index  <= 4'hf;
        wired         <= 4'b0;
        entryhi       <= 32'b0;
        entrylo0      <= 32'b0;
        entrylo1      <= 32'b0;
        status_ie     <= 1'b0;
        status_exl    <= 1'b0;
        status_im     <= 8'b0;
        status_bev    <= 1'b1;
        cause_sw_ip   <= 2'b0;
        cause_bd      <= 1'b0;
        cause_exc_code<= 5'h1f;
        timer_pending <= 1'b0;
        count_add_en  <= 1'b0;
    end
    else begin
        // Match CPU132's half-rate Count clock.  A Count write replaces the
        // value for this edge; the divider phase continues to advance.
        count_add_en <= ~count_add_en;
        if (cp0_write_count)
            count <= cp0_wdata;
        else if (count_add_en)
            count <= count + 32'd1;

        // Compare writes clear TI.  Otherwise Count==Compare latches it until
        // the next Compare write, matching the course reference CPU.
        if (cp0_write_compare) begin
            compare       <= cp0_wdata;
            timer_pending <= 1'b0;
        end
        else if (count == compare) begin
            timer_pending <= 1'b1;
        end

        if (cp0_write_status) begin
            status_ie  <= cp0_wdata[0];
            status_exl <= cp0_wdata[1];
            status_im  <= cp0_wdata[15:8];
            status_bev <= cp0_wdata[22];
        end

        if (cp0_write_cause)
            cause_sw_ip <= cp0_wdata[9:8];

        if (cp0_write_epc)
            epc <= cp0_wdata;

        if (cp0_write_index)
            index <= {27'b0, cp0_wdata[3:0]};
        if (cp0_write_entryhi)
            entryhi <= {cp0_wdata[31:13], 5'b0, cp0_wdata[7:0]};
        if (cp0_write_entrylo0)
            entrylo0 <= {6'b0, cp0_wdata[25:0]};
        if (cp0_write_entrylo1)
            entrylo1 <= {6'b0, cp0_wdata[25:0]};
        if (cp0_write_wired) begin
            wired <= cp0_wdata[3:0];
            if (random_index <= cp0_wdata[3:0])
                random_index <= 4'hf;
        end else if (random_index <= wired) begin
            random_index <= 4'hf;
        end else begin
            random_index <= random_index - 4'd1;
        end

        // TLB instructions update CP0 only when the in-order commit point
        // asserts their one-cycle commit pulse.
        if (tlbp_commit)
            index <= tlbp_found ? {28'b0, tlbp_index} : 32'h8000_0000;
        if (tlbr_commit) begin
            entryhi  <= {tlbr_vpn2, 5'b0, tlbr_asid};
            entrylo0 <= {6'b0, tlbr_pfn0, tlbr_c0, tlbr_d0, tlbr_v0, tlbr_g};
            entrylo1 <= {6'b0, tlbr_pfn1, tlbr_c1, tlbr_d1, tlbr_v1, tlbr_g};
        end

        if (exc_commit) begin
            status_exl     <= 1'b1;
            cause_exc_code <= exc_code;
            if (!status_exl) begin
                cause_bd <= exc_bd;
                epc <= exc_bd ? (exc_pc - 32'd4) : exc_pc;
            end
            if ((exc_code == 5'd4) || (exc_code == 5'd5))
                bad_vaddr <= exc_bad_vaddr;
        end
        else if (eret_commit) begin
            status_exl <= 1'b0;
        end
    end
end

endmodule
