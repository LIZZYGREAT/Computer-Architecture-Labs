/*------------------------------------------------------------------------------
--------------------------------------------------------------------------------
Copyright (c) 2016, Loongson Technology Corporation Limited.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this 
list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, 
this list of conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.

3. Neither the name of Loongson Technology Corporation Limited nor the names of 
its contributors may be used to endorse or promote products derived from this 
software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
DISCLAIMED. IN NO EVENT SHALL LOONGSON TECHNOLOGY CORPORATION LIMITED BE LIABLE
TO ANY PARTY FOR DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE 
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) 
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--------------------------------------------------------------------------------
------------------------------------------------------------------------------*/
`timescale 1ns / 1ps

`define TRACE_REF_FILE "../../../../../../../cpu132_gettrace/golden_trace.txt"
`define CONFREG_NUM_REG      soc_lite.confreg.num_data
`define CONFREG_OPEN_TRACE   soc_lite.confreg.open_trace
`define CONFREG_NUM_MONITOR  soc_lite.confreg.num_monitor
`define CONFREG_UART_DISPLAY soc_lite.confreg.write_uart_valid
`define CONFREG_UART_DATA    soc_lite.confreg.write_uart_data
`define END_PC 32'hbfc00100

module tb_top #(parameter PIPELINE_FORWARDING = 1'b1)();
reg resetn;
reg clk;

//goio
wire [15:0] led;
wire [1 :0] led_rg0;
wire [1 :0] led_rg1;
wire [7 :0] num_csn;
wire [6 :0] num_a_g;
wire [7 :0] switch;
wire [3 :0] btn_key_col;
wire [3 :0] btn_key_row;
wire [1 :0] btn_step;
assign switch      = 8'hff;
assign btn_key_row = 4'd0;
assign btn_step    = 2'd3;

initial
begin
    clk = 1'b0;
    resetn = 1'b0;
    #2000;
    resetn = 1'b1;
end
always #5 clk=~clk;
soc_lite_top #(.SIMULATION(1'b1), .PIPELINE_FORWARDING(PIPELINE_FORWARDING)) soc_lite
(
       .resetn      (resetn     ), 
       .clk         (clk        ),
    
        //------gpio-------
        .num_csn    (num_csn    ),
        .num_a_g    (num_a_g    ),
        .led        (led        ),
        .led_rg0    (led_rg0    ),
        .led_rg1    (led_rg1    ),
        .switch     (switch     ),
        .btn_key_col(btn_key_col),
        .btn_key_row(btn_key_row),
        .btn_step   (btn_step   )
    );   

//soc lite signals
//"soc_clk" means clk in cpu
//"wb" means write-back stage in pipeline
//"rf" means regfiles in cpu
//"w" in "wen/wnum/wdata" means writing
wire soc_clk;
wire [31:0] debug_wb_pc;
wire [3 :0] debug_wb_rf_wen;
wire [4 :0] debug_wb_rf_wnum;
wire [31:0] debug_wb_rf_wdata;
assign soc_clk           = soc_lite.cpu_clk;
assign debug_wb_pc       = soc_lite.debug_wb_pc;
assign debug_wb_rf_wen   = soc_lite.debug_wb_rf_wen;
assign debug_wb_rf_wnum  = soc_lite.debug_wb_rf_wnum;
assign debug_wb_rf_wdata = soc_lite.debug_wb_rf_wdata;

// open the trace file;
integer trace_ref;
integer trace_ref_plusarg;
reg [1023:0] trace_ref_path;
integer trace_scan_result;
integer trace_records_read;
integer trace_matched_writes;
integer trace_remaining_writes;
reg     trace_error;
reg     trace_cmp_flag;
reg     debug_end;
integer pipeline_cycles;
integer pipeline_stall_cycles;
integer forward_ex_uses;
integer forward_mem_uses;
integer forward_wb_uses;
integer hazard_load_use_stalls;
integer hazard_store_base_forwards;
integer hazard_store_data_forwards;
integer hazard_branch_forwards;
integer hazard_jr_forwards;
integer hazard_priority_ex_uses;
integer hazard_zero_dest_writes;
integer zero_reg_writeback_attempts;
integer expected_functional_points;
integer functional_point_passes;
integer expected_points_plusarg;
reg     functional_point_count_error;
wire ds_instruction_issued = soc_lite.cpu.id_stage.ds_to_es_valid &&
                             soc_lite.cpu.id_stage.es_allowin;
