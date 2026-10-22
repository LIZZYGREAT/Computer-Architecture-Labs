`include "mycpu.h"

module exe_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          ms_allowin    ,
    output                         es_allowin    ,
    //from ds
    input                          ds_to_es_valid,
    input  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus  ,
    //to ms
    output                         es_to_ms_valid,
    output [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus  ,
    output [38:0]                  es_producer_bus,
    // data sram interface
    output        data_sram_en   ,
    output [ 3:0] data_sram_wen  ,
    output [31:0] data_sram_addr ,
    output [31:0] data_sram_wdata
);

reg         es_valid      ;
wire        es_ready_go   ;

reg  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus_r;
wire [`HILO_OP_WD-1:0] es_hilo_op;
wire [11:0] es_alu_op     ;
wire [`MEM_OP_WD-1:0] es_mem_op;
wire        es_src1_is_sa ;  
wire        es_src1_is_pc ;
wire        es_src2_is_imm; 
wire        es_src2_is_8  ;
wire        es_gr_we      ;
wire [ 4:0] es_dest       ;
wire [15:0] es_imm        ;
wire [31:0] es_rs_value   ;
wire [31:0] es_rt_value   ;
wire [31:0] es_pc         ;
assign {es_hilo_op     ,  //153:146
        es_alu_op      ,  //145:134
        es_mem_op      ,  //133:122
        es_src1_is_sa  ,  //121:121
        es_src1_is_pc  ,  //120:120
        es_src2_is_imm ,  //119:119
        es_src2_is_8   ,  //118:118
        es_gr_we       ,  //117:117
        es_dest        ,  //116:112
        es_imm         ,  //111:96
        es_rs_value    ,  //95 :64
        es_rt_value    ,  //63 :32
        es_pc             //31 :0
       } = ds_to_es_bus_r;

wire [31:0] es_alu_src1   ;
wire [31:0] es_alu_src2   ;
wire [31:0] es_alu_result ;
wire [31:0] es_result     ;
wire        es_imm_zero_extend;
wire        es_hilo_multdiv;
wire        es_hilo_start;
wire        es_hilo_busy;
wire        es_hilo_done;
wire        es_hilo_write_hi;
wire        es_hilo_write_lo;
wire        es_hilo_consume;
wire [31:0] hilo_hi_value;
wire [31:0] hilo_lo_value;

wire        es_res_from_mem;
wire        es_mem_store;
wire [3:0]  es_store_wen;
wire [31:0] es_store_data;

assign es_res_from_mem = |es_mem_op[6:0];
assign es_mem_store = |es_mem_op[11:7];
assign es_producer_bus = {es_valid && es_gr_we && (es_dest != 5'd0),
                          es_valid && es_gr_we && !es_res_from_mem && (es_dest != 5'd0),
                          es_dest,
                          es_result};
assign es_to_ms_bus = {es_mem_op      ,  //113:102
                       es_gr_we       ,  //101:101
                       es_dest        ,  //100:96
                       es_result      ,  //95:64
                       es_rt_value    ,  //63:32 old rt for LWL/LWR merge
                       es_pc             //31:0
                      };

assign es_hilo_multdiv = es_hilo_op[`HILO_OP_MULT]  |
                         es_hilo_op[`HILO_OP_MULTU] |
                         es_hilo_op[`HILO_OP_DIV]   |
                         es_hilo_op[`HILO_OP_DIVU];
assign es_hilo_start   = es_valid && es_hilo_multdiv && !es_hilo_busy && !es_hilo_done;
assign es_hilo_write_hi = es_valid && es_ready_go && ms_allowin && es_hilo_op[`HILO_OP_MTHI];
assign es_hilo_write_lo = es_valid && es_ready_go && ms_allowin && es_hilo_op[`HILO_OP_MTLO];
assign es_hilo_consume   = es_valid && es_hilo_done && ms_allowin;
assign es_ready_go     = !es_hilo_multdiv || es_hilo_done;
assign es_allowin     = !es_valid || es_ready_go && ms_allowin;
assign es_to_ms_valid =  es_valid && es_ready_go;
always @(posedge clk) begin
    if (reset) begin
        es_valid <= 1'b0;
    end
    else if (es_allowin) begin
        es_valid <= ds_to_es_valid;
    end

    if (ds_to_es_valid && es_allowin) begin
        ds_to_es_bus_r <= ds_to_es_bus;
    end
end

assign es_alu_src1 = es_src1_is_sa  ? {27'b0, es_imm[10:6]} : 
                     es_src1_is_pc  ? es_pc[31:0] :
                                      es_rs_value;
// ANDI/ORI/XORI share their ALU operation with the register forms. With an
// immediate selected, those three operations require a zero-extended operand.
assign es_imm_zero_extend = es_src2_is_imm &&
                            (es_alu_op[4] || es_alu_op[6] || es_alu_op[7]);
assign es_alu_src2 = es_src2_is_imm ? (es_imm_zero_extend ? {16'b0, es_imm} :
                                                            {{16{es_imm[15]}}, es_imm}) :
                     es_src2_is_8   ? 32'd8 :
                                      es_rt_value;

assign es_result = es_hilo_op[`HILO_OP_MFHI] ? hilo_hi_value :
                   es_hilo_op[`HILO_OP_MFLO] ? hilo_lo_value :
                                                es_alu_result;

hilo_unit u_hilo_unit(
    .clk              (clk),
    .resetn           (~reset),
    .start            (es_hilo_start),
    .is_mult          (es_hilo_op[`HILO_OP_MULT]),
    .is_multu         (es_hilo_op[`HILO_OP_MULTU]),
    .is_div           (es_hilo_op[`HILO_OP_DIV]),
    .is_divu          (es_hilo_op[`HILO_OP_DIVU]),
    .consume_done     (es_hilo_consume),
    .operand_a        (es_rs_value),
    .operand_b        (es_rt_value),
    .write_hi_en      (es_hilo_write_hi),
    .write_lo_en      (es_hilo_write_lo),
    .write_data       (es_rs_value),
    .busy             (es_hilo_busy),
    .done             (es_hilo_done),
    .hi_value         (hilo_hi_value),
    .lo_value         (hilo_lo_value)
);

alu u_alu(
    .alu_op     (es_alu_op    ),
    .alu_src1   (es_alu_src1  ),
    .alu_src2   (es_alu_src2  ),
    .alu_result (es_alu_result)
    );

assign data_sram_en    = es_valid && es_ready_go && ms_allowin &&
                         (es_res_from_mem || es_mem_store);
assign data_sram_wen   = data_sram_en && es_mem_store ? es_store_wen : 4'h0;
assign data_sram_addr  = es_alu_result;
assign data_sram_wdata = es_store_data;

reg [3:0] es_store_wen_r;
reg [31:0] es_store_data_r;
assign es_store_wen = es_store_wen_r;
assign es_store_data = es_store_data_r;
always @(*) begin
    es_store_wen_r = 4'b0000;
    es_store_data_r = es_rt_value;
    if (es_mem_op[`MEM_OP_SW]) begin
        es_store_wen_r = 4'b1111;
    end
    else if (es_mem_op[`MEM_OP_SB]) begin
        es_store_wen_r = 4'b0001 << es_alu_result[1:0];
        es_store_data_r = es_rt_value << {es_alu_result[1:0], 3'b000};
    end
    else if (es_mem_op[`MEM_OP_SH]) begin
        if (es_alu_result[1]) begin
            es_store_wen_r = 4'b1100;
            es_store_data_r = es_rt_value << 16;
        end
        else begin
            es_store_wen_r = 4'b0011;
        end
    end
    else if (es_mem_op[`MEM_OP_SWL]) begin
        case (es_alu_result[1:0])
            2'd0: begin es_store_wen_r = 4'b0001; es_store_data_r = es_rt_value >> 24; end
            2'd1: begin es_store_wen_r = 4'b0011; es_store_data_r = es_rt_value >> 16; end
            2'd2: begin es_store_wen_r = 4'b0111; es_store_data_r = es_rt_value >> 8;  end
            2'd3: begin es_store_wen_r = 4'b1111; end
        endcase
    end
    else if (es_mem_op[`MEM_OP_SWR]) begin
        case (es_alu_result[1:0])
            2'd0: begin es_store_wen_r = 4'b1111; end
            2'd1: begin es_store_wen_r = 4'b1110; es_store_data_r = es_rt_value << 8;  end
            2'd2: begin es_store_wen_r = 4'b1100; es_store_data_r = es_rt_value << 16; end
            2'd3: begin es_store_wen_r = 4'b1000; es_store_data_r = es_rt_value << 24; end
        endcase
    end
end

endmodule
