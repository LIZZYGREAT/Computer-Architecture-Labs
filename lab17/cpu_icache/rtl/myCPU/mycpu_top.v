`include "mycpu.h"

module mycpu_top #(
    parameter PIPELINE_FORWARDING = 1'b1,
    parameter ICACHE_ENABLE = 1'b1
)(
    input         aclk,
    input         aresetn,
    input  [ 5:0] hw_int,
    // AXI3 master interface (AXI3 WID and 2-bit LOCK retained).
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
    input  [ 3:0] rid,
    input  [31:0] rdata,
    input  [ 1:0] rresp,
    input         rlast,
    input         rvalid,
    output        rready,
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
    output [ 3:0] wid,
    output [31:0] wdata,
    output [ 3:0] wstrb,
    output        wlast,
    output        wvalid,
    input         wready,
    input  [ 3:0] bid,
    input  [ 1:0] bresp,
    input         bvalid,
    output        bready,
    // Trace debug interface.
    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_wen,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata
);

reg reset;
always @(posedge aclk) reset <= ~aresetn;

wire         ds_allowin;
wire         es_allowin;
wire         ms_allowin;
wire         ws_allowin;
wire         fs_to_ds_valid;
wire         ds_to_es_valid;
wire         es_to_ms_valid;
wire         ms_to_ws_valid;
wire [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus;
wire [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus;
wire [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus;
wire [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus;
wire [`WS_TO_RF_BUS_WD -1:0] ws_to_rf_bus;
wire [`BR_BUS_WD       -1:0] br_bus;
wire [38:0] es_producer_bus;
wire [38:0] ms_producer_bus;
wire [31:0] cp0_rdata;
wire [31:0] cp0_wdata;
wire [31:0] cp0_epc;
wire [31:0] cp0_index;
wire [31:0] cp0_random;
wire [31:0] cp0_entryhi;
wire [31:0] cp0_entrylo0;
wire [31:0] cp0_entrylo1;
wire [ 7:0] cp0_raddr;
wire [ 7:0] cp0_waddr;
wire        cp0_we;
wire        tlb_commit;
wire [`TLB_OP_WD-1:0] tlb_op_commit;
wire        es_cp0_serial_busy;
wire        ms_cp0_serial_busy;
wire        cp0_serial_busy;
wire        cp0_bev;
wire        interrupt_pending;
wire        trap_commit;
wire [ 4:0] trap_code;
wire [31:0] trap_pc;
wire        trap_bd;
wire [31:0] trap_bad_vaddr;
wire        eret_commit;
wire        pipeline_flush;
wire [31:0] exception_vector;

wire        inst_sram_req;
wire        inst_sram_wr;
wire [ 1:0] inst_sram_size;
wire [ 3:0] inst_sram_wstrb;
wire [31:0] inst_sram_addr;
wire [31:0] inst_sram_wdata;
wire        inst_sram_addr_ok;
wire        inst_sram_data_ok;
wire [31:0] inst_sram_rdata;
wire        data_sram_req;
wire        data_sram_wr;
wire [ 1:0] data_sram_size;
wire [ 3:0] data_sram_wstrb;
wire [31:0] data_sram_addr;
wire [31:0] data_sram_wdata;
wire        data_sram_addr_ok;
wire        data_sram_data_ok;
wire [31:0] data_sram_rdata;
wire        axi_fault;
wire [31:0] inst_sram_pa;
wire [31:0] data_sram_pa;
wire        inst_translation_valid;
wire        data_translation_valid;
wire        inst_cacheable;
wire        data_cacheable;
wire        icache_cpu_addr_ok;
wire        ic_refill_req;
wire [31:0] ic_refill_addr;
wire        ic_refill_addr_ok;
wire        ic_ret_valid;
wire        ic_ret_last;
wire [31:0] ic_ret_data;
wire        ic_uncache_req;
wire [31:0] ic_uncache_addr;
wire        ic_uncache_addr_ok;
wire        ic_uncache_data_ok;
wire [31:0] ic_uncache_data;
wire [31:0] ic_stat_hit;
wire [31:0] ic_stat_miss;
wire [31:0] ic_stat_refill;
wire [31:0] ic_stat_uncache_read;
wire        icache_fault;
wire [31:0] axi_stat_ar_transactions;
wire [31:0] axi_stat_r_beats;
wire [31:0] axi_stat_aw_transactions;
wire [31:0] axi_stat_w_beats;
wire [31:0] axi_stat_b_responses;
wire [31:0] dc_ret_data_unused;
wire        dc_ret_valid_unused;
wire        dc_ret_last_unused;
wire        dc_refill_addr_ok_unused;

