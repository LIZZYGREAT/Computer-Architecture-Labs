// Single-beat AXI3 adapter for the Lab11 CPU's request/response memory ports.
// The supported subset keeps one outstanding shared read and one outstanding
// write, with no AXI3 write interleaving or burst reordering.
module axi3_cpu_bus(
    input         aclk,
    input         aresetn,
    input         inst_req,
    input  [ 1:0] inst_size,
    input  [31:0] inst_addr,
    output        inst_addr_ok,
    output        inst_data_ok,
    output [31:0] inst_rdata,
    input         data_req,
    input         data_wr,
    input  [ 1:0] data_size,
    input  [ 3:0] data_wstrb,
    input  [31:0] data_addr,
    input  [31:0] data_wdata,
    output        data_addr_ok,
    output        data_data_ok,
    output [31:0] data_rdata,
    output reg    axi_fault,
    // AXI3 read address channel.
    output [ 3:0] arid,
    output [31:0] araddr,
    output [ 7:0] arlen,
    output [ 2:0] arsize,
    output [ 1:0] arburst,
    output [ 1:0] arlock,
    output [ 3:0] arcache,
    output [ 2:0] arprot,
    output        arvalid,
    input         arready,
    // AXI3 read data channel.
    input  [ 3:0] rid,
    input  [31:0] rdata,
    input  [ 1:0] rresp,
    input         rlast,
    input         rvalid,
    output        rready,
    // AXI3 write address channel.
    output [ 3:0] awid,
    output [31:0] awaddr,
    output [ 7:0] awlen,
    output [ 2:0] awsize,
    output [ 1:0] awburst,
    output [ 1:0] awlock,
    output [ 3:0] awcache,
    output [ 2:0] awprot,
    output        awvalid,
    input         awready,
    // AXI3 write data channel (WID is intentionally retained).
    output [ 3:0] wid,
    output [31:0] wdata,
    output [ 3:0] wstrb,
    output        wlast,
    output        wvalid,
    input         wready,
    // AXI3 write response channel.
    input  [ 3:0] bid,
    input  [ 1:0] bresp,
    input         bvalid,
    output        bready
);

localparam [1:0] RD_IDLE = 2'd0;
localparam [1:0] RD_ADDR = 2'd1;
localparam [1:0] RD_DATA = 2'd2;
localparam [1:0] WR_IDLE = 2'd0;
localparam [1:0] WR_SEND = 2'd1;
localparam [1:0] WR_RESP = 2'd2;
localparam [3:0] IF_ID   = 4'h0;
localparam [3:0] DATA_ID = 4'h1;

reg [1:0] rd_state;
reg       rd_owner_data;
reg [3:0] rd_id_q;
reg [31:0] rd_addr_q;
reg [1:0] rd_size_q;
reg [2:0] rd_prot_q;

reg [1:0] wr_state;
reg [3:0] wr_id_q;
reg [31:0] wr_addr_q;
reg [1:0] wr_size_q;
reg [3:0] wr_strb_q;
reg [31:0] wr_data_q;
reg [2:0] wr_prot_q;
reg       wr_aw_done;
reg       wr_w_done;

wire rd_addr_fire;
wire rd_data_fire;
wire rd_response_good;
wire wr_aw_fire;
wire wr_w_fire;
wire wr_all_done;
wire wr_b_fire;
wire wr_response_good;
wire rd_claim_data;
wire rd_claim_inst;

assign rd_claim_data = (rd_state == RD_IDLE) && !axi_fault &&
                       data_req && !data_wr;
assign rd_claim_inst = (rd_state == RD_IDLE) && !axi_fault &&
                       !rd_claim_data && inst_req;