initial begin
    trace_records_read = 0;
    trace_matched_writes = 0;
    trace_remaining_writes = 0;
    trace_error = 1'b0;
    pipeline_cycles = 0;
    pipeline_stall_cycles = 0;
    forward_ex_uses = 0;
    forward_mem_uses = 0;
    forward_wb_uses = 0;
    hazard_load_use_stalls = 0;
    hazard_store_base_forwards = 0;
    hazard_store_data_forwards = 0;
    hazard_branch_forwards = 0;
    hazard_jr_forwards = 0;
    hazard_priority_ex_uses = 0;
    hazard_zero_dest_writes = 0;
    zero_reg_writeback_attempts = 0;
    functional_point_passes = 0;
    functional_point_count_error = 1'b0;
    expected_functional_points = 23;
    expected_points_plusarg = $value$plusargs("EXPECTED_POINTS=%d", expected_functional_points);
    $display("EXPECTED_FUNCTIONAL_POINTS=%0d", expected_functional_points);
    trace_ref_path = `TRACE_REF_FILE;
    trace_ref_plusarg = $value$plusargs("TRACE_REF=%s", trace_ref_path);
    trace_ref = $fopen(trace_ref_path, "r");
    if (trace_ref == 0)
    begin
        $display("TRACE_REF_OPEN_FAIL path=%s", trace_ref_path);
        $fatal(1, "reference trace could not be opened");
    end
    else
    begin
        $display("TRACE_REF_OPEN_OK path=%s", trace_ref_path);
        $display("TRACE_REF_PLUSARG=%0d", trace_ref_plusarg);
    end
end

always @(posedge soc_clk)
begin
    if (!resetn)
    begin
        pipeline_cycles <= 0;
        pipeline_stall_cycles <= 0;
        forward_ex_uses <= 0;
        forward_mem_uses <= 0;
        forward_wb_uses <= 0;
        hazard_load_use_stalls <= 0;
        hazard_store_base_forwards <= 0;
        hazard_store_data_forwards <= 0;
        hazard_branch_forwards <= 0;
        hazard_jr_forwards <= 0;
        hazard_priority_ex_uses <= 0;
        hazard_zero_dest_writes <= 0;
        zero_reg_writeback_attempts <= 0;
    end
    else if (!debug_end)
    begin
        pipeline_cycles <= pipeline_cycles + 1;
        if (soc_lite.cpu.id_stage.ds_stall)
            pipeline_stall_cycles <= pipeline_stall_cycles + 1;
        // Count a stage selection only when this ID instruction is accepted by EX.
        // Each counter is issue cycles per forwarding level, not source operands.
        if (ds_instruction_issued &&
            (soc_lite.cpu.id_stage.ds_forward_rs_ex || soc_lite.cpu.id_stage.ds_forward_rt_ex))
            forward_ex_uses <= forward_ex_uses + 1;
        if (ds_instruction_issued &&
            (soc_lite.cpu.id_stage.ds_forward_rs_ms || soc_lite.cpu.id_stage.ds_forward_rt_ms))
            forward_mem_uses <= forward_mem_uses + 1;
        if (ds_instruction_issued &&
            (soc_lite.cpu.id_stage.ds_forward_rs_ws || soc_lite.cpu.id_stage.ds_forward_rt_ws))
            forward_wb_uses <= forward_wb_uses + 1;
        if (soc_lite.cpu.id_stage.ds_valid && soc_lite.cpu.id_stage.ds_stall &&
            soc_lite.cpu.id_stage.es_hazard_valid && !soc_lite.cpu.id_stage.es_forward_valid)
            hazard_load_use_stalls <= hazard_load_use_stalls + 1;
        if (ds_instruction_issued && soc_lite.cpu.id_stage.inst_sw &&
            (soc_lite.cpu.id_stage.ds_forward_rs_ex || soc_lite.cpu.id_stage.ds_forward_rs_ms ||
             soc_lite.cpu.id_stage.ds_forward_rs_ws))
            hazard_store_base_forwards <= hazard_store_base_forwards + 1;
        if (ds_instruction_issued && soc_lite.cpu.id_stage.inst_sw &&
            (soc_lite.cpu.id_stage.ds_forward_rt_ex || soc_lite.cpu.id_stage.ds_forward_rt_ms ||
             soc_lite.cpu.id_stage.ds_forward_rt_ws))
            hazard_store_data_forwards <= hazard_store_data_forwards + 1;
        if (ds_instruction_issued &&
            (soc_lite.cpu.id_stage.inst_beq || soc_lite.cpu.id_stage.inst_bne) &&
            (soc_lite.cpu.id_stage.ds_forward_rs_ex || soc_lite.cpu.id_stage.ds_forward_rt_ex ||
             soc_lite.cpu.id_stage.ds_forward_rs_ms || soc_lite.cpu.id_stage.ds_forward_rt_ms ||
             soc_lite.cpu.id_stage.ds_forward_rs_ws || soc_lite.cpu.id_stage.ds_forward_rt_ws))
            hazard_branch_forwards <= hazard_branch_forwards + 1;
        if (ds_instruction_issued && soc_lite.cpu.id_stage.inst_jr &&
            (soc_lite.cpu.id_stage.ds_forward_rs_ex || soc_lite.cpu.id_stage.ds_forward_rs_ms ||
             soc_lite.cpu.id_stage.ds_forward_rs_ws))
            hazard_jr_forwards <= hazard_jr_forwards + 1;
        if (ds_instruction_issued &&
            soc_lite.cpu.id_stage.es_hazard_valid && soc_lite.cpu.id_stage.ms_hazard_valid &&
            (soc_lite.cpu.id_stage.es_producer_dest == soc_lite.cpu.id_stage.ms_producer_dest) &&
            (soc_lite.cpu.id_stage.ds_forward_rs_ex || soc_lite.cpu.id_stage.ds_forward_rt_ex))
            hazard_priority_ex_uses <= hazard_priority_ex_uses + 1;
        if (soc_lite.cpu.exe_stage.es_valid && soc_lite.cpu.exe_stage.es_gr_we &&
            (soc_lite.cpu.exe_stage.es_dest == 5'd0))
            hazard_zero_dest_writes <= hazard_zero_dest_writes + 1;
        if ((|debug_wb_rf_wen) && (debug_wb_rf_wnum == 5'd0))
        begin
            zero_reg_writeback_attempts <= zero_reg_writeback_attempts + 1;
            $display("ZERO_REG_WRITEBACK_ASSERT_FAIL pc=%08h", debug_wb_pc);
        end
    end
end

//get reference result in falling edge

reg [31:0] ref_wb_pc;
reg [4 :0] ref_wb_rf_wnum;
reg [31:0] ref_wb_rf_wdata;

always @(posedge soc_clk)
begin 
    #1;
    if(|debug_wb_rf_wen && debug_wb_rf_wnum!=5'd0 && !debug_end && `CONFREG_OPEN_TRACE)
    begin
        trace_cmp_flag=1'b0;
        while (!trace_cmp_flag && !($feof(trace_ref)))
        begin
            trace_scan_result = $fscanf(trace_ref, "%h %h %h %h", trace_cmp_flag,
                                        ref_wb_pc, ref_wb_rf_wnum, ref_wb_rf_wdata);
            if (trace_scan_result == 4)
            begin
                trace_records_read = trace_records_read + 1;
            end
            else
            begin
                trace_error = 1'b1;
                trace_cmp_flag = 1'b1;
                $display("TRACE_READ_FAIL record=%0d", trace_records_read + 1);
            end
        end
        if (trace_cmp_flag && !trace_error)
            trace_matched_writes = trace_matched_writes + 1;
        else if (!trace_cmp_flag)
        begin
            trace_error = 1'b1;
            $display("TRACE_EOF before expected writeback=%0d", trace_matched_writes + 1);
        end
    end
