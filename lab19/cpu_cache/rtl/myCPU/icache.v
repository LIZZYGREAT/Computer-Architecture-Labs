// Lab17 instruction cache: 4 ways, 128 sets, 32-byte lines.
module icache(
    input          clk,
    input          resetn,
    input          cpu_req,
    input          cpu_cacheable,
    input  [31:0]  cpu_addr,
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

    output         uncache_req,
    output [31:0]  uncache_addr,
    input          uncache_addr_ok,
    input          uncache_data_ok,
    input  [31:0]  uncache_data,

    output reg [31:0] stat_hit,
    output reg [31:0] stat_miss,
    output reg [31:0] stat_refill,
    output reg [31:0] stat_uncache_read,
    output reg        cache_fault
);

localparam [3:0] ST_RESET_CLEAR = 4'd0;
localparam [3:0] ST_IDLE        = 4'd1;
localparam [3:0] ST_LOOKUP      = 4'd2;
localparam [3:0] ST_REFILL_REQ  = 4'd3;
localparam [3:0] ST_REFILL_DATA = 4'd4;
localparam [3:0] ST_UNC_REQ     = 4'd5;
localparam [3:0] ST_UNC_WAIT    = 4'd6;
localparam [3:0] ST_COMPLETE    = 4'd7;
localparam [3:0] ST_FAULT       = 4'd8;

reg [3:0] state;
reg       reset_done;
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
reg [1:0] replace_way [0:127];

reg [31:0] req_addr;
reg [1:0]  victim_way;
reg [2:0]  refill_beat;
reg [255:0] refill_buffer;
reg [31:0] rdata;
reg [31:0] refill_addr_reg;

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
reg [255:0] chosen_line;
wire [255:0] refill_line_now;
wire [31:0] refill_word;

assign cpu_addr_ok = reset_done && (state == ST_IDLE);
assign cpu_data_ok = (state == ST_COMPLETE);
assign maint_addr_ok = reset_done && (state == ST_IDLE);
assign cpu_rdata = rdata;
assign refill_req = (state == ST_REFILL_REQ);
assign refill_addr = refill_addr_reg;
assign uncache_req = (state == ST_UNC_REQ);
assign uncache_addr = req_addr;

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
    chosen_line = 256'b0;
    case (choose_way)
        2'd0: begin
            chosen_valid = valid_way0[req_addr[11:5]];
            chosen_line = line_way0[req_addr[11:5]];
        end
        2'd1: begin
            chosen_valid = valid_way1[req_addr[11:5]];
            chosen_line = line_way1[req_addr[11:5]];
        end
        2'd2: begin
            chosen_valid = valid_way2[req_addr[11:5]];
            chosen_line = line_way2[req_addr[11:5]];
        end
        default: begin
            chosen_valid = valid_way3[req_addr[11:5]];
            chosen_line = line_way3[req_addr[11:5]];
        end
    endcase
end

assign refill_line_now = {refill_data, refill_buffer[223:0]};
assign refill_word = select_word(refill_line_now, req_addr[4:2]);

