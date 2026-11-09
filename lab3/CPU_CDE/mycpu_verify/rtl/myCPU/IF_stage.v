`include "mycpu.h"

module if_stage(
    input                          clk            ,
    input                          reset          ,
    //allwoin
    input                          ds_allowin     ,
    //brbus
    input  [`BR_BUS_WD       -1:0] br_bus         ,
    //precise exception and return redirects
    input                          trap_redirect  ,
    input                          eret_redirect  ,
    input  [31:0]                  trap_vector    ,
    input  [31:0]                  eret_target    ,
    //to ds
    output                         fs_to_ds_valid ,
    output [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus   ,
    // inst sram interface
    output        inst_sram_en   ,
    output [ 3:0] inst_sram_wen  ,
    output [31:0] inst_sram_addr ,
    output [31:0] inst_sram_wdata,
    input  [31:0] inst_sram_rdata
);

reg         fs_valid;
wire        fs_ready_go;
wire        fs_allowin;
wire        to_fs_valid;
wire        redirect_valid;

wire [31:0] seq_pc;
wire [31:0] nextpc;

wire         br_taken;
wire [ 31:0] br_target;
wire         br_delay_slot;
assign {br_taken,br_target,br_delay_slot} = br_bus;

wire [31:0] fs_inst;
reg  [31:0] fs_pc;
reg         fs_exception_valid;
reg  [ 4:0] fs_exception_code;
reg  [31:0] fs_bad_vaddr;
assign fs_to_ds_bus = {fs_bad_vaddr,
                       fs_exception_code,
                       fs_exception_valid,
                       br_delay_slot,
                       fs_inst,
                       fs_pc};

// pre-IF stage
assign to_fs_valid  = ~reset;
assign seq_pc       = fs_pc + 32'd4;
assign redirect_valid = trap_redirect || eret_redirect;
assign nextpc       = trap_redirect ? trap_vector :
                      eret_redirect ? eret_target :
                      br_taken      ? br_target : seq_pc;

// IF stage
assign fs_ready_go    = 1'b1;
assign fs_allowin     = !fs_valid || fs_ready_go && ds_allowin;
assign fs_to_ds_valid =  fs_valid && fs_ready_go;
always @(posedge clk) begin
    if (reset) begin
        fs_valid <= 1'b0;
        fs_pc <= 32'hbfbffffc;  //trick: to make nextpc be 0xbfc00000 during reset
        fs_exception_valid <= 1'b0;
        fs_exception_code <= 5'b0;
        fs_bad_vaddr <= 32'b0;
    end
    else if (redirect_valid) begin
        // The synchronous instruction RAM samples the redirect address on
        // this edge, so its response is the first valid instruction after
        // the flush.
        fs_valid <= 1'b1;
        fs_pc <= nextpc;
        fs_exception_valid <= (nextpc[1:0] != 2'b00);
        fs_exception_code <= (nextpc[1:0] != 2'b00) ? `EXC_ADEL : 5'b0;
        fs_bad_vaddr <= nextpc;
    end
    else if (fs_allowin) begin
        fs_valid <= to_fs_valid;
        if (to_fs_valid) begin
            fs_pc <= nextpc;
            fs_exception_valid <= (nextpc[1:0] != 2'b00);
            fs_exception_code <= (nextpc[1:0] != 2'b00) ? `EXC_ADEL : 5'b0;
            fs_bad_vaddr <= nextpc;
        end
    end
end

assign inst_sram_en    = to_fs_valid && (fs_allowin || redirect_valid);
assign inst_sram_wen   = 4'h0;
assign inst_sram_addr  = nextpc;
assign inst_sram_wdata = 32'b0;

assign fs_inst         = inst_sram_rdata;

endmodule
