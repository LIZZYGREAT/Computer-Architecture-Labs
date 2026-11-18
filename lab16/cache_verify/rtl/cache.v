`default_nettype none

// Lab16 stand-alone cache: 4 ways, 256 sets, 16-byte lines.
module cache(
    input  wire        clk_g,
    input  wire        resetn,
    input  wire        valid,
    input  wire        op,
    input  wire [7:0]  index,
    input  wire [19:0] tag,
    input  wire [3:0]  offset,
    input  wire [3:0]  wstrb,
    input  wire [31:0] wdata,
    output wire        addr_ok,
    output wire        data_ok,
    output reg  [31:0] rdata,
    output wire        rd_req,
    output wire [2:0]  rd_type,
    output wire [31:0] rd_addr,
    input  wire        rd_rdy,
    input  wire        ret_valid,
    input  wire        ret_last,
    input  wire [31:0] ret_data,
    output wire        wr_req,
    output wire [2:0]  wr_type,
    output wire [31:0] wr_addr,
    output wire [3:0]  wr_wstrb,
    output wire [127:0] wr_data,
    input  wire        wr_rdy
);

localparam [2:0] ST_RESET_CLEAR = 3'd0;
localparam [2:0] ST_IDLE        = 3'd1;
localparam [2:0] ST_LOOKUP      = 3'd2;
localparam [2:0] ST_WRITEBACK   = 3'd3;
localparam [2:0] ST_REFILL_REQ  = 3'd4;
localparam [2:0] ST_REFILL_DATA = 3'd5;
localparam [2:0] ST_COMPLETE    = 3'd6;
localparam [2:0] TYPE_LINE      = 3'b100;

reg [2:0] state;
reg       reset_done;
reg [7:0] clear_index;

// Tag/data RAMs are intentionally left uncleared. Valid and dirty metadata
// are cleared one set per cycle before the cache accepts a CPU request.
reg [19:0] tag_way0 [0:255];
reg [19:0] tag_way1 [0:255];
reg [19:0] tag_way2 [0:255];
reg [19:0] tag_way3 [0:255];
reg [127:0] line_way0 [0:255];
reg [127:0] line_way1 [0:255];
reg [127:0] line_way2 [0:255];
reg [127:0] line_way3 [0:255];
reg [255:0] valid_way0;
reg [255:0] valid_way1;
reg [255:0] valid_way2;
reg [255:0] valid_way3;
reg [255:0] dirty_way0;
reg [255:0] dirty_way1;
reg [255:0] dirty_way2;
reg [255:0] dirty_way3;
reg [1:0] replace_way [0:255];

reg        req_op;
reg [7:0]  req_index;
reg [19:0] req_tag;
reg [3:0]  req_offset;
reg [3:0]  req_wstrb;
reg [31:0] req_wdata;

reg [1:0]  victim_way;
reg [1:0]  refill_count;
reg [127:0] refill_buffer;
reg [31:0] rd_addr_reg;
reg [31:0] wr_addr_reg;
reg [127:0] wr_data_reg;

wire hit0;
wire hit1;
wire hit2;
wire hit3;
wire [3:0] hit_vector;
wire [2:0] hit_count;
wire hit;
reg [1:0] hit_way;
reg [127:0] hit_line;
wire [31:0] hit_word;
wire [31:0] hit_merged_word;

reg [1:0] choose_way;
reg chosen_valid;
reg chosen_dirty;
reg [19:0] chosen_tag;
reg [127:0] chosen_line;

wire [127:0] refill_line_now;
wire [31:0] refill_word;
wire [31:0] refill_merged_word;
wire [127:0] refill_final_line;
wire [31:0] refill_result_word;

assign addr_ok = reset_done && (state == ST_IDLE);
assign data_ok = (state == ST_COMPLETE);
assign rd_req = (state == ST_REFILL_REQ);
assign rd_type = TYPE_LINE;
assign rd_addr = rd_addr_reg;
assign wr_req = (state == ST_WRITEBACK);
assign wr_type = TYPE_LINE;
assign wr_addr = wr_addr_reg;
assign wr_wstrb = 4'b1111;
assign wr_data = wr_data_reg;

assign hit0 = valid_way0[req_index] && (tag_way0[req_index] == req_tag);
assign hit1 = valid_way1[req_index] && (tag_way1[req_index] == req_tag);
assign hit2 = valid_way2[req_index] && (tag_way2[req_index] == req_tag);
assign hit3 = valid_way3[req_index] && (tag_way3[req_index] == req_tag);
assign hit_vector = {hit3, hit2, hit1, hit0};
assign hit_count = {2'b0, hit0} + {2'b0, hit1} + {2'b0, hit2} + {2'b0, hit3};
assign hit = |hit_vector;

function [31:0] select_word;
    input [127:0] line_value;
    input [1:0] word_index;
    begin
        case (word_index)
            2'd0: select_word = line_value[31:0];
            2'd1: select_word = line_value[63:32];
            2'd2: select_word = line_value[95:64];
            default: select_word = line_value[127:96];
        endcase
    end
endfunction

function [127:0] replace_word;
    input [127:0] line_value;
    input [1:0] word_index;
    input [31:0] word_value;
    begin
        replace_word = line_value;
        case (word_index)
            2'd0: replace_word[31:0] = word_value;
            2'd1: replace_word[63:32] = word_value;
            2'd2: replace_word[95:64] = word_value;
            default: replace_word[127:96] = word_value;
        endcase
    end
endfunction

function [31:0] merge_bytes;
    input [31:0] old_word;
    input [31:0] new_word;
    input [3:0] byte_enable;
    begin
        merge_bytes = old_word;
        if (byte_enable[0]) merge_bytes[7:0]   = new_word[7:0];
        if (byte_enable[1]) merge_bytes[15:8]  = new_word[15:8];
        if (byte_enable[2]) merge_bytes[23:16] = new_word[23:16];
        if (byte_enable[3]) merge_bytes[31:24] = new_word[31:24];
    end
endfunction

always @* begin
    hit_way = 2'd0;
    if (hit0) hit_way = 2'd0;
    if (hit1) hit_way = 2'd1;
    if (hit2) hit_way = 2'd2;
    if (hit3) hit_way = 2'd3;
    case (hit_way)
        2'd0: hit_line = line_way0[req_index];
        2'd1: hit_line = line_way1[req_index];
        2'd2: hit_line = line_way2[req_index];
        default: hit_line = line_way3[req_index];
    endcase
end

assign hit_word = select_word(hit_line, req_offset[3:2]);
assign hit_merged_word = merge_bytes(hit_word, req_wdata, req_wstrb);

always @* begin
    choose_way = replace_way[req_index];
    if (!valid_way0[req_index])
        choose_way = 2'd0;
    else if (!valid_way1[req_index])
        choose_way = 2'd1;
    else if (!valid_way2[req_index])
        choose_way = 2'd2;
    else if (!valid_way3[req_index])
        choose_way = 2'd3;

    chosen_valid = 1'b0;
    chosen_dirty = 1'b0;
    chosen_tag = 20'b0;
    chosen_line = 128'b0;
    case (choose_way)
        2'd0: begin
            chosen_valid = valid_way0[req_index];
            chosen_dirty = dirty_way0[req_index];
            chosen_tag = tag_way0[req_index];
            chosen_line = line_way0[req_index];
        end
        2'd1: begin
            chosen_valid = valid_way1[req_index];
            chosen_dirty = dirty_way1[req_index];
            chosen_tag = tag_way1[req_index];
            chosen_line = line_way1[req_index];
        end
        2'd2: begin
            chosen_valid = valid_way2[req_index];
            chosen_dirty = dirty_way2[req_index];
            chosen_tag = tag_way2[req_index];
            chosen_line = line_way2[req_index];
        end
        default: begin
            chosen_valid = valid_way3[req_index];
            chosen_dirty = dirty_way3[req_index];
            chosen_tag = tag_way3[req_index];
            chosen_line = line_way3[req_index];
        end
    endcase
end

assign refill_line_now = {ret_data, refill_buffer[95:0]};
assign refill_word = select_word(refill_line_now, req_offset[3:2]);
assign refill_merged_word = merge_bytes(refill_word, req_wdata, req_wstrb);
assign refill_final_line = req_op ?
                           replace_word(refill_line_now, req_offset[3:2], refill_merged_word) :
                           refill_line_now;
assign refill_result_word = req_op ? refill_merged_word : refill_word;

always @(posedge clk_g) begin
    if (!resetn) begin
        state <= ST_RESET_CLEAR;
        reset_done <= 1'b0;
        clear_index <= 8'b0;
        req_op <= 1'b0;
        req_index <= 8'b0;
        req_tag <= 20'b0;
        req_offset <= 4'b0;
        req_wstrb <= 4'b0;
        req_wdata <= 32'b0;
        victim_way <= 2'b0;
        refill_count <= 2'b0;
        refill_buffer <= 128'b0;
        rd_addr_reg <= 32'b0;
        wr_addr_reg <= 32'b0;
        wr_data_reg <= 128'b0;
        rdata <= 32'b0;
    end else begin
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
                if (clear_index == 8'hff) begin
                    reset_done <= 1'b1;
                    state <= ST_IDLE;
                end else begin
                    clear_index <= clear_index + 8'd1;
                end
            end

            ST_IDLE: begin
                if (valid && addr_ok) begin
                    req_op <= op;
                    req_index <= index;
                    req_tag <= tag;
                    req_offset <= offset;
                    req_wstrb <= wstrb;
                    req_wdata <= wdata;
                    state <= ST_LOOKUP;
                end
            end

            ST_LOOKUP: begin
                if (hit) begin
                    if (req_op) begin
                        rdata <= hit_merged_word;
                        case (hit_way)
                            2'd0: begin
                                line_way0[req_index] <= replace_word(line_way0[req_index], req_offset[3:2], hit_merged_word);
                                dirty_way0[req_index] <= 1'b1;
                            end
                            2'd1: begin
                                line_way1[req_index] <= replace_word(line_way1[req_index], req_offset[3:2], hit_merged_word);
                                dirty_way1[req_index] <= 1'b1;
                            end
                            2'd2: begin
                                line_way2[req_index] <= replace_word(line_way2[req_index], req_offset[3:2], hit_merged_word);
                                dirty_way2[req_index] <= 1'b1;
                            end
                            default: begin
                                line_way3[req_index] <= replace_word(line_way3[req_index], req_offset[3:2], hit_merged_word);
                                dirty_way3[req_index] <= 1'b1;
                            end
                        endcase
                    end else begin
                        rdata <= hit_word;
                    end
                    state <= ST_COMPLETE;
                end else begin
                    rd_addr_reg <= {req_tag, req_index, 4'b0000};
                    victim_way <= choose_way;
                    if (chosen_valid && chosen_dirty) begin
                        wr_addr_reg <= {chosen_tag, req_index, 4'b0000};
                        wr_data_reg <= chosen_line;
                        state <= ST_WRITEBACK;
                    end else begin
                        state <= ST_REFILL_REQ;
                    end
                end
            end

            ST_WRITEBACK: begin
                // wr_rdy is the one-cycle acceptance of the whole line.
                // The interface has no separate write-completion response.
                if (wr_rdy)
                    state <= ST_REFILL_REQ;
            end

            ST_REFILL_REQ: begin
                if (rd_rdy) begin
                    refill_count <= 2'b0;
                    refill_buffer <= 128'b0;
                    state <= ST_REFILL_DATA;
                end
            end

            ST_REFILL_DATA: begin
                if (ret_valid) begin
                    case (refill_count)
                        2'd0: refill_buffer[31:0] <= ret_data;
                        2'd1: refill_buffer[63:32] <= ret_data;
                        2'd2: refill_buffer[95:64] <= ret_data;
                        default: refill_buffer[127:96] <= ret_data;
                    endcase

                    if (ret_last && (refill_count == 2'd3)) begin
                        rdata <= refill_result_word;
                        case (victim_way)
                            2'd0: begin
                                tag_way0[req_index] <= req_tag;
                                line_way0[req_index] <= refill_final_line;
                                valid_way0[req_index] <= 1'b1;
                                dirty_way0[req_index] <= req_op;
                            end
                            2'd1: begin
                                tag_way1[req_index] <= req_tag;
                                line_way1[req_index] <= refill_final_line;
                                valid_way1[req_index] <= 1'b1;
                                dirty_way1[req_index] <= req_op;
                            end
                            2'd2: begin
                                tag_way2[req_index] <= req_tag;
                                line_way2[req_index] <= refill_final_line;
                                valid_way2[req_index] <= 1'b1;
                                dirty_way2[req_index] <= req_op;
                            end
                            default: begin
                                tag_way3[req_index] <= req_tag;
                                line_way3[req_index] <= refill_final_line;
                                valid_way3[req_index] <= 1'b1;
                                dirty_way3[req_index] <= req_op;
                            end
                        endcase
                        replace_way[req_index] <= victim_way + 2'd1;
                        state <= ST_COMPLETE;
                    end else if (!ret_last && (refill_count != 2'd3)) begin
                        refill_count <= refill_count + 2'd1;
                    end
                end
            end

            ST_COMPLETE: begin
                state <= ST_IDLE;
            end

            default: begin
                state <= ST_RESET_CLEAR;
                reset_done <= 1'b0;
                clear_index <= 8'b0;
            end
        endcase
    end
end

`ifndef SYNTHESIS
always @(posedge clk_g) begin
    if (resetn && (state == ST_LOOKUP) && (hit_count > 3'd1))
        $fatal(1, "CACHE_ASSERT_FAIL=multiple_way_hit index=%02x tag=%05x", req_index, req_tag);
    if (resetn && (state == ST_REFILL_DATA) && ret_valid &&
        (ret_last !== (refill_count == 2'd3)))
        $fatal(1, "CACHE_ASSERT_FAIL=refill_last_beat count=%0d last=%b", refill_count, ret_last);
end
`endif

endmodule

`default_nettype wire