wire        tlb_s0_found;
wire [3:0]  tlb_s0_index;
wire [19:0] tlb_s0_pfn;
wire [2:0]  tlb_s0_c;
wire        tlb_s0_d;
wire        tlb_s0_v;
wire        tlb_s1_found;
wire [3:0]  tlb_s1_index;
wire [19:0] tlb_s1_pfn;
wire [2:0]  tlb_s1_c;
wire        tlb_s1_d;
wire        tlb_s1_v;
wire [18:0] tlb_r_vpn2;
wire [7:0]  tlb_r_asid;
wire        tlb_r_g;
wire [19:0] tlb_r_pfn0;
wire [2:0]  tlb_r_c0;
wire        tlb_r_d0;
wire        tlb_r_v0;
wire [19:0] tlb_r_pfn1;
wire [2:0]  tlb_r_c1;
wire        tlb_r_d1;
wire        tlb_r_v1;
wire [3:0]  tlb_w_index;
wire        tlb_write_enable;

assign pipeline_flush = trap_commit || eret_commit;
assign cp0_serial_busy = es_cp0_serial_busy || ms_cp0_serial_busy;
assign exception_vector = cp0_bev ? 32'hbfc0_0380 : 32'h8000_0180;
addr_translate u_inst_translate(
    .vaddr           (inst_sram_addr),
    .is_write        (1'b0),
    .tlb_found       (tlb_s0_found),
    .tlb_pfn         (tlb_s0_pfn),
    .tlb_c           (tlb_s0_c),
    .tlb_d           (tlb_s0_d),
    .tlb_v           (tlb_s0_v),
    .paddr           (inst_sram_pa),
    .translation_valid(inst_translation_valid),
    .cacheable       (inst_cacheable)
);

addr_translate u_data_translate(
    .vaddr           (data_sram_addr),
    .is_write        (data_sram_wr),
    .tlb_found       (tlb_s1_found),
    .tlb_pfn         (tlb_s1_pfn),
    .tlb_c           (tlb_s1_c),
    .tlb_d           (tlb_s1_d),
    .tlb_v           (tlb_s1_v),
    .paddr           (data_sram_pa),
    .translation_valid(data_translation_valid),
    .cacheable       (data_cacheable)
);
assign tlb_w_index = (tlb_op_commit == `TLB_OP_TLBWR) ?
                     cp0_random[3:0] : cp0_index[3:0];
assign tlb_write_enable = tlb_commit &&
                          ((tlb_op_commit == `TLB_OP_TLBWI) ||
                           (tlb_op_commit == `TLB_OP_TLBWR));

cp0_reg cp0_reg(
    .clk              (aclk),
    .reset            (reset),
    .hw_int           (hw_int),
    .cp0_we           (cp0_we),
    .cp0_waddr        (cp0_waddr),
    .cp0_wdata        (cp0_wdata),
    .cp0_raddr        (cp0_raddr),
    .cp0_rdata        (cp0_rdata),
    .exc_commit       (trap_commit),
    .exc_code         (trap_code),
    .exc_pc           (trap_pc),
    .exc_bd           (trap_bd),
    .exc_bad_vaddr    (trap_bad_vaddr),
    .eret_commit      (eret_commit),
    .tlbr_commit      (tlb_commit && (tlb_op_commit == `TLB_OP_TLBR)),
    .tlbr_vpn2        (tlb_r_vpn2),
    .tlbr_asid        (tlb_r_asid),
    .tlbr_g           (tlb_r_g),
    .tlbr_pfn0        (tlb_r_pfn0),
    .tlbr_c0          (tlb_r_c0),
    .tlbr_d0          (tlb_r_d0),
    .tlbr_v0          (tlb_r_v0),
    .tlbr_pfn1        (tlb_r_pfn1),
    .tlbr_c1          (tlb_r_c1),
    .tlbr_d1          (tlb_r_d1),
    .tlbr_v1          (tlb_r_v1),
    .tlbp_commit      (tlb_commit && (tlb_op_commit == `TLB_OP_TLBP)),
    .tlbp_found       (tlb_s1_found),
    .tlbp_index       (tlb_s1_index),
    .cp0_epc          (cp0_epc),
    .cp0_index        (cp0_index),
    .cp0_random       (cp0_random),
    .cp0_entryhi      (cp0_entryhi),
    .cp0_entrylo0     (cp0_entrylo0),
    .cp0_entrylo1     (cp0_entrylo1),
    .cp0_bev          (cp0_bev),
    .interrupt_pending(interrupt_pending)
);

tlb #(.TLBNUM(16)) u_tlb(
    .clk       (aclk),
    .s0_vpn2   (inst_sram_addr[31:13]),
    .s0_odd_page(inst_sram_addr[12]),
    .s0_asid   (cp0_entryhi[7:0]),
    .s0_found  (tlb_s0_found),
    .s0_index  (tlb_s0_index),
    .s0_pfn    (tlb_s0_pfn),
    .s0_c      (tlb_s0_c),
    .s0_d      (tlb_s0_d),
    .s0_v      (tlb_s0_v),
    .s1_vpn2   ((tlb_commit && (tlb_op_commit == `TLB_OP_TLBP)) ?
                cp0_entryhi[31:13] : data_sram_addr[31:13]),
    .s1_odd_page((tlb_commit && (tlb_op_commit == `TLB_OP_TLBP)) ?
                 1'b0 : data_sram_addr[12]),
    .s1_asid   (cp0_entryhi[7:0]),
    .s1_found  (tlb_s1_found),
    .s1_index  (tlb_s1_index),
    .s1_pfn    (tlb_s1_pfn),
    .s1_c      (tlb_s1_c),
    .s1_d      (tlb_s1_d),
    .s1_v      (tlb_s1_v),
    .we        (tlb_write_enable),
    .w_index   (tlb_w_index),
    .w_vpn2    (cp0_entryhi[31:13]),
    .w_asid    (cp0_entryhi[7:0]),
    .w_g       (cp0_entrylo0[0] && cp0_entrylo1[0]),
    .w_pfn0    (cp0_entrylo0[25:6]),
    .w_c0      (cp0_entrylo0[5:3]),
    .w_d0      (cp0_entrylo0[2]),
    .w_v0      (cp0_entrylo0[1]),
    .w_pfn1    (cp0_entrylo1[25:6]),
    .w_c1      (cp0_entrylo1[5:3]),
    .w_d1      (cp0_entrylo1[2]),
    .w_v1      (cp0_entrylo1[1]),
    .r_index   (cp0_index[3:0]),
    .r_vpn2    (tlb_r_vpn2),
    .r_asid    (tlb_r_asid),
    .r_g       (tlb_r_g),
    .r_pfn0    (tlb_r_pfn0),
    .r_c0      (tlb_r_c0),
    .r_d0      (tlb_r_d0),
    .r_v0      (tlb_r_v0),
    .r_pfn1    (tlb_r_pfn1),
    .r_c1      (tlb_r_c1),
    .r_d1      (tlb_r_d1),
    .r_v1      (tlb_r_v1)
);

if_stage if_stage(
    .clk               (aclk),
    .reset             (reset),
    .trap_redirect     (trap_commit),
    .eret_redirect     (eret_commit),
    .trap_vector       (exception_vector),
    .eret_target       (cp0_epc),
    .ds_allowin        (ds_allowin),
    .br_bus            (br_bus),
    .fs_to_ds_valid    (fs_to_ds_valid),
    .fs_to_ds_bus      (fs_to_ds_bus),
    .inst_sram_req     (inst_sram_req),
    .inst_sram_wr      (inst_sram_wr),
    .inst_sram_size    (inst_sram_size),
    .inst_sram_wstrb   (inst_sram_wstrb),
    .inst_sram_addr    (inst_sram_addr),
    .inst_sram_wdata   (inst_sram_wdata),
    .inst_sram_addr_ok (inst_sram_addr_ok),
    .inst_sram_data_ok (inst_sram_data_ok),
    .inst_sram_rdata   (inst_sram_rdata)
);

id_stage #(.PIPELINE_FORWARDING(PIPELINE_FORWARDING)) id_stage(
    .clk              (aclk),
    .reset            (reset),
    .flush            (pipeline_flush),
    .interrupt_pending(interrupt_pending),
    .cp0_serial_busy  (cp0_serial_busy),
    .es_allowin       (es_allowin),
    .ds_allowin       (ds_allowin),
    .fs_to_ds_valid   (fs_to_ds_valid),
    .fs_to_ds_bus     (fs_to_ds_bus),
    .ds_to_es_valid   (ds_to_es_valid),
    .ds_to_es_bus     (ds_to_es_bus),
    .br_bus           (br_bus),
    .ws_to_rf_bus     (ws_to_rf_bus),
    .es_producer_bus  (es_producer_bus),
    .ms_producer_bus  (ms_producer_bus)
);

exe_stage exe_stage(
    .clk              (aclk),
    .reset            (reset),
    .flush            (pipeline_flush),
    .ms_allowin       (ms_allowin),
    .es_allowin       (es_allowin),
    .ds_to_es_valid   (ds_to_es_valid),
    .ds_to_es_bus     (ds_to_es_bus),
    .es_to_ms_valid   (es_to_ms_valid),
    .es_to_ms_bus     (es_to_ms_bus),
    .es_producer_bus  (es_producer_bus),
    .cp0_serial_busy  (es_cp0_serial_busy)
);

mem_stage mem_stage(
    .clk                (aclk),
    .reset              (reset),
    .cp0_rdata           (cp0_rdata),
    .cp0_we              (cp0_we),
    .cp0_waddr           (cp0_waddr),
    .cp0_wdata           (cp0_wdata),
    .cp0_raddr           (cp0_raddr),
    .cp0_serial_busy     (ms_cp0_serial_busy),
    .tlb_commit          (tlb_commit),
    .tlb_op_commit       (tlb_op_commit),
    .trap_commit         (trap_commit),
    .trap_code           (trap_code),
    .trap_pc             (trap_pc),
    .trap_bd             (trap_bd),
    .trap_bad_vaddr      (trap_bad_vaddr),
    .eret_commit         (eret_commit),
    .ws_allowin          (ws_allowin),
    .ms_allowin          (ms_allowin),
    .es_to_ms_valid      (es_to_ms_valid),
    .es_to_ms_bus        (es_to_ms_bus),
    .data_sram_req       (data_sram_req),
    .data_sram_wr        (data_sram_wr),
    .data_sram_size      (data_sram_size),
    .data_sram_wstrb     (data_sram_wstrb),
    .data_sram_addr      (data_sram_addr),
    .data_sram_wdata     (data_sram_wdata),
    .data_sram_addr_ok   (data_sram_addr_ok),
    .data_sram_data_ok   (data_sram_data_ok),
    .data_sram_rdata     (data_sram_rdata),
    .ms_to_ws_valid      (ms_to_ws_valid),
    .ms_to_ws_bus        (ms_to_ws_bus),
    .ms_producer_bus     (ms_producer_bus)
);

wb_stage wb_stage(
    .clk              (aclk),
    .reset            (reset),
    .ws_allowin       (ws_allowin),
    .ms_to_ws_valid   (ms_to_ws_valid),
    .ms_to_ws_bus     (ms_to_ws_bus),
    .ws_to_rf_bus     (ws_to_rf_bus),
    .debug_wb_pc      (debug_wb_pc),
    .debug_wb_rf_wen  (debug_wb_rf_wen),
    .debug_wb_rf_wnum (debug_wb_rf_wnum),
    .debug_wb_rf_wdata(debug_wb_rf_wdata)
);

icache u_icache(
    .clk(aclk),
    .resetn(aresetn),
    .cpu_req(inst_sram_req && inst_translation_valid),
    .cpu_cacheable(inst_cacheable && ICACHE_ENABLE),
    .cpu_addr(inst_sram_pa),
    .cpu_addr_ok(icache_cpu_addr_ok),
    .cpu_data_ok(inst_sram_data_ok),
    .cpu_rdata(inst_sram_rdata),
    .refill_req(ic_refill_req),
    .refill_addr(ic_refill_addr),
    .refill_addr_ok(ic_refill_addr_ok),
    .refill_data_valid(ic_ret_valid),
    .refill_data_last(ic_ret_last),
    .refill_data(ic_ret_data),
    .bridge_fault(axi_fault),
    .uncache_req(ic_uncache_req),
    .uncache_addr(ic_uncache_addr),
    .uncache_addr_ok(ic_uncache_addr_ok),
    .uncache_data_ok(ic_uncache_data_ok),
    .uncache_data(ic_uncache_data),
    .stat_hit(ic_stat_hit),
    .stat_miss(ic_stat_miss),
    .stat_refill(ic_stat_refill),
    .stat_uncache_read(ic_stat_uncache_read),
    .cache_fault(icache_fault)
);

assign inst_sram_addr_ok = icache_cpu_addr_ok && inst_translation_valid;

cache_axi3_bridge u_cache_axi3_bridge(
    .aclk(aclk),
    .aresetn(aresetn),
    .ic_refill_req(ic_refill_req),
    .ic_refill_addr(ic_refill_addr),
    .ic_refill_addr_ok(ic_refill_addr_ok),
    .ic_ret_valid(ic_ret_valid),
    .ic_ret_last(ic_ret_last),
    .ic_ret_data(ic_ret_data),
    .dc_refill_req(1'b0),
    .dc_refill_addr(32'b0),
    .dc_refill_addr_ok(dc_refill_addr_ok_unused),
    .dc_ret_valid(dc_ret_valid_unused),
    .dc_ret_last(dc_ret_last_unused),
    .dc_ret_data(dc_ret_data_unused),
    .inst_req(ic_uncache_req),
    .inst_size(inst_sram_size),
    .inst_addr(ic_uncache_addr),
    .inst_addr_ok(ic_uncache_addr_ok),
    .inst_data_ok(ic_uncache_data_ok),
    .inst_rdata(ic_uncache_data),
    .data_req(data_sram_req && data_translation_valid),
    .data_wr(data_sram_wr),
    .data_size(data_sram_size),
    .data_wstrb(data_sram_wstrb),
    .data_addr(data_sram_pa),
    .data_wdata(data_sram_wdata),
    .data_addr_ok(data_sram_addr_ok),
    .data_data_ok(data_sram_data_ok),
    .data_rdata(data_sram_rdata),
    .dc_writeback_req(1'b0),
    .dc_writeback_addr(32'b0),
    .dc_writeback_data(256'b0),
    .dc_writeback_addr_ok(),
    .dc_writeback_done(),
    .axi_fault(axi_fault),
    .stat_ar_transactions(axi_stat_ar_transactions),
    .stat_r_beats(axi_stat_r_beats),
    .stat_aw_transactions(axi_stat_aw_transactions),
    .stat_w_beats(axi_stat_w_beats),
    .stat_b_responses(axi_stat_b_responses),
    .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize),
    .arburst(arburst), .arlock(arlock), .arcache(arcache), .arprot(arprot),
    .arvalid(arvalid), .arready(arready), .rid(rid), .rdata(rdata),
    .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready),
    .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
    .awburst(awburst), .awlock(awlock), .awcache(awcache), .awprot(awprot),
    .awvalid(awvalid), .awready(awready), .wid(wid), .wdata(wdata),
    .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
    .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready)
);

endmodule
