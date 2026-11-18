`include "mycpu.h"

module if_stage(
    input                          clk             ,
    input                          reset           ,
    input                          ds_allowin      ,
    input  [`BR_BUS_WD       -1:0] br_bus          ,
    input                          trap_redirect   ,
    input                          eret_redirect   ,
    input                          cache_redirect  ,
    input                          tlb_redirect    ,
    input                          cache_resume_valid,
    input  [31:0]                  cache_resume_pc,
    input  [31:0]                  trap_vector     ,
    input  [31:0]                  eret_target     ,
    output                         fs_to_ds_valid  ,
    output [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus    ,
    output                         inst_sram_req   ,
    output                         inst_sram_wr    ,
    output [1:0]                   inst_sram_size  ,
    output [3:0]                   inst_sram_wstrb ,
    output [31:0]                  inst_sram_addr  ,
    output [31:0]                  inst_sram_wdata ,
    input                          inst_sram_addr_ok,
    input                          inst_sram_data_ok,
    input  [31:0]                  inst_sram_rdata
);

localparam IF_REQUEST   = 2'd0;
localparam IF_WAIT_DATA = 2'd1;
localparam IF_HOLD      = 2'd2;

reg [1:0]  state;
reg [31:0] request_pc;
reg        stale_response;
reg [31:0] restart_pc;

reg        response_valid;
reg [31:0] response_pc;
reg [31:0] response_inst;
reg        response_exception_valid;
reg [4:0]  response_exception_code;
reg [31:0] response_bad_vaddr;

reg        delay_slot_pending;
reg        branch_target_valid;
reg [31:0] branch_target_pending;

wire        br_taken;
wire [31:0] br_target;
wire        br_delay_slot;
wire        redirect_valid;
wire [31:0] redirect_pc;
wire        response_fire;
wire        response_is_delay_slot;

assign {br_taken, br_target, br_delay_slot} = br_bus;
assign redirect_valid = trap_redirect || eret_redirect || cache_redirect || tlb_redirect;
assign redirect_pc = trap_redirect ? trap_vector :
                     eret_redirect ? eret_target :
                     ((cache_redirect || tlb_redirect) && cache_resume_valid) ? cache_resume_pc :
                     (state == IF_HOLD) ? response_pc : request_pc;

assign response_fire = response_valid && ds_allowin && !redirect_valid;
assign response_is_delay_slot = delay_slot_pending || br_delay_slot;

assign fs_to_ds_valid = response_valid && !redirect_valid;
assign fs_to_ds_bus = {response_bad_vaddr,
                       response_exception_code,
                       response_exception_valid,
                       response_is_delay_slot,
                       response_inst,
                       response_pc};

assign inst_sram_req   = (state == IF_REQUEST) && !reset && !redirect_valid &&
                         (request_pc[1:0] == 2'b00);
assign inst_sram_wr    = 1'b0;
assign inst_sram_size  = 2'd2;
assign inst_sram_wstrb = 4'b0000;
assign inst_sram_addr  = request_pc;
assign inst_sram_wdata = 32'b0;

always @(posedge clk) begin
    if (reset) begin
        state                    <= IF_REQUEST;
        request_pc               <= 32'hbfc0_0000;
        stale_response           <= 1'b0;
        restart_pc               <= 32'b0;
        response_valid           <= 1'b0;
        response_pc              <= 32'b0;
        response_inst            <= 32'b0;
        response_exception_valid <= 1'b0;
        response_exception_code  <= 5'b0;
        response_bad_vaddr       <= 32'b0;
        delay_slot_pending       <= 1'b0;
        branch_target_valid      <= 1'b0;
        branch_target_pending    <= 32'b0;
    end else if (redirect_valid) begin
        // A trap/ERET kills unaccepted work and buffered instructions. An
        // accepted read must still be drained before issuing from the target.
        response_valid      <= 1'b0;
        delay_slot_pending  <= 1'b0;
        branch_target_valid <= 1'b0;
        if (state == IF_WAIT_DATA && !inst_sram_data_ok) begin
            stale_response <= 1'b1;
            restart_pc     <= redirect_pc;
        end else begin
            stale_response <= 1'b0;
            request_pc     <= redirect_pc;
            state          <= IF_REQUEST;
        end
    end else begin
        if (br_delay_slot) begin
            // The instruction after a control transfer is architecturally
            // executed even when the branch is taken.
            delay_slot_pending  <= 1'b1;
            branch_target_valid <= br_taken;
            branch_target_pending <= br_target;
        end

        case (state)
            IF_REQUEST: begin
                stale_response <= 1'b0;
                if (request_pc[1:0] != 2'b00) begin
                    // Do not send a misaligned PC to the instruction RAM.
                    response_valid           <= 1'b1;
                    response_pc              <= request_pc;
                    response_inst            <= 32'b0;
                    response_exception_valid <= 1'b1;
                    response_exception_code  <= `EXC_ADEL;
                    response_bad_vaddr       <= request_pc;
                    state                    <= IF_HOLD;
                end else if (inst_sram_req && inst_sram_addr_ok) begin
                    if (inst_sram_data_ok) begin
                        response_valid           <= 1'b1;
                        response_pc              <= request_pc;
                        response_inst            <= inst_sram_rdata;
                        response_exception_valid <= 1'b0;
                        response_exception_code  <= 5'b0;
                        response_bad_vaddr       <= 32'b0;
                        state                    <= IF_HOLD;
                    end else begin
                        state <= IF_WAIT_DATA;
                    end
                end
            end

            IF_WAIT_DATA: begin
                if (inst_sram_data_ok) begin
                    if (stale_response) begin
                        // Consume an old-path response without exposing it to
                        // decode. The redirect target was saved on flush.
                        request_pc     <= restart_pc;
                        stale_response <= 1'b0;
                        state          <= IF_REQUEST;
                    end else begin
                        response_valid           <= 1'b1;
                        response_pc              <= request_pc;
                        response_inst            <= inst_sram_rdata;
                        response_exception_valid <= 1'b0;
                        response_exception_code  <= 5'b0;
                        response_bad_vaddr       <= 32'b0;
                        state                    <= IF_HOLD;
                    end
                end
            end

            IF_HOLD: begin
                if (response_fire) begin
                    response_valid <= 1'b0;
                    state          <= IF_REQUEST;
                    if (response_is_delay_slot) begin
                        if (branch_target_valid) begin
                            request_pc <= branch_target_pending;
                        end else if (br_delay_slot && br_taken) begin
                            request_pc <= br_target;
                        end else begin
                            request_pc <= response_pc + 32'd4;
                        end
                        delay_slot_pending  <= 1'b0;
                        branch_target_valid <= 1'b0;
                    end else begin
                        request_pc <= response_pc + 32'd4;
                    end
                end
            end

            default: begin
                state <= IF_REQUEST;
            end
        endcase
    end
end

endmodule
