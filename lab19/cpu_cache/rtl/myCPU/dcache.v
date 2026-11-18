// Lab18 data cache: 4 ways, 128 sets, 32-byte lines, write-back/write-allocate.
module dcache(
    input          clk,
    input          resetn,
    input          cpu_req,
    input          cpu_cacheable,
    input          cpu_wr,
    input  [1:0]   cpu_size,
    input  [3:0]   cpu_wstrb,
    input  [31:0]  cpu_addr,
    input  [31:0]  cpu_wdata,
    output         cpu_addr_ok,
    output         cpu_data_ok,
    output [31:0]  cpu_rdata,

    input          maint_req,
    input  [4:0]   maint_op,
    input  [31:0]  maint_vaddr,
    input  [31:0]  maint_paddr,
    input  [31:0]  maint_taglo,
    output         maint_addr_ok,
    output reg     maint_done,

    output         refill_req,
    output [31:0]  refill_addr,
    input          refill_addr_ok,
    input          refill_data_valid,
    input          refill_data_last,
    input  [31:0]  refill_data,

    output         writeback_req,
    output [31:0]  writeback_addr,
    output [255:0] writeback_data,
    input          writeback_addr_ok,
    input          writeback_done,

    output         uncache_req,
    output         uncache_wr,
    output [1:0]   uncache_size,
    output [3:0]   uncache_wstrb,
    output [31:0]  uncache_addr,
    output [31:0]  uncache_wdata,
    input          uncache_addr_ok,
    input          uncache_data_ok,
    input  [31:0]  uncache_rdata,

    input          bridge_fault,
    output reg [31:0] stat_hit,
    output reg [31:0] stat_miss,
    output reg [31:0] stat_writeback,
    output reg [31:0] stat_uncache,
    output reg        cache_fault
);

localparam [3:0] ST_RESET_CLEAR = 4'd0;
localparam [3:0] ST_IDLE        = 4'd1;
localparam [3:0] ST_LOOKUP      = 4'd2;
localparam [3:0] ST_WB_REQ      = 4'd3;
localparam [3:0] ST_WB_WAIT     = 4'd4;
localparam [3:0] ST_REFILL_REQ  = 4'd5;
localparam [3:0] ST_REFILL_DATA = 4'd6;
localparam [3:0] ST_UNC_REQ     = 4'd7;
localparam [3:0] ST_UNC_WAIT    = 4'd8;
localparam [3:0] ST_COMPLETE    = 4'd9;
localparam [3:0] ST_FAULT       = 4'd10;

reg [3:0] state;
reg reset_done;
reg [6:0] clear_index;
reg [19:0] tag_way0 [0:127];
reg [19:0] tag_way1 [0:127];
reg [19:0] tag_way2 [0:127];
reg [19:0] tag_way3 [0:127];
reg [255:0] line_way0 [0:127];
reg [255:0] line_way1 [0:127];
reg [255:0] line_way2 [0:127];
reg [255:0] line_way3 [0:127];
reg [127:0] valid_way0;
reg [127:0] valid_way1;
reg [127:0] valid_way2;
reg [127:0] valid_way3;
reg [127:0] dirty_way0;
reg [127:0] dirty_way1;
reg [127:0] dirty_way2;
reg [127:0] dirty_way3;
reg [1:0] replace_way [0:127];

reg [31:0] req_addr;
reg req_wr;
reg [1:0] req_size;
reg [3:0] req_wstrb;
reg [31:0] req_wdata;
reg [1:0] victim_way;
reg [2:0] refill_beat;
reg [255:0] refill_buffer;
reg [31:0] rdata;
reg [31:0] refill_addr_reg;
reg        wb_for_maint;

wire hit0;
wire hit1;
wire hit2;
wire hit3;
wire [3:0] hit_vector;
wire [2:0] hit_count;
reg [1:0] hit_way;
reg [255:0] hit_line;
wire [31:0] hit_word;
reg [1:0] choose_way;
reg chosen_valid;
reg chosen_dirty;
reg [255:0] chosen_line;
reg [31:0] chosen_tag;
wire [255:0] refill_line_now;
wire [255:0] refill_line_merged;
wire [31:0] refill_word;
reg [31:0] maint_selected_tag;
reg [255:0] maint_selected_line;
reg        maint_selected_valid;
reg        maint_selected_dirty;

