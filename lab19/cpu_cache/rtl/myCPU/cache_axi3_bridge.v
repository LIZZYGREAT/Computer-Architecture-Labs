// Shared AXI3 bridge for cache refills, dirty writebacks and uncache accesses.
// It owns the external bus so I-cache and D-cache never drive AXI directly.
module cache_axi3_bridge(
    input          aclk,
    input          aresetn,

    input          ic_refill_req,
    input  [31:0]  ic_refill_addr,
    output         ic_refill_addr_ok,
    output         ic_ret_valid,
    output         ic_ret_last,
    output [31:0]  ic_ret_data,

    input          dc_refill_req,
    input  [31:0]  dc_refill_addr,
    output         dc_refill_addr_ok,
    output         dc_ret_valid,
    output         dc_ret_last,
    output [31:0]  dc_ret_data,

    input          inst_req,
    input  [1:0]   inst_size,
    input  [31:0]  inst_addr,
    output         inst_addr_ok,
    output         inst_data_ok,
    output [31:0]  inst_rdata,

    input          data_req,
    input          data_wr,
    input  [1:0]   data_size,
    input  [3:0]   data_wstrb,
    input  [31:0]  data_addr,
    input  [31:0]  data_wdata,
    output         data_addr_ok,
    output         data_data_ok,
    output [31:0]  data_rdata,

    input          dc_writeback_req,
    input  [31:0]  dc_writeback_addr,
    input  [255:0] dc_writeback_data,
    output         dc_writeback_addr_ok,
    output         dc_writeback_done,

    output reg     axi_fault,
    output reg [31:0] stat_ar_transactions,
    output reg [31:0] stat_r_beats,
    output reg [31:0] stat_aw_transactions,
    output reg [31:0] stat_w_beats,
    output reg [31:0] stat_b_responses,

    output [3:0]   arid,
    output [31:0]  araddr,
    output [7:0]   arlen,
    output [2:0]   arsize,
    output [1:0]   arburst,
    output [1:0]   arlock,
    output [3:0]   arcache,
    output [2:0]   arprot,
    output         arvalid,
    input          arready,
    input  [3:0]   rid,
    input  [31:0]  rdata,
    input  [1:0]   rresp,
    input          rlast,
    input          rvalid,
    output         rready,

    output [3:0]   awid,
    output [31:0]  awaddr,
    output [7:0]   awlen,
    output [2:0]   awsize,
    output [1:0]   awburst,
    output [1:0]   awlock,
    output [3:0]   awcache,
    output [2:0]   awprot,
    output         awvalid,
    input          awready,
    output [3:0]   wid,
    output [31:0]  wdata,
    output [3:0]   wstrb,
    output         wlast,
    output         wvalid,
    input          wready,
    input  [3:0]   bid,
    input  [1:0]   bresp,
    input          bvalid,
    output         bready
);

localparam [1:0] RD_IDLE = 2'd0;
localparam [1:0] RD_ADDR = 2'd1;
localparam [1:0] RD_DATA = 2'd2;
localparam [1:0] WR_IDLE = 2'd0;
localparam [1:0] WR_SEND = 2'd1;
localparam [1:0] WR_RESP = 2'd2;

localparam [2:0] RD_OWNER_NONE = 3'd0;
localparam [2:0] RD_OWNER_IC   = 3'd1;
localparam [2:0] RD_OWNER_DC   = 3'd2;
localparam [2:0] RD_OWNER_INST = 3'd3;
localparam [2:0] RD_OWNER_DATA = 3'd4;
localparam [1:0] WR_OWNER_NONE = 2'd0;
localparam [1:0] WR_OWNER_WB   = 2'd1;
localparam [1:0] WR_OWNER_DATA = 2'd2;

reg [1:0] rd_state;
reg [2:0] rd_owner;
reg [1:0] rd_rr;
reg [3:0] rd_id_q;
reg [31:0] rd_addr_q;
reg [7:0] rd_len_q;
reg [7:0] rd_beat;
reg [1:0] rd_size_q;
reg [2:0] rd_prot_q;
reg [3:0] rd_cache_q;

reg [1:0] wr_state;
reg [1:0] wr_owner;
reg [3:0] wr_id_q;
reg [31:0] wr_addr_q;
reg [7:0] wr_len_q;
reg [2:0] wr_beat;
reg [255:0] wr_data_q;
reg [31:0] wr_strb_q;
reg wr_aw_done;
reg wr_w_done;
reg [2:0] wr_prot_q;
reg [3:0] wr_cache_q;

