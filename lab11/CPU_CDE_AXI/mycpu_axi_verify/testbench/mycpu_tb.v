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
`define CONFREG_NUM_REG      soc_lite.u_confreg.num_data
`define CONFREG_OPEN_TRACE   soc_lite.u_confreg.open_trace
`define CONFREG_NUM_MONITOR  soc_lite.u_confreg.num_monitor
`define CONFREG_UART_DISPLAY soc_lite.u_confreg.write_uart_valid
`define CONFREG_UART_DATA    soc_lite.u_confreg.write_uart_data
`define END_PC 32'hbfc00100

module tb_top( );
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
soc_axi_lite_top #(.SIMULATION(1'b1)) soc_lite
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

integer bus_inst_req_accept;
integer bus_inst_data_complete;
integer bus_load_req_accept;
integer bus_load_data_complete;
integer bus_store_req_accept;
integer bus_store_data_complete;
integer bus_stale_fetch_drops;
integer bus_pipeline_cycles;
integer bus_duplicate_store_count;
integer bus_ar_handshakes;
integer bus_r_handshakes;
integer bus_aw_handshakes;
integer bus_w_handshakes;
integer bus_b_handshakes;
integer bus_backpressure_ar_cycles;
integer bus_backpressure_r_cycles;
integer bus_backpressure_aw_cycles;
integer bus_backpressure_w_cycles;
integer bus_backpressure_b_cycles;
reg bus_first_fetch_seen;
reg bus_first_load_seen;
reg bus_first_store_seen;
reg bus_first_redirect_seen;
reg bus_first_stale_drop_seen;
reg bus_first_backpressure_seen;
reg bus_store_pending;
reg bus_first_ar_seen;
reg bus_axi_fault_seen;
integer bus_protocol_faults;
reg debug_wb_err;
always @(posedge soc_clk) begin
    if (!resetn) begin
        bus_inst_req_accept     <= 0;
        bus_inst_data_complete  <= 0;
        bus_load_req_accept     <= 0;
        bus_load_data_complete  <= 0;
        bus_store_req_accept    <= 0;
        bus_store_data_complete <= 0;
        bus_stale_fetch_drops   <= 0;
        bus_pipeline_cycles     <= 0;
        bus_duplicate_store_count <= 0;
        bus_ar_handshakes       <= 0;
        bus_r_handshakes        <= 0;
        bus_aw_handshakes       <= 0;
        bus_w_handshakes        <= 0;
        bus_b_handshakes        <= 0;
        bus_backpressure_ar_cycles <= 0;
        bus_backpressure_r_cycles  <= 0;
        bus_backpressure_aw_cycles <= 0;
        bus_backpressure_w_cycles  <= 0;
        bus_backpressure_b_cycles  <= 0;
        bus_protocol_faults <= 0;
        bus_store_pending = 1'b0;
        bus_first_fetch_seen = 1'b0;
        bus_first_load_seen = 1'b0;
        bus_first_store_seen = 1'b0;
        bus_first_redirect_seen = 1'b0;
        bus_first_stale_drop_seen = 1'b0;
        bus_first_backpressure_seen = 1'b0;
        bus_first_ar_seen = 1'b0;
        bus_axi_fault_seen = 1'b0;
    end else begin
        bus_pipeline_cycles <= bus_pipeline_cycles + 1;
        if (soc_lite.u_cpu.inst_sram_req && soc_lite.u_cpu.inst_sram_addr_ok) begin
            bus_inst_req_accept <= bus_inst_req_accept + 1;
            if (!bus_first_fetch_seen) begin
                bus_first_fetch_seen = 1'b1;
                $display("BUS_ANCHOR event=fetch pc=%08x addr=%08x time_ns=%0t",
                         soc_lite.u_cpu.if_stage.request_pc, soc_lite.u_cpu.inst_sram_addr, $time);
            end
        end
        if (soc_lite.u_cpu.inst_sram_data_ok)
            bus_inst_data_complete <= bus_inst_data_complete + 1;
        if (soc_lite.u_cpu.data_sram_req && soc_lite.u_cpu.data_sram_addr_ok) begin
            if (soc_lite.u_cpu.data_sram_wr) begin
                bus_store_req_accept <= bus_store_req_accept + 1;
                if (bus_store_pending)
                    bus_duplicate_store_count <= bus_duplicate_store_count + 1;
                else
                    bus_store_pending = 1'b1;
                if (!bus_first_store_seen) begin
                    bus_first_store_seen = 1'b1;
                    $display("BUS_ANCHOR event=store pc=%08x addr=%08x size=%0d wstrb=%x wdata=%08x time_ns=%0t",
                             soc_lite.u_cpu.mem_stage.ms_pc, soc_lite.u_cpu.data_sram_addr,
                             soc_lite.u_cpu.data_sram_size, soc_lite.u_cpu.data_sram_wstrb,
                             soc_lite.u_cpu.data_sram_wdata, $time);
                end
            end else begin
                bus_load_req_accept <= bus_load_req_accept + 1;
                if (!bus_first_load_seen) begin
                    bus_first_load_seen = 1'b1;
                    $display("BUS_ANCHOR event=load pc=%08x addr=%08x size=%0d time_ns=%0t",
                             soc_lite.u_cpu.mem_stage.ms_pc, soc_lite.u_cpu.data_sram_addr,
                             soc_lite.u_cpu.data_sram_size, $time);
                end
            end
        end
        if (soc_lite.u_cpu.data_sram_data_ok) begin
            if (soc_lite.u_cpu.data_sram_wr) begin
                bus_store_data_complete <= bus_store_data_complete + 1;
                bus_store_pending = 1'b0;
            end else begin
                bus_load_data_complete <= bus_load_data_complete + 1;
            end
        end
        if (soc_lite.u_cpu.if_stage.stale_response && soc_lite.u_cpu.inst_sram_data_ok) begin
            bus_stale_fetch_drops <= bus_stale_fetch_drops + 1;
            if (!bus_first_stale_drop_seen) begin
                bus_first_stale_drop_seen = 1'b1;
                $display("BUS_ANCHOR event=stale_drop pc=%08x target=%08x time_ns=%0t",
                         soc_lite.u_cpu.if_stage.request_pc, soc_lite.u_cpu.if_stage.restart_pc, $time);
            end
        end
        if ((soc_lite.u_cpu.trap_commit || soc_lite.u_cpu.eret_commit) && !bus_first_redirect_seen) begin
            bus_first_redirect_seen = 1'b1;
            $display("BUS_ANCHOR event=redirect pc=%08x target=%08x time_ns=%0t",
                     soc_lite.u_cpu.mem_stage.ms_pc, soc_lite.u_cpu.if_stage.redirect_pc, $time);
        end
        if (soc_lite.cpu_arvalid && soc_lite.cpu_arready) begin
            bus_ar_handshakes <= bus_ar_handshakes + 1;
            if (!bus_first_ar_seen) begin
                bus_first_ar_seen = 1'b1;
                $display("BUS_ANCHOR event=ar addr=%08x id=%x time_ns=%0t",
                         soc_lite.cpu_araddr, soc_lite.cpu_arid, $time);
            end
        end
        if (soc_lite.cpu_rvalid && soc_lite.cpu_rready)
            bus_r_handshakes <= bus_r_handshakes + 1;
        if (soc_lite.cpu_awvalid && soc_lite.cpu_awready)
            bus_aw_handshakes <= bus_aw_handshakes + 1;
        if (soc_lite.cpu_wvalid && soc_lite.cpu_wready)
            bus_w_handshakes <= bus_w_handshakes + 1;
        if (soc_lite.cpu_bvalid && soc_lite.cpu_bready)
            bus_b_handshakes <= bus_b_handshakes + 1;
        if (soc_lite.u_cpu.axi_fault && !bus_axi_fault_seen) begin
            bus_axi_fault_seen = 1'b1;
            bus_protocol_faults <= bus_protocol_faults + 1;
        end
        if (soc_lite.cpu_arvalid && !soc_lite.cpu_arready) begin
            bus_backpressure_ar_cycles <= bus_backpressure_ar_cycles + 1;
            if (!bus_first_backpressure_seen) begin
                bus_first_backpressure_seen = 1'b1;
                $display("BUS_ANCHOR event=backpressure channel=AR addr=%08x id=%x time_ns=%0t",
                         soc_lite.cpu_araddr, soc_lite.cpu_arid, $time);
            end
        end
        if (soc_lite.cpu_rvalid && !soc_lite.cpu_rready) begin
            bus_backpressure_r_cycles <= bus_backpressure_r_cycles + 1;
            if (!bus_first_backpressure_seen) begin
                bus_first_backpressure_seen = 1'b1;
                $display("BUS_ANCHOR event=backpressure channel=R data=%08x id=%x time_ns=%0t",
                         soc_lite.cpu_rdata, soc_lite.cpu_rid, $time);
            end
        end
        if (soc_lite.cpu_awvalid && !soc_lite.cpu_awready) begin
            bus_backpressure_aw_cycles <= bus_backpressure_aw_cycles + 1;
            if (!bus_first_backpressure_seen) begin
                bus_first_backpressure_seen = 1'b1;
                $display("BUS_ANCHOR event=backpressure channel=AW addr=%08x id=%x time_ns=%0t",
                         soc_lite.cpu_awaddr, soc_lite.cpu_awid, $time);
            end
        end
        if (soc_lite.cpu_wvalid && !soc_lite.cpu_wready) begin
            bus_backpressure_w_cycles <= bus_backpressure_w_cycles + 1;
            if (!bus_first_backpressure_seen) begin
                bus_first_backpressure_seen = 1'b1;
                $display("BUS_ANCHOR event=backpressure channel=W data=%08x strb=%x time_ns=%0t",
                         soc_lite.cpu_wdata, soc_lite.cpu_wstrb, $time);
            end
        end
        if (soc_lite.cpu_bvalid && !soc_lite.cpu_bready) begin
            bus_backpressure_b_cycles <= bus_backpressure_b_cycles + 1;
            if (!bus_first_backpressure_seen) begin
                bus_first_backpressure_seen = 1'b1;
                $display("BUS_ANCHOR event=backpressure channel=B resp=%x id=%x time_ns=%0t",
                         soc_lite.cpu_bresp, soc_lite.cpu_bid, $time);
            end
        end
    end