assign arid    = rd_id_q;
assign araddr  = rd_addr_q;
assign arlen   = 8'd0;
assign arsize  = {1'b0, rd_size_q};
assign arburst = 2'b01;              // INCR, single beat (ARLEN=0).
assign arlock  = 2'b00;              // Normal, unlocked access.
assign arcache = 4'b0000;            // No cache and no buffer allocation.
assign arprot  = rd_prot_q;          // Normal, non-secure; instruction/data bit.
assign arvalid = (rd_state == RD_ADDR) && !axi_fault;
assign rready  = (rd_state == RD_DATA) && !axi_fault;

assign rd_addr_fire = arvalid && arready;
assign rd_data_fire = rvalid && rready;
assign rd_response_good = (rid == rd_id_q) && (rresp == 2'b00) && rlast;
// addr_ok means the adapter has taken ownership and locked the request. The
// AXI address channel may remain stalled afterward without leaving IF free to
// cancel or replace a request that is already queued here.
assign inst_addr_ok = rd_claim_inst;
assign inst_data_ok = rd_data_fire && rd_response_good && !rd_owner_data;
assign inst_rdata = rdata;

assign awid    = wr_id_q;
assign awaddr  = wr_addr_q;
assign awlen   = 8'd0;
assign awsize  = {1'b0, wr_size_q};
assign awburst = 2'b01;              // INCR, single beat (AWLEN=0).
assign awlock  = 2'b00;              // Normal, unlocked access.
assign awcache = 4'b0000;            // No cache and no buffer allocation.
assign awprot  = wr_prot_q;          // Normal, non-secure, data access.
assign awvalid = (wr_state == WR_SEND) && !wr_aw_done && !axi_fault;
assign wid     = wr_id_q;
assign wdata   = wr_data_q;
assign wstrb   = wr_strb_q;
assign wlast   = 1'b1;
assign wvalid  = (wr_state == WR_SEND) && !wr_w_done && !axi_fault;
assign bready  = (wr_state == WR_RESP) && !axi_fault;

assign wr_aw_fire = awvalid && awready;
assign wr_w_fire = wvalid && wready;
assign wr_all_done = (wr_state == WR_SEND) &&
                     (wr_aw_done || wr_aw_fire) &&
                     (wr_w_done || wr_w_fire);
assign wr_b_fire = bvalid && bready;
assign wr_response_good = (bid == wr_id_q) && (bresp == 2'b00);

// AW and W are accepted independently. This pulse marks that both payloads
// have been accepted; MEM still waits for the matching successful B response.
assign data_addr_ok = rd_claim_data ||
                      (wr_all_done && !axi_fault);
assign data_data_ok = (rd_data_fire && rd_response_good && rd_owner_data) ||
                      (wr_b_fire && wr_response_good);
assign data_rdata = rdata;

always @(posedge aclk) begin
    if (!aresetn) begin
        rd_state      <= RD_IDLE;
        rd_owner_data <= 1'b0;
        rd_id_q       <= IF_ID;
        rd_addr_q     <= 32'b0;
        rd_size_q     <= 2'd2;
        rd_prot_q     <= 3'b010;
        wr_state      <= WR_IDLE;
        wr_id_q       <= DATA_ID;
        wr_addr_q     <= 32'b0;
        wr_size_q     <= 2'd2;
        wr_strb_q     <= 4'b0;
        wr_data_q     <= 32'b0;
        wr_prot_q     <= 3'b110;
        wr_aw_done    <= 1'b0;
        wr_w_done     <= 1'b0;
        axi_fault     <= 1'b0;
    end else begin
        if (rd_claim_data) begin
            rd_owner_data <= 1'b1;
            rd_id_q       <= DATA_ID;
            // LWL/LWR use the aligned SRAM word while preserving their byte
            // offset for MEM's merge logic. Ordinary byte/halfword reads keep
            // the exact address and use AXI narrow transfers.
            rd_addr_q     <= (data_size == 2'd2 && data_addr[1:0] != 2'b00) ?
                             {data_addr[31:2], 2'b00} : data_addr;
            rd_size_q     <= data_size;
            rd_prot_q     <= 3'b110;
            rd_state      <= RD_ADDR;
        end else if (rd_claim_inst) begin
            rd_owner_data <= 1'b0;
            rd_id_q       <= IF_ID;
            rd_addr_q     <= inst_addr;
            rd_size_q     <= inst_size;
            rd_prot_q     <= 3'b010;
            rd_state      <= RD_ADDR;
        end else if (rd_state == RD_ADDR && rd_addr_fire) begin
            rd_state <= RD_DATA;
        end else if (rd_state == RD_DATA && rd_data_fire) begin
            rd_state <= RD_IDLE;
            if (!rd_response_good) begin
                axi_fault <= 1'b1;
`ifndef SYNTHESIS
                if (rid != rd_id_q)
                    $display("AXI3_FAULT R_ID expected=%h actual=%h", rd_id_q, rid);
                if (rresp != 2'b00)
                    $display("AXI3_FAULT R_RESP value=%b", rresp);
                if (!rlast)
                    $display("AXI3_FAULT R_LAST missing");
`endif
            end
        end

        if (wr_state == WR_IDLE && data_req && data_wr && !axi_fault) begin
            wr_id_q    <= DATA_ID;
            // SWL/SWR carry an aligned-word lane mask from MEM. Aligning the
            // full-width AXI beat keeps the SRAM byte-lane semantics intact.
            wr_addr_q  <= (data_size == 2'd2 && data_addr[1:0] != 2'b00) ?
                          {data_addr[31:2], 2'b00} : data_addr;
            wr_size_q  <= data_size;
            wr_strb_q  <= data_wstrb;
            wr_data_q  <= data_wdata;
            wr_prot_q  <= 3'b110;
            wr_aw_done <= 1'b0;
            wr_w_done  <= 1'b0;
            wr_state   <= WR_SEND;
        end else if (wr_state == WR_SEND) begin
            if (wr_aw_fire)
                wr_aw_done <= 1'b1;
            if (wr_w_fire)
                wr_w_done <= 1'b1;
            if (wr_all_done)
                wr_state <= WR_RESP;
        end else if (wr_state == WR_RESP && wr_b_fire) begin
            wr_state <= WR_IDLE;
            if (!wr_response_good) begin
                axi_fault <= 1'b1;
`ifndef SYNTHESIS
                if (bid != wr_id_q)
                    $display("AXI3_FAULT B_ID expected=%h actual=%h", wr_id_q, bid);
                if (bresp != 2'b00)
                    $display("AXI3_FAULT B_RESP value=%b", bresp);
`endif
            end
        end
    end
end

endmodule