assign cpu_addr_ok = reset_done && (state == ST_IDLE);
assign cpu_data_ok = (state == ST_COMPLETE);
assign maint_addr_ok = reset_done && (state == ST_IDLE);
assign cpu_rdata = rdata;
assign refill_req = (state == ST_REFILL_REQ);
assign refill_addr = refill_addr_reg;
assign writeback_req = (state == ST_WB_REQ);
assign writeback_addr = wb_for_maint ?
                        {maint_selected_tag[19:0], req_addr[11:5], 5'b0} :
                        {chosen_tag[19:0], req_addr[11:5], 5'b0};
assign writeback_data = wb_for_maint ? maint_selected_line : chosen_line;
assign uncache_req = (state == ST_UNC_REQ);
assign uncache_wr = req_wr;
assign uncache_size = req_size;
assign uncache_wstrb = req_wstrb;
assign uncache_addr = req_addr;
assign uncache_wdata = req_wdata;

assign hit0 = valid_way0[req_addr[11:5]] &&
              (tag_way0[req_addr[11:5]] == req_addr[31:12]);
assign hit1 = valid_way1[req_addr[11:5]] &&
              (tag_way1[req_addr[11:5]] == req_addr[31:12]);
assign hit2 = valid_way2[req_addr[11:5]] &&
              (tag_way2[req_addr[11:5]] == req_addr[31:12]);
assign hit3 = valid_way3[req_addr[11:5]] &&
              (tag_way3[req_addr[11:5]] == req_addr[31:12]);
assign hit_vector = {hit3, hit2, hit1, hit0};
assign hit_count = {2'b0, hit0} + {2'b0, hit1} +
                   {2'b0, hit2} + {2'b0, hit3};

function [31:0] select_word;
    input [255:0] line_value;
    input [2:0] word_index;
    begin
        case (word_index)
            3'd0: select_word = line_value[31:0];
            3'd1: select_word = line_value[63:32];
            3'd2: select_word = line_value[95:64];
            3'd3: select_word = line_value[127:96];
            3'd4: select_word = line_value[159:128];
            3'd5: select_word = line_value[191:160];
            3'd6: select_word = line_value[223:192];
            default: select_word = line_value[255:224];
        endcase
    end
endfunction

function [255:0] put_word;
    input [255:0] line_value;
    input [2:0] word_index;
    input [31:0] word_value;
    reg [255:0] temp;
    begin
        temp = line_value;
        temp[word_index*32 +: 32] = word_value;
        put_word = temp;
    end
endfunction

function [255:0] merge_store;
    input [255:0] line_value;
    input [2:0] word_index;
    input [3:0] byte_enable;
    input [31:0] word_value;
    reg [255:0] temp;
    integer lane;
    begin
        temp = line_value;
        for (lane = 0; lane < 4; lane = lane + 1) begin
            if (byte_enable[lane])
                temp[word_index*32 + lane*8 +: 8] = word_value[lane*8 +: 8];
        end
        merge_store = temp;
    end
endfunction

always @* begin
    hit_way = 2'd0;
    if (hit0) hit_way = 2'd0;
    if (hit1) hit_way = 2'd1;
    if (hit2) hit_way = 2'd2;
    if (hit3) hit_way = 2'd3;
    case (hit_way)
        2'd0: hit_line = line_way0[req_addr[11:5]];
        2'd1: hit_line = line_way1[req_addr[11:5]];
        2'd2: hit_line = line_way2[req_addr[11:5]];
        default: hit_line = line_way3[req_addr[11:5]];
    endcase
end

always @* begin
    maint_selected_tag = 32'b0;
    maint_selected_line = 256'b0;
    maint_selected_valid = 1'b0;
    maint_selected_dirty = 1'b0;
    case (victim_way)
        2'd0: begin
            maint_selected_tag = {12'b0, tag_way0[req_addr[11:5]]};
            maint_selected_line = line_way0[req_addr[11:5]];
            maint_selected_valid = valid_way0[req_addr[11:5]];
            maint_selected_dirty = dirty_way0[req_addr[11:5]];
        end
        2'd1: begin
            maint_selected_tag = {12'b0, tag_way1[req_addr[11:5]]};
            maint_selected_line = line_way1[req_addr[11:5]];
            maint_selected_valid = valid_way1[req_addr[11:5]];
            maint_selected_dirty = dirty_way1[req_addr[11:5]];
        end
        2'd2: begin
            maint_selected_tag = {12'b0, tag_way2[req_addr[11:5]]};
            maint_selected_line = line_way2[req_addr[11:5]];
            maint_selected_valid = valid_way2[req_addr[11:5]];
            maint_selected_dirty = dirty_way2[req_addr[11:5]];
        end
        default: begin
            maint_selected_tag = {12'b0, tag_way3[req_addr[11:5]]};
            maint_selected_line = line_way3[req_addr[11:5]];
            maint_selected_valid = valid_way3[req_addr[11:5]];
            maint_selected_dirty = dirty_way3[req_addr[11:5]];
        end
    endcase
end

reg maint_hit;
reg [1:0] maint_hit_way;
always @* begin
    maint_hit = 1'b0;
    maint_hit_way = 2'd0;
    if (valid_way0[maint_paddr[11:5]] && tag_way0[maint_paddr[11:5]] == maint_paddr[31:12]) begin
        maint_hit = 1'b1;
        maint_hit_way = 2'd0;
    end
    if (valid_way1[maint_paddr[11:5]] && tag_way1[maint_paddr[11:5]] == maint_paddr[31:12]) begin
        maint_hit = 1'b1;
        maint_hit_way = 2'd1;
    end
    if (valid_way2[maint_paddr[11:5]] && tag_way2[maint_paddr[11:5]] == maint_paddr[31:12]) begin
        maint_hit = 1'b1;
        maint_hit_way = 2'd2;
    end
    if (valid_way3[maint_paddr[11:5]] && tag_way3[maint_paddr[11:5]] == maint_paddr[31:12]) begin
        maint_hit = 1'b1;
        maint_hit_way = 2'd3;
    end
end
assign hit_word = select_word(hit_line, req_addr[4:2]);

always @* begin
    choose_way = replace_way[req_addr[11:5]];
    if (!valid_way0[req_addr[11:5]])
        choose_way = 2'd0;
    else if (!valid_way1[req_addr[11:5]])
        choose_way = 2'd1;
    else if (!valid_way2[req_addr[11:5]])
        choose_way = 2'd2;
    else if (!valid_way3[req_addr[11:5]])
        choose_way = 2'd3;

    chosen_valid = 1'b0;
    chosen_dirty = 1'b0;
    chosen_line = 256'b0;
    chosen_tag = 20'b0;
    case (choose_way)
        2'd0: begin
            chosen_valid = valid_way0[req_addr[11:5]];
            chosen_dirty = dirty_way0[req_addr[11:5]];
            chosen_line = line_way0[req_addr[11:5]];
            chosen_tag = tag_way0[req_addr[11:5]];
        end
        2'd1: begin
            chosen_valid = valid_way1[req_addr[11:5]];
            chosen_dirty = dirty_way1[req_addr[11:5]];
            chosen_line = line_way1[req_addr[11:5]];
            chosen_tag = tag_way1[req_addr[11:5]];
        end
        2'd2: begin
            chosen_valid = valid_way2[req_addr[11:5]];
            chosen_dirty = dirty_way2[req_addr[11:5]];
            chosen_line = line_way2[req_addr[11:5]];
            chosen_tag = tag_way2[req_addr[11:5]];
        end
        default: begin
            chosen_valid = valid_way3[req_addr[11:5]];
            chosen_dirty = dirty_way3[req_addr[11:5]];
            chosen_line = line_way3[req_addr[11:5]];
            chosen_tag = tag_way3[req_addr[11:5]];
        end
    endcase
end

assign refill_line_now = put_word(refill_buffer, refill_beat, refill_data);
assign refill_line_merged = req_wr ?
    merge_store(refill_line_now, req_addr[4:2], req_wstrb, req_wdata) :
    refill_line_now;
assign refill_word = select_word(refill_line_now, req_addr[4:2]);

always @(posedge clk) begin
    if (!resetn) begin
        state <= ST_RESET_CLEAR;
        reset_done <= 1'b0;
        clear_index <= 7'b0;
        req_addr <= 32'b0;
        req_wr <= 1'b0;
        req_size <= 2'b0;
        req_wstrb <= 4'b0;
        req_wdata <= 32'b0;
        victim_way <= 2'b0;
        refill_beat <= 3'b0;
        refill_buffer <= 256'b0;
        rdata <= 32'b0;
        refill_addr_reg <= 32'b0;
        stat_hit <= 32'b0;
        stat_miss <= 32'b0;
        stat_writeback <= 32'b0;
        stat_uncache <= 32'b0;
        cache_fault <= 1'b0;
        maint_done <= 1'b0;
        wb_for_maint <= 1'b0;
    end else begin
        maint_done <= 1'b0;
        if (bridge_fault)
            cache_fault <= 1'b1;
        case (state)
            ST_RESET_CLEAR: begin
                valid_way0[clear_index] <= 1'b0;
                valid_way1[clear_index] <= 1'b0;
                valid_way2[clear_index] <= 1'b0;
                valid_way3[clear_index] <= 1'b0;
                dirty_way0[clear_index] <= 1'b0;
                dirty_way1[clear_index] <= 1'b0;
                dirty_way2[clear_index] <= 1'b0;
                dirty_way3[clear_index] <= 1'b0;
                replace_way[clear_index] <= 2'b0;
                if (clear_index == 7'd127) begin
                    reset_done <= 1'b1;
                    state <= ST_IDLE;
                end else begin
                    clear_index <= clear_index + 7'd1;
                end
            end

            ST_IDLE: begin
                if (maint_req && maint_addr_ok) begin
                    req_addr <= maint_paddr;
                    wb_for_maint <= 1'b0;
                    case (maint_op)
                        5'h01: begin
                            victim_way <= maint_vaddr[13:12];
                            case (maint_vaddr[13:12])
                                2'd0: if (valid_way0[maint_vaddr[11:5]] && dirty_way0[maint_vaddr[11:5]]) begin wb_for_maint <= 1'b1; state <= ST_WB_REQ; end else begin valid_way0[maint_vaddr[11:5]] <= 1'b0; dirty_way0[maint_vaddr[11:5]] <= 1'b0; maint_done <= 1'b1; end
                                2'd1: if (valid_way1[maint_vaddr[11:5]] && dirty_way1[maint_vaddr[11:5]]) begin wb_for_maint <= 1'b1; state <= ST_WB_REQ; end else begin valid_way1[maint_vaddr[11:5]] <= 1'b0; dirty_way1[maint_vaddr[11:5]] <= 1'b0; maint_done <= 1'b1; end
                                2'd2: if (valid_way2[maint_vaddr[11:5]] && dirty_way2[maint_vaddr[11:5]]) begin wb_for_maint <= 1'b1; state <= ST_WB_REQ; end else begin valid_way2[maint_vaddr[11:5]] <= 1'b0; dirty_way2[maint_vaddr[11:5]] <= 1'b0; maint_done <= 1'b1; end
                                default: if (valid_way3[maint_vaddr[11:5]] && dirty_way3[maint_vaddr[11:5]]) begin wb_for_maint <= 1'b1; state <= ST_WB_REQ; end else begin valid_way3[maint_vaddr[11:5]] <= 1'b0; dirty_way3[maint_vaddr[11:5]] <= 1'b0; maint_done <= 1'b1; end
                            endcase
                        end
                        5'h09: begin
                            case (maint_vaddr[13:12])
                                2'd0: begin tag_way0[maint_vaddr[11:5]] <= maint_taglo[31:12]; valid_way0[maint_vaddr[11:5]] <= |maint_taglo[7:6]; dirty_way0[maint_vaddr[11:5]] <= (maint_taglo[7:6] == 2'b11); end
                                2'd1: begin tag_way1[maint_vaddr[11:5]] <= maint_taglo[31:12]; valid_way1[maint_vaddr[11:5]] <= |maint_taglo[7:6]; dirty_way1[maint_vaddr[11:5]] <= (maint_taglo[7:6] == 2'b11); end
                                2'd2: begin tag_way2[maint_vaddr[11:5]] <= maint_taglo[31:12]; valid_way2[maint_vaddr[11:5]] <= |maint_taglo[7:6]; dirty_way2[maint_vaddr[11:5]] <= (maint_taglo[7:6] == 2'b11); end
                                default: begin tag_way3[maint_vaddr[11:5]] <= maint_taglo[31:12]; valid_way3[maint_vaddr[11:5]] <= |maint_taglo[7:6]; dirty_way3[maint_vaddr[11:5]] <= (maint_taglo[7:6] == 2'b11); end
                            endcase
                            maint_done <= 1'b1;
                        end
                        5'h11, 5'h15: begin
                            if (maint_hit) begin
                                victim_way <= maint_hit_way;
                                wb_for_maint <= (maint_op == 5'h15);
                                req_addr <= maint_paddr;
                                if ((maint_op == 5'h15) &&
                                    ((maint_hit_way == 2'd0 && dirty_way0[maint_paddr[11:5]]) ||
                                     (maint_hit_way == 2'd1 && dirty_way1[maint_paddr[11:5]]) ||
                                     (maint_hit_way == 2'd2 && dirty_way2[maint_paddr[11:5]]) ||
                                     (maint_hit_way == 2'd3 && dirty_way3[maint_paddr[11:5]]))) begin
                                    state <= ST_WB_REQ;
                                end else begin
                                    case (maint_hit_way)
                                        2'd0: begin valid_way0[maint_paddr[11:5]] <= 1'b0; dirty_way0[maint_paddr[11:5]] <= 1'b0; end
                                        2'd1: begin valid_way1[maint_paddr[11:5]] <= 1'b0; dirty_way1[maint_paddr[11:5]] <= 1'b0; end
                                        2'd2: begin valid_way2[maint_paddr[11:5]] <= 1'b0; dirty_way2[maint_paddr[11:5]] <= 1'b0; end
                                        default: begin valid_way3[maint_paddr[11:5]] <= 1'b0; dirty_way3[maint_paddr[11:5]] <= 1'b0; end
                                    endcase
                                    wb_for_maint <= 1'b0;
                                    maint_done <= 1'b1;
                                end
                            end else begin
                                maint_done <= 1'b1;
                            end
                        end
                        default: begin
                            cache_fault <= 1'b1;
                            maint_done <= 1'b1;
                        end
                    endcase
                end else if (cpu_req && cpu_addr_ok) begin
                    req_addr <= cpu_addr;
                    req_wr <= cpu_wr;
                    req_size <= cpu_size;
                    req_wstrb <= cpu_wstrb;
                    req_wdata <= cpu_wdata;
                    if (cpu_cacheable) begin
                        state <= ST_LOOKUP;
                    end else begin
                        stat_uncache <= stat_uncache + 32'd1;
                        state <= ST_UNC_REQ;
                    end
                end
            end

            ST_LOOKUP: begin
                if (hit_count > 3'd1) begin
                    cache_fault <= 1'b1;
                    state <= ST_FAULT;
                end else if (hit_vector != 4'b0) begin
                    stat_hit <= stat_hit + 32'd1;
                    replace_way[req_addr[11:5]] <= hit_way + 2'd1;
                    if (req_wr) begin
                        case (hit_way)
                            2'd0: begin
                                line_way0[req_addr[11:5]] <= merge_store(hit_line, req_addr[4:2], req_wstrb, req_wdata);
                                dirty_way0[req_addr[11:5]] <= 1'b1;
                            end
                            2'd1: begin
                                line_way1[req_addr[11:5]] <= merge_store(hit_line, req_addr[4:2], req_wstrb, req_wdata);
                                dirty_way1[req_addr[11:5]] <= 1'b1;
                            end
                            2'd2: begin
                                line_way2[req_addr[11:5]] <= merge_store(hit_line, req_addr[4:2], req_wstrb, req_wdata);
                                dirty_way2[req_addr[11:5]] <= 1'b1;
                            end
                            default: begin
                                line_way3[req_addr[11:5]] <= merge_store(hit_line, req_addr[4:2], req_wstrb, req_wdata);
                                dirty_way3[req_addr[11:5]] <= 1'b1;
                            end
                        endcase
                    end else begin
                        rdata <= hit_word;
                    end
                    state <= ST_COMPLETE;
                end else begin
                    stat_miss <= stat_miss + 32'd1;
                    victim_way <= choose_way;
                    refill_addr_reg <= {req_addr[31:5], 5'b0};
                    if (chosen_valid && chosen_dirty)
                        state <= ST_WB_REQ;
                    else
                        state <= ST_REFILL_REQ;
                end
            end

            ST_WB_REQ: begin
                if (writeback_addr_ok)
                    state <= ST_WB_WAIT;
            end

            ST_WB_WAIT: begin
                if (writeback_done && !bridge_fault) begin
                    stat_writeback <= stat_writeback + 32'd1;
                    case (victim_way)
                        2'd0: begin valid_way0[req_addr[11:5]] <= 1'b0; dirty_way0[req_addr[11:5]] <= 1'b0; end
                        2'd1: begin valid_way1[req_addr[11:5]] <= 1'b0; dirty_way1[req_addr[11:5]] <= 1'b0; end
                        2'd2: begin valid_way2[req_addr[11:5]] <= 1'b0; dirty_way2[req_addr[11:5]] <= 1'b0; end
                        default: begin valid_way3[req_addr[11:5]] <= 1'b0; dirty_way3[req_addr[11:5]] <= 1'b0; end
                    endcase
                    if (wb_for_maint) begin
                        wb_for_maint <= 1'b0;
                        maint_done <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        state <= ST_REFILL_REQ;
                    end
                end else if (bridge_fault) begin
                    state <= ST_FAULT;
                end
            end

            ST_REFILL_REQ: begin
                if (refill_addr_ok) begin
                    refill_beat <= 3'b0;
                    refill_buffer <= 256'b0;
                    state <= ST_REFILL_DATA;
                end
            end

            ST_REFILL_DATA: begin
                if (bridge_fault) begin
                    state <= ST_FAULT;
                end else if (refill_data_valid) begin
                    refill_buffer <= refill_line_now;
                    if (refill_data_last !== (refill_beat == 3'd7)) begin
                        cache_fault <= 1'b1;
                        state <= ST_FAULT;
                    end else if (refill_beat == 3'd7) begin
                        case (victim_way)
                            2'd0: begin
                                tag_way0[req_addr[11:5]] <= req_addr[31:12];
                                line_way0[req_addr[11:5]] <= refill_line_merged;
                                valid_way0[req_addr[11:5]] <= 1'b1;
                                dirty_way0[req_addr[11:5]] <= req_wr;
                            end
                            2'd1: begin
                                tag_way1[req_addr[11:5]] <= req_addr[31:12];
                                line_way1[req_addr[11:5]] <= refill_line_merged;
                                valid_way1[req_addr[11:5]] <= 1'b1;
                                dirty_way1[req_addr[11:5]] <= req_wr;
                            end
                            2'd2: begin
                                tag_way2[req_addr[11:5]] <= req_addr[31:12];
                                line_way2[req_addr[11:5]] <= refill_line_merged;
                                valid_way2[req_addr[11:5]] <= 1'b1;
                                dirty_way2[req_addr[11:5]] <= req_wr;
                            end
                            default: begin
                                tag_way3[req_addr[11:5]] <= req_addr[31:12];
                                line_way3[req_addr[11:5]] <= refill_line_merged;
                                valid_way3[req_addr[11:5]] <= 1'b1;
                                dirty_way3[req_addr[11:5]] <= req_wr;
                            end
                        endcase
                        replace_way[req_addr[11:5]] <= victim_way + 2'd1;
                        if (!req_wr)
                            rdata <= refill_word;
                        state <= ST_COMPLETE;
                    end else begin
                        refill_beat <= refill_beat + 3'd1;
                    end
                end
            end

            ST_UNC_REQ: begin
                if (uncache_addr_ok)
                    state <= ST_UNC_WAIT;
            end

            ST_UNC_WAIT: begin
                if (uncache_data_ok) begin
                    rdata <= uncache_rdata;
                    state <= ST_COMPLETE;
                end else if (bridge_fault) begin
                    state <= ST_FAULT;
                end
            end

            ST_COMPLETE: state <= ST_IDLE;
            ST_FAULT: state <= ST_FAULT;
            default: state <= ST_FAULT;
        endcase
    end
end

endmodule
