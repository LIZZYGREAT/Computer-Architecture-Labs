`include "mycpu.h"

module id_stage #(parameter PIPELINE_FORWARDING = 1'b1)(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          es_allowin    ,
    output                         ds_allowin    ,
    //from fs
    input                          fs_to_ds_valid,
    input  [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus  ,
    //to es
    output                         ds_to_es_valid,
    output [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus  ,
    //to fs
    output [`BR_BUS_WD       -1:0] br_bus        ,
    //to rf: for write back
    input  [`WS_TO_RF_BUS_WD -1:0] ws_to_rf_bus,
    //in-flight producer information for RAW handling and forwarding
    input  [38:0]                  es_producer_bus,
    input  [38:0]                  ms_producer_bus
);

reg         ds_valid   ;
wire        ds_ready_go;
wire        ds_stall;

wire [31                 :0] fs_pc;
reg  [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus_r;
assign fs_pc = fs_to_ds_bus[31:0];

wire [31:0] ds_inst;
wire [31:0] ds_pc  ;
assign {ds_inst,
        ds_pc  } = fs_to_ds_bus_r;

wire        rf_we   ;
wire [ 4:0] rf_waddr;
wire [31:0] rf_wdata;
assign {rf_we   ,  //37:37
        rf_waddr,  //36:32
        rf_wdata   //31:0
       } = ws_to_rf_bus;

wire        br_taken;
wire [31:0] br_target;

wire [11:0] alu_op;
wire [`MEM_OP_WD-1:0] mem_op;
wire        src1_is_sa;
wire        src1_is_pc;
wire        src2_is_imm;
wire        src2_is_8;
wire        gr_we;
wire [ 4:0] dest;
wire [15:0] imm;
wire [31:0] rs_value;
wire [31:0] rt_value;
wire [31:0] rf_rs_value;
wire [31:0] rf_rt_value;
wire [31:0] es_forward_value;
wire [31:0] ms_forward_value;
wire [31:0] ws_forward_value;
wire        es_hazard_valid;
wire        es_forward_valid;
wire [ 4:0] es_producer_dest;
wire        ms_hazard_valid;
wire        ms_forward_valid;
wire [ 4:0] ms_producer_dest;
wire        ws_forward_valid;
wire [ 4:0] ws_producer_dest;
wire        ds_rs_used;
wire        ds_rt_used;
wire        ds_rs_hazard;
wire        ds_rt_hazard;
wire        ds_rs_stall;
wire        ds_rt_stall;
wire        ds_forward_rs_ex;
wire        ds_forward_rt_ex;
wire        ds_forward_rs_ms;
wire        ds_forward_rt_ms;
wire        ds_forward_rs_ws;
wire        ds_forward_rt_ws;
wire [31:0] ds_pc_plus_4;

wire [ 5:0] op;
wire [ 4:0] rs;
wire [ 4:0] rt;
wire [ 4:0] rd;
wire [ 4:0] sa;
wire [ 5:0] func;
wire [25:0] jidx;
wire [63:0] op_d;
wire [31:0] rs_d;
wire [31:0] rt_d;
wire [31:0] rd_d;
wire [31:0] sa_d;
wire [63:0] func_d;

