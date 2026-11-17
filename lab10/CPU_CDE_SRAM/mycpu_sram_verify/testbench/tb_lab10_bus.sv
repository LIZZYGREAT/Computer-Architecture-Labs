module tb_lab10_bus;
localparam FS_TO_DS_BUS_WD = 103;
localparam ES_TO_MS_BUS_WD = 195;
localparam MS_TO_WS_BUS_WD = 70;
localparam MEM_OP_LB = 1;
localparam MEM_OP_LBU = 2;
localparam MEM_OP_LH = 3;
localparam MEM_OP_LHU = 4;
localparam MEM_OP_LWL = 5;
localparam MEM_OP_LWR = 6;
localparam MEM_OP_SW = 7;
localparam MEM_OP_SB = 8;
localparam MEM_OP_SH = 9;
localparam MEM_OP_SWL = 10;
localparam MEM_OP_SWR = 11;
localparam [4:0] EXC_ADEL = 5'd4;
localparam [4:0] EXC_ADES = 5'd5;
localparam [31:0] BOOT_PC = 32'hbfc0_0000;
localparam [31:0] BRANCH_TARGET = 32'hbfc0_0100;
localparam [31:0] TRAP_TARGET = 32'hbfc0_0200;

reg clk = 1'b0;
always #5 clk = ~clk;