end

// open the trace file;
integer trace_ref;
integer trace_records_read;
integer trace_valid_records_read;
integer trace_trailing_valid;
integer trace_valid_flag;
integer trace_override;
reg [1023:0] trace_file_path;
reg trace_read_failed;
initial begin
    trace_file_path = `TRACE_REF_FILE;
    trace_override = $value$plusargs("TRACE_REF=%s", trace_file_path);
    trace_ref = $fopen(trace_file_path, "r");
    trace_records_read = 0;
    trace_valid_records_read = 0;
    trace_trailing_valid = 0;
    trace_read_failed = 1'b0;
    if (trace_ref == 0) begin
        $display("COURSE_SOC_FAIL=trace_open_failed path=%s", trace_file_path);
        $finish;
    end
    $display("TRACE_OPEN_PASS path=%s", trace_file_path);
end

//get reference result in falling edge
reg        trace_cmp_flag;
reg        debug_end;

reg [31:0] ref_wb_pc;
reg [4 :0] ref_wb_rf_wnum;
reg [31:0] ref_wb_rf_wdata;

task read_next_valid_trace;
    integer scan_status;
    reg found_valid;
    begin
        found_valid = 1'b0;
        trace_cmp_flag = 1'b0;
        while (!found_valid && !trace_read_failed) begin
            scan_status = $fscanf(trace_ref, "%h %h %h %h",
                                  trace_valid_flag, ref_wb_pc,
                                  ref_wb_rf_wnum, ref_wb_rf_wdata);
            if (scan_status != 4) begin
                trace_read_failed = 1'b1;
                $display("COURSE_SOC_FAIL=trace_early_eof records=%0d valid=%0d scan=%0d",
                         trace_records_read, trace_valid_records_read, scan_status);
            end
            else if ((trace_valid_flag != 0) && (trace_valid_flag != 1)) begin
                trace_read_failed = 1'b1;
                $display("COURSE_SOC_FAIL=trace_invalid_valid_flag record=%0d flag=%0d",
                         trace_records_read + 1, trace_valid_flag);
            end
            else begin
                trace_cmp_flag = (trace_valid_flag == 1);
                trace_records_read = trace_records_read + 1;
                if (trace_cmp_flag === 1'b1) begin
                    found_valid = 1'b1;
                    trace_valid_records_read = trace_valid_records_read + 1;
                end
            end
        end
    end
endtask

task check_trace_exhaustion;
    integer scan_status;
    integer tail_valid;
    reg [31:0] tail_pc;
    reg [4:0] tail_wnum;
    reg [31:0] tail_wdata;
    begin
        scan_status = 4;
        trace_trailing_valid = 0;
        while (scan_status == 4) begin
            scan_status = $fscanf(trace_ref, "%h %h %h %h",
                                  tail_valid, tail_pc, tail_wnum, tail_wdata);
            if (scan_status == 4) begin
                trace_records_read = trace_records_read + 1;
                if (tail_valid == 1) begin
                    trace_trailing_valid = trace_trailing_valid + 1;
                end
                else if (tail_valid != 0) begin
                    trace_read_failed = 1'b1;
                end
            end
            else if (scan_status != -1) begin
                trace_read_failed = 1'b1;
            end
        end
    end
endtask

always @(posedge soc_clk)
begin 
    #1;
    if(|debug_wb_rf_wen && debug_wb_rf_wnum!=5'd0 && !debug_end && `CONFREG_OPEN_TRACE)
    begin
        read_next_valid_trace;
        if (trace_read_failed) begin
            debug_wb_err <= 1'b1;
            #40;
            $finish;
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
always @(posedge soc_clk)
begin
    #2;
    if(!resetn)
    begin
        debug_wb_err <= 1'b0;
    end
    else if(|debug_wb_rf_wen && debug_wb_rf_wnum!=5'd0 && !debug_end &&
            !trace_read_failed && `CONFREG_OPEN_TRACE)
    begin
        if (  (debug_wb_pc!==ref_wb_pc) || (debug_wb_rf_wnum!==ref_wb_rf_wnum)
            ||(debug_wb_rf_wdata_v!==ref_wb_rf_wdata_v) )
        begin
            $display("--------------------------------------------------------------");
            $display("[%t] Error!!!",$time);
            $display("    reference: PC = 0x%8h, wb_rf_wnum = 0x%2h, wb_rf_wdata = 0x%8h",
                      ref_wb_pc, ref_wb_rf_wnum, ref_wb_rf_wdata_v);
            $display("    mycpu    : PC = 0x%8h, wb_rf_wnum = 0x%2h, wb_rf_wdata = 0x%8h",
                      debug_wb_pc, debug_wb_rf_wnum, debug_wb_rf_wdata_v);
            $display("--------------------------------------------------------------");
            $display("COURSE_SOC_FAIL=trace_mismatch");
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
    if(uart_display)
    begin
        if(uart_data==8'hff)
        begin
            //$finish;
        end
        else
        begin
            $write("%c",uart_data);
        end
    end
end

//test end
wire global_err = debug_wb_err || (err_count!=8'd0);
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
        if (trace_ref != 0) begin
            check_trace_exhaustion;
        end
        $display("BUS_METRICS pipeline_cycles=%0d inst_req_accept=%0d inst_data_complete=%0d load_req_accept=%0d load_data_complete=%0d store_req_accept=%0d store_data_complete=%0d duplicate_store_count=%0d protocol_assertions_failed=%0d stale_fetch_drops=%0d ar_handshakes=%0d r_handshakes=%0d aw_handshakes=%0d w_handshakes=%0d b_handshakes=%0d backpressure_ar_cycles=%0d backpressure_r_cycles=%0d backpressure_aw_cycles=%0d backpressure_w_cycles=%0d backpressure_b_cycles=%0d",
                 bus_pipeline_cycles,
                 bus_inst_req_accept, bus_inst_data_complete,
                 bus_load_req_accept, bus_load_data_complete,
                 bus_store_req_accept, bus_store_data_complete,
                 bus_duplicate_store_count, bus_protocol_faults,
                 bus_stale_fetch_drops, bus_ar_handshakes, bus_r_handshakes,
                 bus_aw_handshakes, bus_w_handshakes, bus_b_handshakes,
                 bus_backpressure_ar_cycles, bus_backpressure_r_cycles,
                 bus_backpressure_aw_cycles, bus_backpressure_w_cycles,
                 bus_backpressure_b_cycles);
        if (global_err || trace_read_failed || (trace_trailing_valid != 0))
        begin
            $display("Fail!!!Total %d errors!",err_count);
            if (trace_read_failed) begin
                $display("COURSE_SOC_FAIL=trace_read_or_format_error");
            end
            else if (trace_trailing_valid != 0) begin
                $display("COURSE_SOC_FAIL=unconsumed_valid_trace_records count=%0d",
                         trace_trailing_valid);
            end
            else begin
                $display("COURSE_SOC_FAIL=course_test_error count=%0d",err_count);
            end
        end
        else
        begin
            $display("----PASS!!!");
            $display("TRACE_EXHAUSTION_PASS records=%0d valid=%0d",
                     trace_records_read, trace_valid_records_read);
            $display("COURSE_SOC_PASS");
        end
        $fclose(trace_ref);
	    $finish;
	end
end
endmodule