wire        inst_addu;
wire        inst_subu;
wire        inst_add;
wire        inst_sub;
wire        inst_slt;
wire        inst_sltu;
wire        inst_and;
wire        inst_or;
wire        inst_xor;
wire        inst_nor;
wire        inst_sll;
wire        inst_srl;
wire        inst_sra;
wire        inst_sllv;
wire        inst_srlv;
wire        inst_srav;
wire        inst_addiu;
wire        inst_addi;
wire        inst_slti;
wire        inst_sltiu;
wire        inst_andi;
wire        inst_ori;
wire        inst_xori;
wire        inst_mult;
wire        inst_multu;
wire        inst_div;
wire        inst_divu;
wire        inst_mfhi;
wire        inst_mflo;
wire        inst_mthi;
wire        inst_mtlo;
wire        inst_lui;
wire        inst_lw;
wire        inst_lb;
wire        inst_lbu;
wire        inst_lh;
wire        inst_lhu;
wire        inst_lwl;
wire        inst_lwr;
wire        inst_sw;
wire        inst_sb;
wire        inst_sh;
wire        inst_swl;
wire        inst_swr;
wire        inst_load;
wire        inst_store;
wire        inst_beq;
wire        inst_bne;
wire        inst_j;
wire        inst_jal;
wire        inst_jr;
wire        inst_jalr;
wire        inst_bgez;
wire        inst_bgtz;
wire        inst_blez;
wire        inst_bltz;
wire        inst_bgezal;
wire        inst_bltzal;
wire        inst_link;
wire        inst_gpr_write;
wire [`HILO_OP_WD-1:0] hilo_op;

wire        dst_is_r31;  
wire        dst_is_rt;   

wire [ 4:0] rf_raddr1;
wire [31:0] rf_rdata1;
wire [ 4:0] rf_raddr2;
wire [31:0] rf_rdata2;

wire        rs_eq_rt;
wire        ds_branch_cond_taken;

assign br_bus       = {br_taken,br_target};

assign ds_to_es_bus = {hilo_op      ,  //153:146
                       alu_op       ,  //145:134
                       mem_op       ,  //133:122
                       src1_is_sa   ,  //121:121
                       src1_is_pc   ,  //120:120
                       src2_is_imm  ,  //119:119
                       src2_is_8    ,  //118:118
                       gr_we        ,  //117:117
                       dest         ,  //116:112
                       imm          ,  //111:96
                       rs_value     ,  //95 :64
                       rt_value     ,  //63 :32
                       ds_pc           //31 :0
                      };

assign {es_hazard_valid, es_forward_valid, es_producer_dest, es_forward_value} = es_producer_bus;
assign {ms_hazard_valid, ms_forward_valid, ms_producer_dest, ms_forward_value} = ms_producer_bus;
assign {ws_forward_valid, ws_producer_dest, ws_forward_value} = ws_to_rf_bus;

assign ds_rs_used = inst_addu | inst_subu | inst_add | inst_sub |
                    inst_slt | inst_sltu | inst_slti | inst_sltiu |
                    inst_and | inst_or | inst_xor | inst_nor |
                    inst_addiu | inst_addi | inst_andi | inst_ori | inst_xori |
                    inst_sllv | inst_srlv | inst_srav |
                    inst_mult | inst_multu | inst_div | inst_divu | inst_mthi | inst_mtlo |
                    inst_load | inst_store | inst_beq | inst_bne | inst_jr | inst_jalr |
                    inst_bgez | inst_bgtz | inst_blez | inst_bltz | inst_bgezal | inst_bltzal;
assign ds_rt_used = inst_addu | inst_subu | inst_add | inst_sub |
                    inst_slt | inst_sltu |
                    inst_and | inst_or | inst_xor | inst_nor |
                    inst_sll | inst_srl | inst_sra | inst_sllv | inst_srlv | inst_srav |
                    inst_mult | inst_multu | inst_div | inst_divu |
                    inst_store | inst_lwl | inst_lwr | inst_beq | inst_bne;

assign ds_rs_hazard = ds_valid && ds_rs_used && (rs != 5'd0) &&
                      ((es_hazard_valid && (es_producer_dest == rs)) ||
                       (ms_hazard_valid && (ms_producer_dest == rs)) ||
                       (ws_forward_valid && (ws_producer_dest == rs)));
assign ds_rt_hazard = ds_valid && ds_rt_used && (rt != 5'd0) &&
                      ((es_hazard_valid && (es_producer_dest == rt)) ||
                       (ms_hazard_valid && (ms_producer_dest == rt)) ||
                       (ws_forward_valid && (ws_producer_dest == rt)));

assign ds_rs_stall = ds_rs_hazard &&
                     ((!PIPELINE_FORWARDING) ||
                      (es_hazard_valid && (es_producer_dest == rs) && !es_forward_valid) ||
                      (!(es_hazard_valid && (es_producer_dest == rs)) &&
                       ms_hazard_valid && (ms_producer_dest == rs) && !ms_forward_valid));
assign ds_rt_stall = ds_rt_hazard &&
                     ((!PIPELINE_FORWARDING) ||
                      (es_hazard_valid && (es_producer_dest == rt) && !es_forward_valid) ||
                      (!(es_hazard_valid && (es_producer_dest == rt)) &&
                       ms_hazard_valid && (ms_producer_dest == rt) && !ms_forward_valid));
assign ds_stall = ds_rs_stall || ds_rt_stall;
assign ds_forward_rs_ex = PIPELINE_FORWARDING && ds_valid && ds_rs_used &&
                          es_forward_valid && (es_producer_dest == rs);
assign ds_forward_rt_ex = PIPELINE_FORWARDING && ds_valid && ds_rt_used &&
                          es_forward_valid && (es_producer_dest == rt);
assign ds_forward_rs_ms = PIPELINE_FORWARDING && ds_valid && ds_rs_used &&
                          !(es_hazard_valid && (es_producer_dest == rs)) &&
                          ms_forward_valid && (ms_producer_dest == rs);
assign ds_forward_rt_ms = PIPELINE_FORWARDING && ds_valid && ds_rt_used &&
                          !(es_hazard_valid && (es_producer_dest == rt)) &&
                          ms_forward_valid && (ms_producer_dest == rt);
assign ds_forward_rs_ws = PIPELINE_FORWARDING && ds_valid && ds_rs_used &&
                          !(es_hazard_valid && (es_producer_dest == rs)) &&
                          !(ms_hazard_valid && (ms_producer_dest == rs)) &&
                          ws_forward_valid && (ws_producer_dest == rs);
assign ds_forward_rt_ws = PIPELINE_FORWARDING && ds_valid && ds_rt_used &&
                          !(es_hazard_valid && (es_producer_dest == rt)) &&
                          !(ms_hazard_valid && (ms_producer_dest == rt)) &&
                          ws_forward_valid && (ws_producer_dest == rt);
assign ds_ready_go    = !ds_stall;
assign ds_allowin     = !ds_valid || ds_ready_go && es_allowin;
assign ds_to_es_valid = ds_valid && ds_ready_go;
always @(posedge clk) begin
    if (reset) begin
        ds_valid <= 1'b0;
    end
    else if (ds_allowin) begin
        ds_valid <= fs_to_ds_valid;
    end

    if (!reset && fs_to_ds_valid && ds_allowin) begin
        fs_to_ds_bus_r <= fs_to_ds_bus;
    end
end

assign op   = ds_inst[31:26];
assign rs   = ds_inst[25:21];
assign rt   = ds_inst[20:16];
assign rd   = ds_inst[15:11];
assign sa   = ds_inst[10: 6];
assign func = ds_inst[ 5: 0];
assign imm  = ds_inst[15: 0];
assign jidx = ds_inst[25: 0];

decoder_6_64 u_dec0(.in(op  ), .out(op_d  ));
decoder_6_64 u_dec1(.in(func), .out(func_d));
decoder_5_32 u_dec2(.in(rs  ), .out(rs_d  ));
decoder_5_32 u_dec3(.in(rt  ), .out(rt_d  ));
decoder_5_32 u_dec4(.in(rd  ), .out(rd_d  ));
decoder_5_32 u_dec5(.in(sa  ), .out(sa_d  ));

assign inst_addu   = op_d[6'h00] & func_d[6'h21] & sa_d[5'h00];
assign inst_subu   = op_d[6'h00] & func_d[6'h23] & sa_d[5'h00];
assign inst_add    = op_d[6'h00] & func_d[6'h20] & sa_d[5'h00];
assign inst_sub    = op_d[6'h00] & func_d[6'h22] & sa_d[5'h00];
assign inst_slt    = op_d[6'h00] & func_d[6'h2a] & sa_d[5'h00];
assign inst_sltu   = op_d[6'h00] & func_d[6'h2b] & sa_d[5'h00];
assign inst_and    = op_d[6'h00] & func_d[6'h24] & sa_d[5'h00];
assign inst_or     = op_d[6'h00] & func_d[6'h25] & sa_d[5'h00];
assign inst_xor    = op_d[6'h00] & func_d[6'h26] & sa_d[5'h00];
assign inst_nor    = op_d[6'h00] & func_d[6'h27] & sa_d[5'h00];
assign inst_sll    = op_d[6'h00] & func_d[6'h00] & rs_d[5'h00];
assign inst_srl    = op_d[6'h00] & func_d[6'h02] & rs_d[5'h00];
assign inst_sra    = op_d[6'h00] & func_d[6'h03] & rs_d[5'h00];
assign inst_sllv   = op_d[6'h00] & func_d[6'h04] & sa_d[5'h00];
assign inst_srlv   = op_d[6'h00] & func_d[6'h06] & sa_d[5'h00];
assign inst_srav   = op_d[6'h00] & func_d[6'h07] & sa_d[5'h00];
assign inst_addiu  = op_d[6'h09];
assign inst_addi   = op_d[6'h08];
assign inst_slti   = op_d[6'h0a];
assign inst_sltiu  = op_d[6'h0b];
assign inst_andi   = op_d[6'h0c];
assign inst_ori    = op_d[6'h0d];
assign inst_xori   = op_d[6'h0e];
assign inst_mult   = op_d[6'h00] & func_d[6'h18] & rd_d[5'h00] & sa_d[5'h00];
assign inst_multu  = op_d[6'h00] & func_d[6'h19] & rd_d[5'h00] & sa_d[5'h00];
assign inst_div    = op_d[6'h00] & func_d[6'h1a] & rd_d[5'h00] & sa_d[5'h00];
assign inst_divu   = op_d[6'h00] & func_d[6'h1b] & rd_d[5'h00] & sa_d[5'h00];
assign inst_mfhi   = op_d[6'h00] & func_d[6'h10] & rs_d[5'h00] & rt_d[5'h00] & sa_d[5'h00];
assign inst_mflo   = op_d[6'h00] & func_d[6'h12] & rs_d[5'h00] & rt_d[5'h00] & sa_d[5'h00];
assign inst_mthi   = op_d[6'h00] & func_d[6'h11] & rt_d[5'h00] & rd_d[5'h00] & sa_d[5'h00];
assign inst_mtlo   = op_d[6'h00] & func_d[6'h13] & rt_d[5'h00] & rd_d[5'h00] & sa_d[5'h00];
assign inst_lui    = op_d[6'h0f] & rs_d[5'h00];
assign inst_lw     = op_d[6'h23];
assign inst_lb     = op_d[6'h20];
assign inst_lbu    = op_d[6'h24];
assign inst_lh     = op_d[6'h21];
assign inst_lhu    = op_d[6'h25];
assign inst_lwl    = op_d[6'h22];
assign inst_lwr    = op_d[6'h26];
assign inst_sw     = op_d[6'h2b];
assign inst_sb     = op_d[6'h28];
assign inst_sh     = op_d[6'h29];
assign inst_swl    = op_d[6'h2a];
assign inst_swr    = op_d[6'h2e];
assign inst_load   = inst_lw | inst_lb | inst_lbu | inst_lh | inst_lhu | inst_lwl | inst_lwr;
assign inst_store  = inst_sw | inst_sb | inst_sh | inst_swl | inst_swr;
assign inst_beq    = op_d[6'h04];
assign inst_bne    = op_d[6'h05];
assign inst_j      = op_d[6'h02];
assign inst_jal    = op_d[6'h03];
assign inst_jr     = op_d[6'h00] & func_d[6'h08] & rt_d[5'h00] & rd_d[5'h00] & sa_d[5'h00];
assign inst_jalr   = op_d[6'h00] & func_d[6'h09] & rt_d[5'h00] & sa_d[5'h00];
assign inst_bltz   = op_d[6'h01] & rt_d[5'h00];
assign inst_bgez   = op_d[6'h01] & rt_d[5'h01];
assign inst_bltzal = op_d[6'h01] & rt_d[5'h10];
assign inst_bgezal = op_d[6'h01] & rt_d[5'h11];
assign inst_bgtz   = op_d[6'h07] & rt_d[5'h00];
assign inst_blez   = op_d[6'h06] & rt_d[5'h00];

// The course's MIPS branch-and-link tests expect the PC+8 link on both
// taken and not-taken cases; only the PC redirect depends on the condition.
assign inst_link = inst_jal | inst_jalr | inst_bltzal | inst_bgezal;

assign hilo_op = {inst_mtlo, inst_mthi, inst_mflo, inst_mfhi,
                  inst_divu, inst_div, inst_multu, inst_mult};

assign alu_op[ 0] = inst_addu | inst_add | inst_addiu | inst_addi |
                    inst_load | inst_store | inst_link;
assign alu_op[ 1] = inst_subu | inst_sub;
assign alu_op[ 2] = inst_slt | inst_slti;
assign alu_op[ 3] = inst_sltu | inst_sltiu;
assign alu_op[ 4] = inst_and | inst_andi;
assign alu_op[ 5] = inst_nor;
assign alu_op[ 6] = inst_or | inst_ori;
assign alu_op[ 7] = inst_xor | inst_xori;
assign alu_op[ 8] = inst_sll | inst_sllv;
assign alu_op[ 9] = inst_srl | inst_srlv;
assign alu_op[10] = inst_sra | inst_srav;
assign alu_op[11] = inst_lui;

assign src1_is_sa   = inst_sll   | inst_srl | inst_sra;
assign src1_is_pc   = inst_link;
assign src2_is_imm  = inst_addiu | inst_addi | inst_slti | inst_sltiu |
                      inst_andi | inst_ori | inst_xori |
                      inst_lui | inst_load | inst_store;
assign src2_is_8    = inst_link;
assign mem_op[`MEM_OP_LW]  = inst_lw;
assign mem_op[`MEM_OP_LB]  = inst_lb;
assign mem_op[`MEM_OP_LBU] = inst_lbu;
assign mem_op[`MEM_OP_LH]  = inst_lh;
assign mem_op[`MEM_OP_LHU] = inst_lhu;
assign mem_op[`MEM_OP_LWL] = inst_lwl;
assign mem_op[`MEM_OP_LWR] = inst_lwr;
assign mem_op[`MEM_OP_SW]  = inst_sw;
assign mem_op[`MEM_OP_SB]  = inst_sb;
assign mem_op[`MEM_OP_SH]  = inst_sh;
assign mem_op[`MEM_OP_SWL] = inst_swl;
assign mem_op[`MEM_OP_SWR] = inst_swr;
assign dst_is_r31   = inst_jal | inst_bltzal | inst_bgezal;
assign dst_is_rt    = inst_addiu | inst_addi | inst_slti | inst_sltiu |
                      inst_andi | inst_ori | inst_xori | inst_lui | inst_load;
assign inst_gpr_write = inst_addu | inst_subu | inst_add | inst_sub |
                        inst_slt | inst_sltu | inst_and | inst_or | inst_xor | inst_nor |
                        inst_sll | inst_srl | inst_sra | inst_sllv | inst_srlv | inst_srav |
                        inst_addiu | inst_addi | inst_slti | inst_sltiu |
                        inst_andi | inst_ori | inst_xori | inst_lui | inst_load | inst_jal |
                        inst_mfhi | inst_mflo | inst_jalr | inst_bltzal | inst_bgezal;
assign gr_we        = inst_gpr_write;

assign dest         = dst_is_r31 ? 5'd31 :
                      dst_is_rt  ? rt    : 
                                   rd;

assign rf_raddr1 = rs;
assign rf_raddr2 = rt;
regfile u_regfile(
    .clk    (clk      ),
    .raddr1 (rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (rf_we    ),
    .waddr  (rf_waddr ),
    .wdata  (rf_wdata )
    );

assign rf_rs_value = rf_rdata1;
assign rf_rt_value = rf_rdata2;
assign rs_value = PIPELINE_FORWARDING && es_forward_valid && (es_producer_dest == rs) ? es_forward_value :
                  PIPELINE_FORWARDING && ms_forward_valid && (ms_producer_dest == rs) ? ms_forward_value :
                  PIPELINE_FORWARDING && ws_forward_valid && (ws_producer_dest == rs) ? ws_forward_value :
                                                                                         rf_rs_value;
assign rt_value = PIPELINE_FORWARDING && es_forward_valid && (es_producer_dest == rt) ? es_forward_value :
                  PIPELINE_FORWARDING && ms_forward_valid && (ms_producer_dest == rt) ? ms_forward_value :
                  PIPELINE_FORWARDING && ws_forward_valid && (ws_producer_dest == rt) ? ws_forward_value :
                                                                                         rf_rt_value;

assign rs_eq_rt = (rs_value == rt_value);
assign ds_branch_cond_taken = (inst_beq && rs_eq_rt) ||
                              (inst_bne && !rs_eq_rt) ||
                              (inst_bgez && !rs_value[31]) ||
                              (inst_bgtz && !rs_value[31] && (rs_value != 32'b0)) ||
                              (inst_blez && (rs_value[31] || (rs_value == 32'b0))) ||
                              (inst_bltz && rs_value[31]) ||
                              (inst_bltzal && rs_value[31]) ||
                              (inst_bgezal && !rs_value[31]);
assign br_taken = (inst_j || inst_jal || inst_jr || inst_jalr || ds_branch_cond_taken) &&
                  ds_valid && ds_ready_go && ds_allowin;
assign ds_pc_plus_4 = ds_pc + 32'd4;
assign br_target = (inst_beq || inst_bne || inst_bgez || inst_bgtz || inst_blez ||
                    inst_bltz || inst_bgezal || inst_bltzal) ?
                   (ds_pc_plus_4 + {{14{imm[15]}}, imm[15:0], 2'b0}) :
                   (inst_jr || inst_jalr) ? rs_value :
                   /*j/jal*/               {ds_pc_plus_4[31:28], jidx[25:0], 2'b0};

endmodule
