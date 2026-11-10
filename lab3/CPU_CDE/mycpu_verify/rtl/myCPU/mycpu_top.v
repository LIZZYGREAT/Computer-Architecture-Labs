module mycpu_top #(parameter PIPELINE_FORWARDING = 1'b1)(
    input         clk,
    input         resetn,
    input  [ 5:0] hw_int,
    // inst sram interface
    output        inst_sram_en,
    output [ 3:0] inst_sram_wen,
    output [31:0] inst_sram_addr,
    output [31:0] inst_sram_wdata,
    input  [31:0] inst_sram_rdata,
    // data sram interface
    output        data_sram_en,
    output [ 3:0] data_sram_wen,
    output [31:0] data_sram_addr,
    output [31:0] data_sram_wdata,
    input  [31:0] data_sram_rdata,
    // trace debug interface
    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_wen,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata
);
reg         reset;
always @(posedge clk) reset <= ~resetn;

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

assign pipeline_flush = trap_commit || eret_commit;
assign cp0_serial_busy = es_cp0_serial_busy || ms_cp0_serial_busy;
assign exception_vector = cp0_bev ? 32'hbfc0_0380 : 32'h8000_0180;

cp0_reg cp0_reg(
    .clk              (clk),
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

// IF stage
if_stage if_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .trap_redirect  (trap_commit    ),
    .eret_redirect  (eret_commit    ),
    .trap_vector    (exception_vector),
    .eret_target    (cp0_epc        ),
    //allowin
    .ds_allowin     (ds_allowin     ),
    //brbus
    .br_bus         (br_bus         ),
    //outputs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    // inst sram interface
    .inst_sram_en   (inst_sram_en   ),
    .inst_sram_wen  (inst_sram_wen  ),
    .inst_sram_addr (inst_sram_addr ),
    .inst_sram_wdata(inst_sram_wdata),
    .inst_sram_rdata(inst_sram_rdata)
);
// ID stage
id_stage #(.PIPELINE_FORWARDING(PIPELINE_FORWARDING)) id_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .flush          (pipeline_flush ),
    .interrupt_pending(interrupt_pending),
    .cp0_serial_busy(cp0_serial_busy),
    //allowin
    .es_allowin     (es_allowin     ),
    .ds_allowin     (ds_allowin     ),
    //from fs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    //to es
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    //to fs
    .br_bus         (br_bus         ),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    .es_producer_bus(es_producer_bus),
    .ms_producer_bus(ms_producer_bus)
);
// EXE stage
exe_stage exe_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .flush          (pipeline_flush ),
    //allowin
    .ms_allowin     (ms_allowin     ),
    .es_allowin     (es_allowin     ),
    //from ds
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    //to ms
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    .es_producer_bus(es_producer_bus),
    .cp0_serial_busy(es_cp0_serial_busy),
    // data sram interface
    .data_sram_en   (data_sram_en   ),
    .data_sram_wen  (data_sram_wen  ),
    .data_sram_addr (data_sram_addr ),
    .data_sram_wdata(data_sram_wdata)
);
// MEM stage
mem_stage mem_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .cp0_rdata      (cp0_rdata      ),
    .cp0_we         (cp0_we         ),
    .cp0_waddr      (cp0_waddr      ),
    .cp0_wdata      (cp0_wdata      ),
    .cp0_raddr      (cp0_raddr      ),
    .cp0_serial_busy(ms_cp0_serial_busy),
    .trap_commit    (trap_commit    ),
    .trap_code      (trap_code      ),
    .trap_pc        (trap_pc        ),
    .trap_bd        (trap_bd        ),
    .trap_bad_vaddr (trap_bad_vaddr ),
    .eret_commit    (eret_commit    ),
    //allowin
    .ws_allowin     (ws_allowin     ),
    .ms_allowin     (ms_allowin     ),
    //from es
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    //to ws
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    .ms_producer_bus(ms_producer_bus),
    //from data-sram
    .data_sram_rdata(data_sram_rdata)
);
// WB stage
wb_stage wb_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ws_allowin     (ws_allowin     ),
    //from ms
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    //trace debug interface
    .debug_wb_pc      (debug_wb_pc      ),
    .debug_wb_rf_wen  (debug_wb_rf_wen  ),
    .debug_wb_rf_wnum (debug_wb_rf_wnum ),
    .debug_wb_rf_wdata(debug_wb_rf_wdata)
);

endmodule
