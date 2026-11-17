`include "mycpu.h"

module mycpu_top #(parameter PIPELINE_FORWARDING = 1'b1)(
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
wire [ 7:0] cp0_raddr;
wire [ 7:0] cp0_waddr;
wire        cp0_we;
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

assign pipeline_flush = trap_commit || eret_commit;
assign cp0_serial_busy = es_cp0_serial_busy || ms_cp0_serial_busy;
assign exception_vector = cp0_bev ? 32'hbfc0_0380 : 32'h8000_0180;

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
    .cp0_epc          (cp0_epc),
    .cp0_bev          (cp0_bev),
    .interrupt_pending(interrupt_pending)
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

axi3_cpu_bus axi3_cpu_bus(
    .aclk(aclk),
    .aresetn(aresetn),
    .inst_req(inst_sram_req),
    .inst_size(inst_sram_size),
    .inst_addr(inst_sram_addr),
    .inst_addr_ok(inst_sram_addr_ok),
    .inst_data_ok(inst_sram_data_ok),
    .inst_rdata(inst_sram_rdata),
    .data_req(data_sram_req),
    .data_wr(data_sram_wr),
    .data_size(data_sram_size),
    .data_wstrb(data_sram_wstrb),
    .data_addr(data_sram_addr),
    .data_wdata(data_sram_wdata),
    .data_addr_ok(data_sram_addr_ok),
    .data_data_ok(data_sram_data_ok),
    .data_rdata(data_sram_rdata),
    .axi_fault(axi_fault),
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
