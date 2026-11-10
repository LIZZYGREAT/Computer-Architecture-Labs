`include "mycpu.h"

module mem_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          ws_allowin    ,
    output                         ms_allowin    ,
    //from es
    input                          es_to_ms_valid,
    input  [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus  ,
    // CP0 access and precise exception/return interface
    input  [31:0]                  cp0_rdata,
    output                         cp0_we,
    output [ 7:0]                  cp0_waddr,
    output [31:0]                  cp0_wdata,
    output [ 7:0]                  cp0_raddr,
    output                         cp0_serial_busy,
    output                         trap_commit,
    output [ 4:0]                  trap_code,
    output [31:0]                  trap_pc,
    output                         trap_bd,
    output [31:0]                  trap_bad_vaddr,
    output                         eret_commit,
    //to ws
    output                         ms_to_ws_valid,
    output [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus  ,
    output [38:0]                  ms_producer_bus,
    //from data-sram
    input  [31                 :0] data_sram_rdata
);

reg         ms_valid;
wire        ms_ready_go;

reg [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus_r;
wire [1:0]  ms_cp0_op;
wire [7:0]  ms_cp0_addr;
wire [31:0] ms_cp0_write_data;
wire        ms_exception_valid;
wire [4:0]  ms_exception_code;
wire [31:0] ms_bad_vaddr;
wire        ms_is_delay_slot;
wire [`MEM_OP_WD-1:0] ms_mem_op;
wire        ms_res_from_mem;
wire        ms_gr_we;
wire [ 4:0] ms_dest;
wire [31:0] ms_alu_result;
wire [31:0] ms_rt_value;
wire [31:0] ms_pc;
assign {ms_cp0_op,
        ms_cp0_addr,
        ms_cp0_write_data,
        ms_exception_valid,
        ms_exception_code,
        ms_bad_vaddr,
        ms_is_delay_slot,
        ms_mem_op      ,  //113:102 legacy fields
        ms_gr_we       ,  //101:101
        ms_dest        ,  //100:96
        ms_alu_result  ,  //95:64 effective address / ALU result
        ms_rt_value    ,  //63:32 old rt for LWL/LWR merge
        ms_pc             //31:0
       } = es_to_ms_bus_r;

assign ms_res_from_mem = |ms_mem_op[6:0];

reg [31:0] mem_result;
wire [31:0] ms_final_result;

assign ms_to_ws_bus = {ms_gr_we       ,  //69:69
                       ms_dest        ,  //68:64
                       ms_final_result,  //63:32
                       ms_pc             //31:0
                      };
assign ms_producer_bus = {ms_valid && !ms_exception_valid &&
                              (ms_cp0_op != `CP0_OP_ERET) &&
                              ms_gr_we && (ms_dest != 5'd0),
                          ms_valid && !ms_exception_valid &&
                              (ms_cp0_op != `CP0_OP_ERET) &&
                              ms_gr_we && (ms_dest != 5'd0),
                          ms_dest,
                          ms_final_result};

assign ms_ready_go    = 1'b1;
assign ms_allowin     = !ms_valid || ms_ready_go && ws_allowin;
assign ms_to_ws_valid = ms_valid && ms_ready_go &&
                        !ms_exception_valid && (ms_cp0_op != `CP0_OP_ERET);
assign trap_commit = ms_valid && ms_ready_go && ws_allowin && ms_exception_valid;
assign eret_commit = ms_valid && ms_ready_go && ws_allowin &&
                     !ms_exception_valid && (ms_cp0_op == `CP0_OP_ERET);
assign cp0_we = ms_valid && ms_ready_go && ws_allowin &&
                !ms_exception_valid && (ms_cp0_op == `CP0_OP_MTC0);
assign cp0_waddr = cp0_we ? ms_cp0_addr : 8'b0;
assign cp0_wdata = cp0_we ? ms_cp0_write_data : 32'b0;
assign cp0_raddr = (ms_valid && (ms_cp0_op == `CP0_OP_MFC0)) ? ms_cp0_addr : 8'b0;
assign cp0_serial_busy = ms_valid &&
                         ((ms_cp0_op == `CP0_OP_MTC0) ||
                          (ms_cp0_op == `CP0_OP_ERET));
assign trap_code = ms_exception_code;
assign trap_pc = ms_pc;
assign trap_bd = ms_is_delay_slot;
assign trap_bad_vaddr = ms_bad_vaddr;
always @(posedge clk) begin
    if (reset) begin
        ms_valid <= 1'b0;
    end
    else if (trap_commit || eret_commit) begin
        ms_valid <= 1'b0;
    end
    else if (ms_allowin) begin
        ms_valid <= es_to_ms_valid;
    end

    if (!reset && !trap_commit && !eret_commit && es_to_ms_valid && ms_allowin) begin
        es_to_ms_bus_r  <= es_to_ms_bus;
    end
end

always @(*) begin
    mem_result = data_sram_rdata;
    if (ms_mem_op[`MEM_OP_LB]) begin
        case (ms_alu_result[1:0])
            2'd0: mem_result = {{24{data_sram_rdata[7]}},  data_sram_rdata[7:0]};
            2'd1: mem_result = {{24{data_sram_rdata[15]}}, data_sram_rdata[15:8]};
            2'd2: mem_result = {{24{data_sram_rdata[23]}}, data_sram_rdata[23:16]};
            2'd3: mem_result = {{24{data_sram_rdata[31]}}, data_sram_rdata[31:24]};
        endcase
    end
    else if (ms_mem_op[`MEM_OP_LBU]) begin
        case (ms_alu_result[1:0])
            2'd0: mem_result = {24'b0, data_sram_rdata[7:0]};
            2'd1: mem_result = {24'b0, data_sram_rdata[15:8]};
            2'd2: mem_result = {24'b0, data_sram_rdata[23:16]};
            2'd3: mem_result = {24'b0, data_sram_rdata[31:24]};
        endcase
    end
    else if (ms_mem_op[`MEM_OP_LH]) begin
        if (ms_alu_result[1])
            mem_result = {{16{data_sram_rdata[31]}}, data_sram_rdata[31:16]};
        else
            mem_result = {{16{data_sram_rdata[15]}}, data_sram_rdata[15:0]};
    end
    else if (ms_mem_op[`MEM_OP_LHU]) begin
        mem_result = ms_alu_result[1] ? {16'b0, data_sram_rdata[31:16]} :
                                        {16'b0, data_sram_rdata[15:0]};
    end
    else if (ms_mem_op[`MEM_OP_LWL]) begin
        case (ms_alu_result[1:0])
            2'd0: mem_result = {data_sram_rdata[7:0],  ms_rt_value[23:0]};
            2'd1: mem_result = {data_sram_rdata[15:0], ms_rt_value[15:0]};
            2'd2: mem_result = {data_sram_rdata[23:0], ms_rt_value[7:0]};
            2'd3: mem_result = data_sram_rdata;
        endcase
    end
    else if (ms_mem_op[`MEM_OP_LWR]) begin
        case (ms_alu_result[1:0])
            2'd0: mem_result = data_sram_rdata;
            2'd1: mem_result = {ms_rt_value[31:24], data_sram_rdata[31:8]};
            2'd2: mem_result = {ms_rt_value[31:16], data_sram_rdata[31:16]};
            2'd3: mem_result = {ms_rt_value[31:8],  data_sram_rdata[31:24]};
        endcase
    end
end

assign ms_final_result = (ms_cp0_op == `CP0_OP_MFC0) ? cp0_rdata :
                         ms_res_from_mem ? mem_result : ms_alu_result;

endmodule