always @(posedge clk) begin
    if (!resetn) begin
        state <= ST_RESET_CLEAR;
        reset_done <= 1'b0;
        clear_index <= 7'b0;
        req_addr <= 32'b0;
        victim_way <= 2'b0;
        refill_beat <= 3'b0;
        refill_buffer <= 256'b0;
        rdata <= 32'b0;
        refill_addr_reg <= 32'b0;
        stat_hit <= 32'b0;
        stat_miss <= 32'b0;
        stat_refill <= 32'b0;
        stat_uncache_read <= 32'b0;
        cache_fault <= 1'b0;
        maint_done <= 1'b0;
    end else begin
        maint_done <= 1'b0;
        case (state)
            ST_RESET_CLEAR: begin
                valid_way0[clear_index] <= 1'b0;
                valid_way1[clear_index] <= 1'b0;
                valid_way2[clear_index] <= 1'b0;
                valid_way3[clear_index] <= 1'b0;
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
                    case (maint_op)
                        5'h00: begin
                            case (maint_vaddr[13:12])
                                2'd0: valid_way0[maint_vaddr[11:5]] <= 1'b0;
                                2'd1: valid_way1[maint_vaddr[11:5]] <= 1'b0;
                                2'd2: valid_way2[maint_vaddr[11:5]] <= 1'b0;
                                default: valid_way3[maint_vaddr[11:5]] <= 1'b0;
                            endcase
                        end
                        5'h08: begin
                            case (maint_vaddr[13:12])
                                2'd0: begin
                                    tag_way0[maint_vaddr[11:5]] <= maint_taglo[31:12];
                                    valid_way0[maint_vaddr[11:5]] <= |maint_taglo[7:6];
                                end
                                2'd1: begin
                                    tag_way1[maint_vaddr[11:5]] <= maint_taglo[31:12];
                                    valid_way1[maint_vaddr[11:5]] <= |maint_taglo[7:6];
                                end
                                2'd2: begin
                                    tag_way2[maint_vaddr[11:5]] <= maint_taglo[31:12];
                                    valid_way2[maint_vaddr[11:5]] <= |maint_taglo[7:6];
                                end
                                default: begin
                                    tag_way3[maint_vaddr[11:5]] <= maint_taglo[31:12];
                                    valid_way3[maint_vaddr[11:5]] <= |maint_taglo[7:6];
                                end
                            endcase
                        end
                        5'h10: begin
                            if (valid_way0[maint_paddr[11:5]] && tag_way0[maint_paddr[11:5]] == maint_paddr[31:12])
                                valid_way0[maint_paddr[11:5]] <= 1'b0;
                            if (valid_way1[maint_paddr[11:5]] && tag_way1[maint_paddr[11:5]] == maint_paddr[31:12])
                                valid_way1[maint_paddr[11:5]] <= 1'b0;
                            if (valid_way2[maint_paddr[11:5]] && tag_way2[maint_paddr[11:5]] == maint_paddr[31:12])
                                valid_way2[maint_paddr[11:5]] <= 1'b0;
                            if (valid_way3[maint_paddr[11:5]] && tag_way3[maint_paddr[11:5]] == maint_paddr[31:12])
                                valid_way3[maint_paddr[11:5]] <= 1'b0;
                        end
                        default: cache_fault <= 1'b1;
                    endcase
                    maint_done <= 1'b1;
                end else if (cpu_req && cpu_addr_ok) begin
                    req_addr <= cpu_addr;
                    if (cpu_cacheable) begin
                        state <= ST_LOOKUP;
                    end else begin
                        stat_uncache_read <= stat_uncache_read + 32'd1;
                        state <= ST_UNC_REQ;
                    end
                end
            end

            ST_LOOKUP: begin
                if (hit_count > 3'd1) begin
                    cache_fault <= 1'b1;
                    state <= ST_FAULT;
                end else if (hit_vector != 4'b0) begin
                    rdata <= hit_word;
                    stat_hit <= stat_hit + 32'd1;
                    state <= ST_COMPLETE;
                end else begin
                    stat_miss <= stat_miss + 32'd1;
                    victim_way <= choose_way;
                    refill_addr_reg <= {req_addr[31:5], 5'b0};
                    state <= ST_REFILL_REQ;
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
                if (refill_data_valid) begin
                    case (refill_beat)
                        3'd0: refill_buffer[31:0] <= refill_data;
                        3'd1: refill_buffer[63:32] <= refill_data;
                        3'd2: refill_buffer[95:64] <= refill_data;
                        3'd3: refill_buffer[127:96] <= refill_data;
                        3'd4: refill_buffer[159:128] <= refill_data;
                        3'd5: refill_buffer[191:160] <= refill_data;
                        3'd6: refill_buffer[223:192] <= refill_data;
                        default: refill_buffer[255:224] <= refill_data;
                    endcase

                    if (refill_data_last !== (refill_beat == 3'd7)) begin
                        cache_fault <= 1'b1;
                        state <= ST_FAULT;
                    end else if (refill_beat == 3'd7) begin
                        rdata <= refill_word;
                        case (victim_way)
                            2'd0: begin
                                tag_way0[req_addr[11:5]] <= req_addr[31:12];
                                line_way0[req_addr[11:5]] <= refill_line_now;
                                valid_way0[req_addr[11:5]] <= 1'b1;
                            end
                            2'd1: begin
                                tag_way1[req_addr[11:5]] <= req_addr[31:12];
                                line_way1[req_addr[11:5]] <= refill_line_now;
                                valid_way1[req_addr[11:5]] <= 1'b1;
                            end
                            2'd2: begin
                                tag_way2[req_addr[11:5]] <= req_addr[31:12];
                                line_way2[req_addr[11:5]] <= refill_line_now;
                                valid_way2[req_addr[11:5]] <= 1'b1;
                            end
                            default: begin
                                tag_way3[req_addr[11:5]] <= req_addr[31:12];
                                line_way3[req_addr[11:5]] <= refill_line_now;
                                valid_way3[req_addr[11:5]] <= 1'b1;
                            end
                        endcase
                        replace_way[req_addr[11:5]] <= victim_way + 2'd1;
                        stat_refill <= stat_refill + 32'd1;
                        state <= ST_COMPLETE;
                    end else begin
                        refill_beat <= refill_beat + 3'd1;
                    end
                end
            end

            ST_UNC_REQ: begin
                if (uncache_req && uncache_addr_ok) begin
                    if (uncache_data_ok) begin
                        rdata <= uncache_data;
                        state <= ST_COMPLETE;
                    end else begin
                        state <= ST_UNC_WAIT;
                    end
                end
            end

            ST_UNC_WAIT: begin
                if (uncache_data_ok) begin
                    rdata <= uncache_data;
                    state <= ST_COMPLETE;
                end
            end

            ST_COMPLETE: begin
                state <= ST_IDLE;
            end

            default: begin
                cache_fault <= 1'b1;
                state <= ST_FAULT;
            end
        endcase
    end
end

endmodule