reg reset;
reg ds_allowin;
reg [33:0] br_bus;
reg trap_redirect;
reg eret_redirect;
reg [31:0] trap_vector;
reg [31:0] eret_target;
wire fs_to_ds_valid;
wire [FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus;
wire inst_sram_req;
wire inst_sram_wr;
wire [1:0] inst_sram_size;
wire [3:0] inst_sram_wstrb;
wire [31:0] inst_sram_addr;
wire [31:0] inst_sram_wdata;
reg inst_sram_addr_ok;
reg inst_sram_data_ok;
reg [31:0] inst_sram_rdata;

wire [31:0] fs_pc = fs_to_ds_bus[31:0];
wire [31:0] fs_inst = fs_to_ds_bus[63:32];
wire fs_delay_slot = fs_to_ds_bus[64];
wire fs_exception_valid = fs_to_ds_bus[65];
wire [4:0] fs_exception_code = fs_to_ds_bus[70:66];
wire [31:0] fs_bad_vaddr = fs_to_ds_bus[102:71];

if_stage u_if(
    .clk(clk), .reset(reset), .ds_allowin(ds_allowin), .br_bus(br_bus),
    .trap_redirect(trap_redirect), .eret_redirect(eret_redirect),
    .trap_vector(trap_vector), .eret_target(eret_target),
    .fs_to_ds_valid(fs_to_ds_valid), .fs_to_ds_bus(fs_to_ds_bus),
    .inst_sram_req(inst_sram_req), .inst_sram_wr(inst_sram_wr),
    .inst_sram_size(inst_sram_size), .inst_sram_wstrb(inst_sram_wstrb),
    .inst_sram_addr(inst_sram_addr), .inst_sram_wdata(inst_sram_wdata),
    .inst_sram_addr_ok(inst_sram_addr_ok), .inst_sram_data_ok(inst_sram_data_ok),
    .inst_sram_rdata(inst_sram_rdata)
);

reg ws_allowin;
reg es_to_ms_valid;
reg [ES_TO_MS_BUS_WD-1:0] es_to_ms_bus;
wire ms_allowin;
reg [31:0] cp0_rdata;
wire cp0_we;
wire [7:0] cp0_waddr;
wire [31:0] cp0_wdata;
wire [7:0] cp0_raddr;
wire cp0_serial_busy;
wire trap_commit;
wire [4:0] trap_code;
wire [31:0] trap_pc;
wire trap_bd;
wire [31:0] trap_bad_vaddr;
wire eret_commit;
wire data_sram_req;
wire data_sram_wr;
wire [1:0] data_sram_size;
wire [3:0] data_sram_wstrb;
wire [31:0] data_sram_addr;
wire [31:0] data_sram_wdata;
reg data_sram_addr_ok;
reg data_sram_data_ok;
reg [31:0] data_sram_rdata;
wire ms_to_ws_valid;
wire [MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus;
wire [38:0] ms_producer_bus;

mem_stage u_mem(
    .clk(clk), .reset(reset), .ws_allowin(ws_allowin), .ms_allowin(ms_allowin),
    .es_to_ms_valid(es_to_ms_valid), .es_to_ms_bus(es_to_ms_bus),
    .cp0_rdata(cp0_rdata), .cp0_we(cp0_we), .cp0_waddr(cp0_waddr),
    .cp0_wdata(cp0_wdata), .cp0_raddr(cp0_raddr),
    .cp0_serial_busy(cp0_serial_busy), .trap_commit(trap_commit),
    .trap_code(trap_code), .trap_pc(trap_pc), .trap_bd(trap_bd),
    .trap_bad_vaddr(trap_bad_vaddr), .eret_commit(eret_commit),
    .data_sram_req(data_sram_req), .data_sram_wr(data_sram_wr),
    .data_sram_size(data_sram_size), .data_sram_wstrb(data_sram_wstrb),
    .data_sram_addr(data_sram_addr), .data_sram_wdata(data_sram_wdata),
    .data_sram_addr_ok(data_sram_addr_ok), .data_sram_data_ok(data_sram_data_ok),
    .data_sram_rdata(data_sram_rdata), .ms_to_ws_valid(ms_to_ws_valid),
    .ms_to_ws_bus(ms_to_ws_bus), .ms_producer_bus(ms_producer_bus)
);

integer if_accept_count;
integer if_response_count;
integer data_accept_count;
integer data_response_count;
integer store_response_count;
integer load_writeback_count;
reg if_outstanding;
reg data_outstanding;

always @(posedge clk) begin
    if (reset) begin
        if_accept_count <= 0;
        if_response_count <= 0;
        data_accept_count <= 0;
        data_response_count <= 0;
        store_response_count <= 0;
        load_writeback_count <= 0;
        if_outstanding <= 1'b0;
        data_outstanding <= 1'b0;
    end else begin
        if (inst_sram_req && inst_sram_addr_ok) begin
            if_accept_count <= if_accept_count + 1;
            if (!inst_sram_data_ok)
                if_outstanding <= 1'b1;
        end
        if (inst_sram_data_ok && (if_outstanding || (inst_sram_req && inst_sram_addr_ok))) begin
            if_response_count <= if_response_count + 1;
            if_outstanding <= 1'b0;
        end
        if (data_sram_req && data_sram_addr_ok) begin
            data_accept_count <= data_accept_count + 1;
            if (!data_sram_data_ok)
                data_outstanding <= 1'b1;
        end
        if (data_sram_data_ok && (data_outstanding || (data_sram_req && data_sram_addr_ok))) begin
            data_response_count <= data_response_count + 1;
            data_outstanding <= 1'b0;
            if (data_sram_wr)
                store_response_count <= store_response_count + 1;
        end
        if (ms_to_ws_valid && ms_to_ws_bus[69])
            load_writeback_count <= load_writeback_count + 1;
    end
end

task automatic check(input condition, input [8*120-1:0] message);
    begin
        if (!condition)
            $fatal(1, "LAB10_BUS_FAIL: %0s at %0t", message, $time);
    end
endtask

task automatic tick;
    begin
        @(posedge clk);
        #1;
    end
endtask

task automatic inject_mem(input [11:0] mem_op,
                          input gr_we,
                          input [4:0] dest,
                          input [31:0] addr,
                          input [31:0] rt_value,
                          input [31:0] pc,
                          input exception_valid,
                          input [4:0] exception_code);
    begin
        while (!ms_allowin)
            tick();
        @(negedge clk);
        es_to_ms_bus = {2'b00, 8'b0, 32'b0,
                        exception_valid, exception_code, addr,
                        1'b0, mem_op, gr_we, dest, addr, rt_value, pc};
        es_to_ms_valid = 1'b1;
        tick();
        @(negedge clk);
        es_to_ms_valid = 1'b0;
    end
endtask

task automatic run_load(input [11:0] mem_op,
                        input [31:0] addr,
                        input [31:0] rt_value,
                        input [31:0] read_value,
                        input [31:0] expected_value,
                        input [1:0] expected_size);
    begin
        inject_mem(mem_op, 1'b1, 5'd8, addr, rt_value, 32'hbfc0_0300, 1'b0, 5'b0);
        check(data_sram_req, "load did not request data");
        check(data_sram_wr == 1'b0, "load asserted write");
        check(data_sram_size == expected_size, "load size mismatch");
        check(data_sram_addr == addr, "load address changed");
        check(ms_producer_bus[38] && !ms_producer_bus[37],
              "load was not marked hazardous before its response");
        @(negedge clk);
        data_sram_addr_ok = 1'b1;
        data_sram_data_ok = 1'b0;
        tick();
        @(negedge clk);
        data_sram_addr_ok = 1'b0;
        check(!data_sram_req, "load request repeated after address acceptance");
        check(ms_producer_bus[38] && !ms_producer_bus[37],
              "load forwarded before data response");
        data_sram_rdata = read_value;
        data_sram_data_ok = 1'b1;
        tick();
        @(negedge clk);
        data_sram_data_ok = 1'b0;
        check(!data_sram_req, "load request repeated after response");
        check(ms_producer_bus[37], "load result was not forwardable after response");
        check(ms_to_ws_valid, "completed load did not advance");
        check(ms_to_ws_bus[63:32] === expected_value,
              "load extension/merge result mismatch");
        tick();
    end
endtask

task automatic run_store(input [11:0] mem_op,
                         input [31:0] addr,
                         input [31:0] rt_value,
                         input [1:0] expected_size,
                         input [3:0] expected_strobe,
                         input [31:0] expected_data);
    begin
        inject_mem(mem_op, 1'b0, 5'd0, addr, rt_value, 32'hbfc0_0400, 1'b0, 5'b0);
        check(data_sram_req, "store did not request data");
        check(data_sram_wr, "store did not assert write");
        check(data_sram_size == expected_size, "store size mismatch");
        check(data_sram_wstrb == expected_strobe, "store byte strobe mismatch");
        check(data_sram_wdata == expected_data, "store data lane mismatch");
        check(data_sram_addr == addr, "store address mismatch");
        @(negedge clk);
        data_sram_addr_ok = 1'b1;
        data_sram_data_ok = 1'b1;
        tick();
        @(negedge clk);
        data_sram_addr_ok = 1'b0;
        data_sram_data_ok = 1'b0;
        check(!data_sram_req, "completed store request repeated");
        tick();
    end
endtask

task automatic run_delayed_store(input [11:0] mem_op,
                                 input [31:0] addr,
                                 input [31:0] rt_value,
                                 input [1:0] expected_size,
                                 input [3:0] expected_strobe,
                                 input [31:0] expected_data);
    integer wait_cycles;
    begin
        inject_mem(mem_op, 1'b0, 5'd0, addr, rt_value, 32'hbfc0_0400, 1'b0, 5'b0);
        check(data_sram_req && data_sram_wr, "delayed Store did not request a write");
        check(data_sram_size == expected_size && data_sram_wstrb == expected_strobe &&
              data_sram_wdata == expected_data && data_sram_addr == addr,
              "delayed Store payload mismatch");
        for (wait_cycles = 0; wait_cycles < 3; wait_cycles = wait_cycles + 1) begin
            tick();
            check(data_sram_req && data_sram_addr == addr &&
                  data_sram_wstrb == expected_strobe && data_sram_wdata == expected_data,
                  "delayed Store request/payload changed before acceptance");
        end
        @(negedge clk);
        data_sram_addr_ok = 1'b1;
        data_sram_data_ok = 1'b0;
        tick();
        @(negedge clk);
        data_sram_addr_ok = 1'b0;
        check(!data_sram_req, "Store request repeated after address acceptance");
        repeat (3) begin
            tick();
            check(!data_sram_req, "Store request repeated while waiting for completion");
        end
        @(negedge clk);
        data_sram_data_ok = 1'b1;
        tick();
        @(negedge clk);
        data_sram_data_ok = 1'b0;
        check(ms_allowin && !data_sram_req, "Store did not complete after data_ok");
        tick();
    end
endtask

initial begin
    reset = 1'b1;
    ds_allowin = 1'b1;
    br_bus = 34'b0;
    trap_redirect = 1'b0;
    eret_redirect = 1'b0;
    trap_vector = 32'b0;
    eret_target = 32'b0;
    inst_sram_addr_ok = 1'b0;
    inst_sram_data_ok = 1'b0;
    inst_sram_rdata = 32'b0;
    ws_allowin = 1'b1;
    es_to_ms_valid = 1'b0;
    es_to_ms_bus = {ES_TO_MS_BUS_WD{1'b0}};
    cp0_rdata = 32'b0;
    data_sram_addr_ok = 1'b0;
    data_sram_data_ok = 1'b0;
    data_sram_rdata = 32'b0;

    repeat (2) tick();
    @(negedge clk);
    reset = 1'b0;
    #1;

    // IF-01/02/03/04: address stall, one acceptance, delayed return, and hold.
    check(inst_sram_req && inst_sram_addr == BOOT_PC, "initial IF request is wrong");
    check(!inst_sram_wr && inst_sram_size == 2'd2 && inst_sram_wstrb == 4'b0,
          "instruction request is not read-only word access");
    tick();
    check(inst_sram_req && inst_sram_addr == BOOT_PC,
          "IF request/address changed while addr_ok was low");
    @(negedge clk);
    inst_sram_addr_ok = 1'b1;
    tick();
    @(negedge clk);
    inst_sram_addr_ok = 1'b0;
    check(!inst_sram_req && !fs_to_ds_valid, "IF did not wait for response");
    repeat (2) begin
        tick();
        check(!inst_sram_req && !fs_to_ds_valid, "IF duplicated request while waiting");
    end
    @(negedge clk);
    inst_sram_rdata = 32'h3c08_0001;
    inst_sram_data_ok = 1'b1;
    ds_allowin = 1'b0;
    tick();
    @(negedge clk);
    inst_sram_data_ok = 1'b0;
    check(fs_to_ds_valid && fs_pc == BOOT_PC && fs_inst == 32'h3c08_0001,
          "IF response was not buffered with the requested PC");
    repeat (2) begin
        tick();
        check(fs_to_ds_valid && fs_pc == BOOT_PC && fs_inst == 32'h3c08_0001,
              "IF result was lost or changed while ID was blocked");
    end
    @(negedge clk);
    ds_allowin = 1'b1;
    tick();
    check(!fs_to_ds_valid && inst_sram_req && inst_sram_addr == BOOT_PC + 4,
          "IF did not advance exactly once after result consumption");

    // IF-05: branch delay slot remains live and the following address redirects.
    @(negedge clk);
    br_bus = {1'b1, BRANCH_TARGET, 1'b1};
    tick();
    check(inst_sram_req && inst_sram_addr == BOOT_PC + 4,
          "branch event replaced the delay-slot request");
    @(negedge clk);
    br_bus = 34'b0;
    inst_sram_addr_ok = 1'b1;
    tick();
    @(negedge clk);
    inst_sram_addr_ok = 1'b0;
    ds_allowin = 1'b0;
    inst_sram_rdata = 32'h2508_0001;
    inst_sram_data_ok = 1'b1;
    tick();
    @(negedge clk);
    inst_sram_data_ok = 1'b0;
    check(fs_to_ds_valid && fs_pc == BOOT_PC + 4 && fs_delay_slot,
          "branch delay-slot instruction was not tagged");
    repeat (2) begin
        tick();
        check(fs_to_ds_valid && fs_delay_slot,
              "blocked delay-slot result was not held");
    end
    @(negedge clk);
    ds_allowin = 1'b1;
    tick();
    check(inst_sram_req && inst_sram_addr == BRANCH_TARGET,
          "taken branch did not fetch its target after the delay slot");

    // IF-06: accepted old-path response is drained after a trap redirect.
    @(negedge clk);
    inst_sram_addr_ok = 1'b1;
    tick();
    @(negedge clk);
    inst_sram_addr_ok = 1'b0;
    trap_redirect = 1'b1;
    trap_vector = TRAP_TARGET;
    tick();
    @(negedge clk);
    trap_redirect = 1'b0;
    check(!inst_sram_req && !fs_to_ds_valid,
          "trap redirect did not wait for the old accepted response");
    inst_sram_rdata = 32'hdead_beef;
    inst_sram_data_ok = 1'b1;
    tick();
    @(negedge clk);
    inst_sram_data_ok = 1'b0;
    check(!fs_to_ds_valid && inst_sram_req && inst_sram_addr == TRAP_TARGET,
          "stale instruction response escaped or trap target was lost");

    // IF-07: same-cycle address/response and misaligned redirect handling.
    @(negedge clk);
    inst_sram_addr_ok = 1'b1;
    inst_sram_data_ok = 1'b1;
    inst_sram_rdata = 32'h2408_0002;
    tick();
    @(negedge clk);
    inst_sram_addr_ok = 1'b0;
    inst_sram_data_ok = 1'b0;
    check(fs_to_ds_valid && fs_pc == TRAP_TARGET && fs_inst == 32'h2408_0002,
          "same-cycle IF request/response was not captured");
    tick();
    @(negedge clk);
    eret_redirect = 1'b1;
    eret_target = TRAP_TARGET + 2;
    tick();
    @(negedge clk);
    eret_redirect = 1'b0;
    check(!inst_sram_req, "misaligned IF address reached the RAM");
    tick();
    check(fs_to_ds_valid && fs_exception_valid &&
          fs_exception_code == EXC_ADEL && fs_bad_vaddr == TRAP_TARGET + 2,
          "misaligned IF address did not raise AdEL with the bad address");
    check(if_accept_count == 4 && if_response_count == 4,
          "IF accepted/completed request counts did not match");
    $display("LAB10_IF_PASS accepts=%0d responses=%0d", if_accept_count, if_response_count);

    // Reset both stage instances before the MEM scenarios.
    @(negedge clk);
    reset = 1'b1;
    repeat (2) tick();
    @(negedge clk);
    reset = 1'b0;
    ds_allowin = 1'b0;
    inst_sram_addr_ok = 1'b0;

    // MEM-02: Store waits for address/data and is issued exactly once.
    run_delayed_store(12'b1 << MEM_OP_SW, 32'h0000_0100, 32'h1122_3344,
                      2'd2, 4'b1111, 32'h1122_3344);

    // MEM-01/03: loads stall forwarding until data arrives and preserve MIPS lanes.
    run_load(12'b1 << MEM_OP_LB,  32'h0000_0103, 32'b0,
             32'h80ff_7f01, 32'hffff_ff80, 2'd0);
    run_load(12'b1 << MEM_OP_LBU, 32'h0000_0102, 32'b0,
             32'h80ff_7f01, 32'h0000_00ff, 2'd0);
    run_load(12'b1 << MEM_OP_LH,  32'h0000_0100, 32'b0,
             32'h80ff_7f01, 32'h0000_7f01, 2'd1);
    run_load(12'b1 << MEM_OP_LHU, 32'h0000_0102, 32'b0,
             32'h80ff_7f01, 32'h0000_80ff, 2'd1);
    run_load(12'b1 << MEM_OP_LWL, 32'h0000_0100, 32'haabb_ccdd,
             32'h1122_3344, 32'h44bb_ccdd, 2'd2);
    run_load(12'b1 << MEM_OP_LWR, 32'h0000_0103, 32'haabb_ccdd,
             32'h1122_3344, 32'haabb_cc11, 2'd2);

    // MEM-04: byte/half and unaligned word-store lane mapping.
    run_store(12'b1 << MEM_OP_SB,  32'h0000_0201, 32'haabb_ccdd,
              2'd0, 4'b0010, 32'hbbcc_dd00);
    run_store(12'b1 << MEM_OP_SH,  32'h0000_0202, 32'h1234_5678,
              2'd1, 4'b1100, 32'h5678_0000);
    run_store(12'b1 << MEM_OP_SWL, 32'h0000_0202, 32'h1234_5678,
              2'd2, 4'b0111, 32'h0012_3456);
    run_store(12'b1 << MEM_OP_SWR, 32'h0000_0203, 32'h1234_5678,
              2'd2, 4'b1000, 32'h7800_0000);

    // EXC-01: a faulting Store never creates an externally visible request.
    inject_mem(12'b1 << MEM_OP_SW, 1'b0, 5'd0, 32'h0000_0301,
               32'hfeed_face, 32'hbfc0_0500, 1'b1, EXC_ADES);
    check(!data_sram_req && trap_commit && trap_code == EXC_ADES,
          "faulting Store issued externally or lost its exception");

    check(data_accept_count == 11 && data_response_count == 11,
          "data accepted/completed counts did not match");
    check(store_response_count == 5, "Store completion count mismatch");
    check(load_writeback_count == 6, "Load writeback count mismatch");
    $display("LAB10_MEM_PASS accepts=%0d responses=%0d stores=%0d loads=%0d",
             data_accept_count, data_response_count,
             store_response_count, load_writeback_count);
    $display("LAB10_BUS_PASS");
    $finish;
end

initial begin
    #100000;
    $fatal(1, "LAB10_BUS_TIMEOUT");
end

endmodule