reg [2:0] rd_pick;
reg rd_pick_valid;
reg [31:0] rd_pick_addr;
reg [3:0] rd_pick_id;
reg [7:0] rd_pick_len;
reg [1:0] rd_pick_size;
reg [2:0] rd_pick_prot;
reg [3:0] rd_pick_cache;

wire rd_claim;
wire rd_ar_fire;
wire rd_fire;
wire rd_response_good;
wire rd_expected_last;
wire wr_claim_wb;
wire wr_claim_data;
wire wr_aw_fire;
wire wr_w_fire;
wire wr_all_done;
wire wr_b_fire;
wire wr_response_good;
wire [31:0] wr_word_data;
wire [3:0] wr_word_strb;

assign rd_claim = (rd_state == RD_IDLE) && rd_pick_valid && !axi_fault;
assign ic_refill_addr_ok = rd_claim && (rd_pick == RD_OWNER_IC);
assign dc_refill_addr_ok = rd_claim && (rd_pick == RD_OWNER_DC);
assign inst_addr_ok = rd_claim && (rd_pick == RD_OWNER_INST);

assign rd_ar_fire = arvalid && arready;
assign rd_fire = rvalid && rready;
assign rd_expected_last = (rd_beat == rd_len_q);
assign rd_response_good = (rid == rd_id_q) &&
                          (rresp == 2'b00) &&
                          (rlast == rd_expected_last);

assign arid = rd_id_q;
assign araddr = rd_addr_q;
assign arlen = rd_len_q;
assign arsize = {1'b0, rd_size_q};
assign arburst = 2'b01;
assign arlock = 2'b00;
assign arcache = rd_cache_q;
assign arprot = rd_prot_q;
assign arvalid = (rd_state == RD_ADDR) && !axi_fault;
assign rready = (rd_state == RD_DATA) && !axi_fault;

assign ic_ret_valid = rd_fire && rd_response_good && (rd_owner == RD_OWNER_IC);
assign ic_ret_last = rlast;
assign ic_ret_data = rdata;
assign dc_ret_valid = rd_fire && rd_response_good && (rd_owner == RD_OWNER_DC);
assign dc_ret_last = rlast;
assign dc_ret_data = rdata;
assign inst_data_ok = rd_fire && rd_response_good && (rd_owner == RD_OWNER_INST);
assign inst_rdata = rdata;
assign data_data_ok = (rd_fire && rd_response_good && (rd_owner == RD_OWNER_DATA)) ||
                      (wr_b_fire && wr_response_good && (wr_owner == WR_OWNER_DATA));
assign data_rdata = rdata;

assign wr_claim_wb = (wr_state == WR_IDLE) && dc_writeback_req && !axi_fault;
assign wr_claim_data = (wr_state == WR_IDLE) && !dc_writeback_req &&
                       data_req && data_wr && !axi_fault;
assign dc_writeback_addr_ok = wr_claim_wb;
assign dc_writeback_done = wr_b_fire && wr_response_good && (wr_owner == WR_OWNER_WB);
assign data_addr_ok = (rd_claim && (rd_pick == RD_OWNER_DATA)) || wr_claim_data;

assign awid = wr_id_q;
assign awaddr = wr_addr_q;
assign awlen = wr_len_q;
assign awsize = 3'b010;
assign awburst = 2'b01;
assign awlock = 2'b00;
assign awcache = wr_cache_q;
assign awprot = wr_prot_q;
assign awvalid = (wr_state == WR_SEND) && !wr_aw_done && !axi_fault;
assign wid = wr_id_q;
assign wdata = wr_word_data;
assign wstrb = wr_word_strb;
assign wlast = (wr_beat == wr_len_q[2:0]);
assign wvalid = (wr_state == WR_SEND) && !wr_w_done && !axi_fault;
assign bready = (wr_state == WR_RESP) && !axi_fault;

assign wr_aw_fire = awvalid && awready;
assign wr_w_fire = wvalid && wready;
assign wr_all_done = (wr_state == WR_SEND) &&
                     (wr_aw_done || wr_aw_fire) &&
                     (wr_w_done || (wr_w_fire && wlast));
assign wr_b_fire = bvalid && bready;
assign wr_response_good = (bid == wr_id_q) && (bresp == 2'b00);
assign wr_word_data = wr_data_q[wr_beat*32 +: 32];
assign wr_word_strb = wr_strb_q[wr_beat*4 +: 4];

always @* begin
    rd_pick = RD_OWNER_NONE;
    rd_pick_valid = 1'b0;
    rd_pick_addr = 32'b0;
    rd_pick_id = 4'b0;
    rd_pick_len = 8'b0;
    rd_pick_size = 2'd2;
    rd_pick_prot = 3'b010;
    rd_pick_cache = 4'b0000;
    case (rd_rr)
        2'd0: begin
            if (ic_refill_req) begin
                rd_pick = RD_OWNER_IC; rd_pick_valid = 1'b1;
            end else if (dc_refill_req) begin
                rd_pick = RD_OWNER_DC; rd_pick_valid = 1'b1;
            end else if (inst_req) begin
                rd_pick = RD_OWNER_INST; rd_pick_valid = 1'b1;
            end else if (data_req && !data_wr) begin
                rd_pick = RD_OWNER_DATA; rd_pick_valid = 1'b1;
            end
        end
        2'd1: begin
            if (dc_refill_req) begin
                rd_pick = RD_OWNER_DC; rd_pick_valid = 1'b1;
            end else if (inst_req) begin
                rd_pick = RD_OWNER_INST; rd_pick_valid = 1'b1;
            end else if (data_req && !data_wr) begin
                rd_pick = RD_OWNER_DATA; rd_pick_valid = 1'b1;
            end else if (ic_refill_req) begin
                rd_pick = RD_OWNER_IC; rd_pick_valid = 1'b1;
            end
        end
        2'd2: begin
            if (inst_req) begin
                rd_pick = RD_OWNER_INST; rd_pick_valid = 1'b1;
            end else if (data_req && !data_wr) begin
                rd_pick = RD_OWNER_DATA; rd_pick_valid = 1'b1;
            end else if (ic_refill_req) begin
                rd_pick = RD_OWNER_IC; rd_pick_valid = 1'b1;
            end else if (dc_refill_req) begin
                rd_pick = RD_OWNER_DC; rd_pick_valid = 1'b1;
            end
        end
        default: begin
            if (data_req && !data_wr) begin
                rd_pick = RD_OWNER_DATA; rd_pick_valid = 1'b1;
            end else if (ic_refill_req) begin
                rd_pick = RD_OWNER_IC; rd_pick_valid = 1'b1;
            end else if (dc_refill_req) begin
                rd_pick = RD_OWNER_DC; rd_pick_valid = 1'b1;
            end else if (inst_req) begin
                rd_pick = RD_OWNER_INST; rd_pick_valid = 1'b1;
            end
        end
    endcase

    case (rd_pick)
        RD_OWNER_IC: begin
            rd_pick_addr = {ic_refill_addr[31:5], 5'b0};
            rd_pick_id = 4'h0;
            rd_pick_len = 8'd7;
            rd_pick_size = 2'd2;
            rd_pick_prot = 3'b110;
            rd_pick_cache = 4'b1111;
        end
        RD_OWNER_DC: begin
            rd_pick_addr = {dc_refill_addr[31:5], 5'b0};
            rd_pick_id = 4'h1;
            rd_pick_len = 8'd7;
            rd_pick_size = 2'd2;
            rd_pick_prot = 3'b010;
            rd_pick_cache = 4'b1111;
        end
        RD_OWNER_INST: begin
            rd_pick_addr = inst_addr;
            rd_pick_id = 4'h2;
            rd_pick_len = 8'd0;
            rd_pick_size = inst_size;
            rd_pick_prot = 3'b110;
            rd_pick_cache = 4'b0000;
        end
        RD_OWNER_DATA: begin
            rd_pick_addr = (data_size == 2'd2 && data_addr[1:0] != 2'b00) ?
                           {data_addr[31:2], 2'b00} : data_addr;
            rd_pick_id = 4'h3;
            rd_pick_len = 8'd0;
            rd_pick_size = data_size;
            rd_pick_prot = 3'b010;
            rd_pick_cache = 4'b0000;
        end
        default: begin end
    endcase
end

always @(posedge aclk) begin
    if (!aresetn) begin
        rd_state <= RD_IDLE;
        rd_owner <= RD_OWNER_NONE;
        rd_rr <= 2'b0;
        rd_id_q <= 4'b0;
        rd_addr_q <= 32'b0;
        rd_len_q <= 8'b0;
        rd_beat <= 8'b0;
        rd_size_q <= 2'd2;
        rd_prot_q <= 3'b010;
        rd_cache_q <= 4'b0;
        wr_state <= WR_IDLE;
        wr_owner <= WR_OWNER_NONE;
        wr_id_q <= 4'b1;
        wr_addr_q <= 32'b0;
        wr_len_q <= 8'b0;
        wr_beat <= 3'b0;
        wr_data_q <= 256'b0;
        wr_strb_q <= 32'b0;
        wr_aw_done <= 1'b0;
        wr_w_done <= 1'b0;
        wr_prot_q <= 3'b010;
        wr_cache_q <= 4'b0;
        axi_fault <= 1'b0;
        stat_ar_transactions <= 32'b0;
        stat_r_beats <= 32'b0;
        stat_aw_transactions <= 32'b0;
        stat_w_beats <= 32'b0;
        stat_b_responses <= 32'b0;
    end else begin
        if (rd_state == RD_IDLE && rd_claim) begin
            rd_owner <= rd_pick;
            rd_id_q <= rd_pick_id;
            rd_addr_q <= rd_pick_addr;
            rd_len_q <= rd_pick_len;
            rd_size_q <= rd_pick_size;
            rd_prot_q <= rd_pick_prot;
            rd_cache_q <= rd_pick_cache;
            rd_beat <= 8'b0;
            rd_state <= RD_ADDR;
            case (rd_pick)
                RD_OWNER_IC:   rd_rr <= 2'd1;
                RD_OWNER_DC:   rd_rr <= 2'd2;
                RD_OWNER_INST: rd_rr <= 2'd3;
                default:       rd_rr <= 2'd0;
            endcase
            if ((rd_pick == RD_OWNER_IC && ic_refill_addr[4:0] != 5'b0) ||
                (rd_pick == RD_OWNER_DC && dc_refill_addr[4:0] != 5'b0))
                axi_fault <= 1'b1;
        end else if (rd_state == RD_ADDR && rd_ar_fire) begin
            stat_ar_transactions <= stat_ar_transactions + 32'd1;
            rd_state <= RD_DATA;
        end else if (rd_state == RD_DATA && rd_fire) begin
            stat_r_beats <= stat_r_beats + 32'd1;
            if (!rd_response_good)
                axi_fault <= 1'b1;
            if (rlast || rd_expected_last) begin
                rd_state <= RD_IDLE;
                rd_owner <= RD_OWNER_NONE;
            end else begin
                rd_beat <= rd_beat + 8'd1;
            end
        end

        if (wr_state == WR_IDLE && wr_claim_wb) begin
            wr_owner <= WR_OWNER_WB;
            wr_id_q <= 4'h1;
            wr_addr_q <= {dc_writeback_addr[31:5], 5'b0};
            wr_len_q <= 8'd7;
            wr_beat <= 3'b0;
            wr_data_q <= dc_writeback_data;
            wr_strb_q <= 32'hffffffff;
            wr_aw_done <= 1'b0;
            wr_w_done <= 1'b0;
            wr_prot_q <= 3'b010;
            wr_cache_q <= 4'b1111;
            wr_state <= WR_SEND;
            if (dc_writeback_addr[4:0] != 5'b0)
                axi_fault <= 1'b1;
        end else if (wr_state == WR_IDLE && wr_claim_data) begin
            wr_owner <= WR_OWNER_DATA;
            wr_id_q <= 4'h3;
            wr_addr_q <= (data_size == 2'd2 && data_addr[1:0] != 2'b00) ?
                         {data_addr[31:2], 2'b00} : data_addr;
            wr_len_q <= 8'd0;
            wr_beat <= 3'b0;
            wr_data_q <= {224'b0, data_wdata};
            wr_strb_q <= {28'b0, data_wstrb};
            wr_aw_done <= 1'b0;
            wr_w_done <= 1'b0;
            wr_prot_q <= 3'b010;
            wr_cache_q <= 4'b0000;
            wr_state <= WR_SEND;
        end else if (wr_state == WR_SEND) begin
            if (wr_aw_fire) begin
                wr_aw_done <= 1'b1;
                stat_aw_transactions <= stat_aw_transactions + 32'd1;
            end
            if (wr_w_fire) begin
                stat_w_beats <= stat_w_beats + 32'd1;
                if (wlast) begin
                    wr_w_done <= 1'b1;
                end else begin
                    wr_beat <= wr_beat + 3'd1;
                end
            end
            if (wr_all_done)
                wr_state <= WR_RESP;
        end else if (wr_state == WR_RESP && wr_b_fire) begin
            stat_b_responses <= stat_b_responses + 32'd1;
            wr_state <= WR_IDLE;
            wr_owner <= WR_OWNER_NONE;
            if (!wr_response_good)
                axi_fault <= 1'b1;
        end
    end
end

endmodule