end

//wdata[i*8+7 : i*8] is valid, only wehile wen[i] is valid
wire [31:0] debug_wb_rf_wdata_v;
wire [31:0] ref_wb_rf_wdata_v;
assign debug_wb_rf_wdata_v[31:24] = debug_wb_rf_wdata[31:24] & {8{debug_wb_rf_wen[3]}};
assign debug_wb_rf_wdata_v[23:16] = debug_wb_rf_wdata[23:16] & {8{debug_wb_rf_wen[2]}};
assign debug_wb_rf_wdata_v[15: 8] = debug_wb_rf_wdata[15: 8] & {8{debug_wb_rf_wen[1]}};
assign debug_wb_rf_wdata_v[7 : 0] = debug_wb_rf_wdata[7 : 0] & {8{debug_wb_rf_wen[0]}};
assign   ref_wb_rf_wdata_v[31:24] =   ref_wb_rf_wdata[31:24] & {8{debug_wb_rf_wen[3]}};
assign   ref_wb_rf_wdata_v[23:16] =   ref_wb_rf_wdata[23:16] & {8{debug_wb_rf_wen[2]}};
assign   ref_wb_rf_wdata_v[15: 8] =   ref_wb_rf_wdata[15: 8] & {8{debug_wb_rf_wen[1]}};
assign   ref_wb_rf_wdata_v[7 : 0] =   ref_wb_rf_wdata[7 : 0] & {8{debug_wb_rf_wen[0]}};


//compare result in rsing edge 
reg debug_wb_err;
always @(posedge soc_clk)
begin
    #2;
    if(!resetn)
    begin
        debug_wb_err <= 1'b0;
    end
    else if(|debug_wb_rf_wen && debug_wb_rf_wnum!=5'd0 && !debug_end && `CONFREG_OPEN_TRACE)
    begin
        if (  (debug_wb_pc!==ref_wb_pc) || (debug_wb_rf_wnum!==ref_wb_rf_wnum)
            ||(debug_wb_rf_wdata_v!==ref_wb_rf_wdata_v) )
        begin
            $display("TRACE_MISMATCH");
            $display("--------------------------------------------------------------");
            $display("[%t] Error!!!",$time);
            $display("    reference: PC = 0x%8h, wb_rf_wnum = 0x%2h, wb_rf_wdata = 0x%8h",
                      ref_wb_pc, ref_wb_rf_wnum, ref_wb_rf_wdata_v);
            $display("    mycpu    : PC = 0x%8h, wb_rf_wnum = 0x%2h, wb_rf_wdata = 0x%8h",
                      debug_wb_pc, debug_wb_rf_wnum, debug_wb_rf_wdata_v);
            $display("--------------------------------------------------------------");
            debug_wb_err <= 1'b1;
            #40;
            $finish;
        end
    end
end

//monitor numeric display
reg [7:0] err_count;
wire [31:0] confreg_num_reg = `CONFREG_NUM_REG;
reg  [31:0] confreg_num_reg_r;
always @(posedge soc_clk)
begin
    confreg_num_reg_r <= confreg_num_reg;
    if (!resetn)
    begin
        err_count <= 8'd0;
    end
    else if (confreg_num_reg_r != confreg_num_reg && `CONFREG_NUM_MONITOR)
    begin
        if(confreg_num_reg[7:0]!=confreg_num_reg_r[7:0]+1'b1)
        begin
            $display("--------------------------------------------------------------");
            $display("[%t] Error(%d)!!! Occurred in number 8'd%02d Functional Test Point!",$time, err_count, confreg_num_reg[31:24]);
            $display("--------------------------------------------------------------");
            err_count <= err_count + 1'b1;
        end
        else if(confreg_num_reg[31:24]!=confreg_num_reg_r[31:24]+1'b1)
        begin
            $display("--------------------------------------------------------------");
            $display("[%t] Error(%d)!!! Unknown, Functional Test Point numbers are unequal!",$time,err_count);
            $display("--------------------------------------------------------------");
            $display("==============================================================");
            err_count <= err_count + 1'b1;
        end
        else
        begin
            $display("----[%t] Number 8'd%02d Functional Test Point PASS!!!", $time, confreg_num_reg[31:24]);
            functional_point_passes <= functional_point_passes + 1;
        end
    end
end

//monitor test
initial
begin
    $timeformat(-9,0," ns",10);
    while(!resetn) #5;
    $display("==============================================================");
    $display("Test begin!");
    $display("PIPELINE_FORWARDING=%0d", PIPELINE_FORWARDING);

    #10000;
    while(`CONFREG_NUM_MONITOR)
    begin
        #10000;
        $display ("        [%t] Test is running, debug_wb_pc = 0x%8h",$time, debug_wb_pc);
    end
end

//模拟串口打印
wire uart_display;
wire [7:0] uart_data;
assign uart_display = `CONFREG_UART_DISPLAY;
assign uart_data    = `CONFREG_UART_DATA;

always @(posedge soc_clk)
begin
    if(uart_display && uart_data != 8'hff)
    begin
        $write("%c",uart_data);
    end
end

//test end
wire global_err = debug_wb_err || (err_count!=8'd0) || trace_error ||
                  (zero_reg_writeback_attempts != 0) || functional_point_count_error;
wire test_end = (debug_wb_pc==`END_PC) || (uart_display && uart_data==8'hff);
always @(posedge soc_clk)
begin
    if (!resetn)
    begin
        debug_end <= 1'b0;
    end
    else if(test_end && !debug_end)
    begin
        debug_end <= 1'b1;
        $display("==============================================================");
        $display("Test end!");
        #40;
        trace_remaining_writes = 0;
        begin : trace_tail_scan
            while (!($feof(trace_ref)))
            begin
                trace_scan_result = $fscanf(trace_ref, "%h %h %h %h", trace_cmp_flag,
                                            ref_wb_pc, ref_wb_rf_wnum, ref_wb_rf_wdata);
                if (trace_scan_result == 4)
                begin
                    trace_records_read = trace_records_read + 1;
                    if (trace_cmp_flag)
                        trace_remaining_writes = trace_remaining_writes + 1;
                end
                else if (!($feof(trace_ref)))
                begin
                    trace_error = 1'b1;
                    $display("TRACE_TAIL_READ_FAIL");
                    disable trace_tail_scan;
                end
            end
        end
        if (trace_remaining_writes != 0)
        begin
            trace_error = 1'b1;
            $display("TRACE_REMAINING_RECORDS=%0d", trace_remaining_writes);
        end
        $display("TRACE_RECORDS_READ=%0d", trace_records_read);
        $display("TRACE_MATCHED_WRITES=%0d", trace_matched_writes);
        $display("PIPELINE_CYCLES=%0d", pipeline_cycles);
        $display("PIPELINE_STALL_CYCLES=%0d", pipeline_stall_cycles);
        $display("FORWARD_EX_USES=%0d", forward_ex_uses);
        $display("FORWARD_MEM_USES=%0d", forward_mem_uses);
        $display("FORWARD_WB_USES=%0d", forward_wb_uses);
        $display("HAZARD_LOAD_USE_STALLS=%0d", hazard_load_use_stalls);
        $display("HAZARD_STORE_BASE_FORWARDS=%0d", hazard_store_base_forwards);
        $display("HAZARD_STORE_DATA_FORWARDS=%0d", hazard_store_data_forwards);
        $display("HAZARD_BRANCH_FORWARDS=%0d", hazard_branch_forwards);
        $display("HAZARD_JR_FORWARDS=%0d", hazard_jr_forwards);
        $display("HAZARD_PRIORITY_EX_USES=%0d", hazard_priority_ex_uses);
        $display("HAZARD_ZERO_DEST_WRITES=%0d", hazard_zero_dest_writes);
        $display("ZERO_REG_WRITEBACK_ATTEMPTS=%0d", zero_reg_writeback_attempts);
        $display("FUNCTIONAL_POINT_PASSES=%0d", functional_point_passes);
        if (functional_point_passes != expected_functional_points)
        begin
            functional_point_count_error = 1'b1;
            $display("FUNCTIONAL_POINT_COUNT_MISMATCH expected=%0d actual=%0d",
                     expected_functional_points, functional_point_passes);
        end
        $fclose(trace_ref);
        if (global_err || trace_error)
        begin
            $display("Fail!!!Total %d errors!",err_count);
        end
        else
        begin
            $display("----PASS!!!");
        end
	    $finish;
	end
end
endmodule
