`timescale 1ns/1ps
`include "mycpu.h"

module tb_lab11_axi3_bus;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg aresetn = 1'b0;
    reg core_reset_sync = 1'b1;
    always @(posedge clk) core_reset_sync <= ~aresetn;

    reg trap_redirect = 1'b0;
    reg eret_redirect = 1'b0;
    reg [31:0] trap_vector = 32'b0;
    reg [31:0] eret_target = 32'b0;
    wire [`BR_BUS_WD-1:0] br_bus = {`BR_BUS_WD{1'b0}};
    wire fs_to_ds_valid;
    wire [`FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus;
    wire [31:0] fs_pc = fs_to_ds_bus[31:0];
    wire [31:0] fs_inst = fs_to_ds_bus[63:32];

    wire inst_req;
    wire inst_wr;
    wire [1:0] inst_size;
    wire [3:0] inst_wstrb;
    wire [31:0] inst_addr;
    wire [31:0] inst_wdata;
    wire inst_addr_ok;
    wire inst_data_ok;
    wire [31:0] inst_rdata;

    reg data_req = 1'b0;
    reg data_wr = 1'b0;
    reg [1:0] data_size = 2'd2;
    reg [3:0] data_wstrb = 4'b0;
    reg [31:0] data_addr = 32'b0;
    reg [31:0] data_wdata = 32'b0;
    wire data_addr_ok;
    wire data_data_ok;
    wire [31:0] data_rdata;
    wire axi_fault;

    reg arready = 1'b0;
    wire [3:0] arid;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire [1:0] arlock;
    wire [3:0] arcache;
    wire [2:0] arprot;
    wire arvalid;
    reg [3:0] rid = 4'b0;
    reg [31:0] rdata = 32'b0;
    reg [1:0] rresp = 2'b0;
    reg rlast = 1'b0;
    reg rvalid = 1'b0;
    wire rready;

    reg awready = 1'b0;
    wire [3:0] awid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire [1:0] awlock;
    wire [3:0] awcache;
    wire [2:0] awprot;
    wire awvalid;
    reg wready = 1'b0;
    wire [3:0] wid;
    wire [31:0] wdata;
    wire [3:0] wstrb;
    wire wlast;
    wire wvalid;
    reg [3:0] bid = 4'b0;
    reg [1:0] bresp = 2'b0;
    reg bvalid = 1'b0;
    wire bready;

    integer ar_hs_count = 0;
    integer r_hs_count = 0;
    integer aw_hs_count = 0;
    integer w_hs_count = 0;
    integer b_hs_count = 0;
    integer data_addr_count = 0;
    integer data_done_count = 0;
    integer cycles;

    always @(posedge clk) begin
        if (!aresetn) begin
            ar_hs_count <= 0;
            r_hs_count <= 0;
            aw_hs_count <= 0;
            w_hs_count <= 0;
            b_hs_count <= 0;
            data_addr_count <= 0;
            data_done_count <= 0;
        end else begin
            if (arvalid && arready) ar_hs_count <= ar_hs_count + 1;
            if (rvalid && rready) r_hs_count <= r_hs_count + 1;
            if (awvalid && awready) aw_hs_count <= aw_hs_count + 1;
            if (wvalid && wready) w_hs_count <= w_hs_count + 1;
            if (bvalid && bready) b_hs_count <= b_hs_count + 1;
            if (data_addr_ok) data_addr_count <= data_addr_count + 1;
            if (data_data_ok) data_done_count <= data_done_count + 1;
        end
    end

    if_stage u_if_stage(
        .clk(clk),
        .reset(core_reset_sync),
        .ds_allowin(1'b1),
        .br_bus(br_bus),
        .trap_redirect(trap_redirect),
        .eret_redirect(eret_redirect),
        .trap_vector(trap_vector),
        .eret_target(eret_target),
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_to_ds_bus(fs_to_ds_bus),
        .inst_sram_req(inst_req),
        .inst_sram_wr(inst_wr),
        .inst_sram_size(inst_size),
        .inst_sram_wstrb(inst_wstrb),
        .inst_sram_addr(inst_addr),
        .inst_sram_wdata(inst_wdata),
        .inst_sram_addr_ok(inst_addr_ok),
        .inst_sram_data_ok(inst_data_ok),
        .inst_sram_rdata(inst_rdata)
    );

    axi3_cpu_bus dut(
        .aclk(clk), .aresetn(aresetn),
        .inst_req(inst_req), .inst_size(inst_size), .inst_addr(inst_addr),
        .inst_addr_ok(inst_addr_ok), .inst_data_ok(inst_data_ok), .inst_rdata(inst_rdata),
        .data_req(data_req), .data_wr(data_wr), .data_size(data_size),
        .data_wstrb(data_wstrb), .data_addr(data_addr), .data_wdata(data_wdata),
        .data_addr_ok(data_addr_ok), .data_data_ok(data_data_ok), .data_rdata(data_rdata),
        .axi_fault(axi_fault),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize),
        .arburst(arburst), .arlock(arlock), .arcache(arcache), .arprot(arprot),
        .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast),
        .rvalid(rvalid), .rready(rready),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
        .awburst(awburst), .awlock(awlock), .awcache(awcache), .awprot(awprot),
        .awvalid(awvalid), .awready(awready),
        .wid(wid), .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
        .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready)
    );

    task automatic require(input logic condition, input string message);
        begin
            if (condition !== 1'b1)
                $fatal(1, "LAB11_AXI3_ASSERT %s", message);
        end
    endtask

    task automatic reset_case;
        begin
            @(negedge clk);
            aresetn = 1'b0;
            trap_redirect = 1'b0;
            eret_redirect = 1'b0;
            trap_vector = 32'b0;
            eret_target = 32'b0;
            data_req = 1'b0;
            data_wr = 1'b0;
            data_size = 2'd2;
            data_wstrb = 4'b0;
            data_addr = 32'b0;
            data_wdata = 32'b0;
            arready = 1'b0;
            rid = 4'b0;
            rdata = 32'b0;
            rresp = 2'b0;
            rlast = 1'b0;
            rvalid = 1'b0;
            awready = 1'b0;
            wready = 1'b0;
            bid = 4'b0;
            bresp = 2'b0;
            bvalid = 1'b0;
            repeat (3) @(posedge clk);
            #1;
        end
    endtask

    task automatic release_case;
        begin
            @(negedge clk);
            aresetn = 1'b1;
            repeat (3) @(posedge clk);
            #1;
        end
    endtask

    task automatic wait_ar;
        begin
            cycles = 0;
            while (arvalid !== 1'b1 && cycles < 30) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
            end
            require(arvalid, "ARVALID watchdog");
        end
    endtask

    task automatic accept_ar;
        begin
            @(negedge clk);
            arready = 1'b1;
            #1;
            require(arvalid, "ARVALID before handshake");
            @(posedge clk);
            #1;
            arready = 1'b0;
        end
    endtask

    task automatic return_read(input [3:0] response_id,
                               input [1:0] response_code,
                               input logic last,
                               input [31:0] response_data,
                               input logic expected_data_ok,
                               input logic expect_if);
        begin
            @(negedge clk);
            rid = response_id;
            rresp = response_code;
            rlast = last;
            rdata = response_data;
            rvalid = 1'b1;
            #1;
            require(rready, "RREADY while one response is owned");
            if (expect_if)
                require(inst_data_ok == expected_data_ok, "IF response delivery");
            else
                require(data_data_ok == expected_data_ok, "Load response delivery");
            @(posedge clk);
            #1;
            rvalid = 1'b0;
            rlast = 1'b0;
            require(!inst_data_ok && !data_data_ok, "read response consumed once");
        end
    endtask

    task automatic run_good_write(input logic aw_first,
                                  input [31:0] address,
                                  input [1:0] size,
                                  input [3:0] strobe,
                                  input [31:0] payload,
                                  input [31:0] expected_address);
        integer aw_before;
        integer w_before;
        integer b_before;
        integer done_before;
        reg [31:0] held_awaddr;
        reg [31:0] held_wdata;
        reg [3:0] held_wstrb;
        begin
            aw_before = aw_hs_count;
            w_before = w_hs_count;
            b_before = b_hs_count;
            done_before = data_done_count;
            @(negedge clk);
            data_req = 1'b1;
            data_wr = 1'b1;
            data_size = size;
            data_wstrb = strobe;
            data_addr = address;
            data_wdata = payload;
            @(posedge clk);
            #1;
            held_awaddr = awaddr;
            held_wdata = wdata;
            held_wstrb = wstrb;
            require(awvalid && wvalid, "AW and W start independently");
            require(awid == 4'h1 && wid == awid, "AXI3 AWID/WID match");
            require(awprot == 3'b010, "data write protection attributes");
            require(awlen == 0 && awsize == {1'b0, size}, "single-beat AWSIZE/AWLEN");
            require(awaddr == expected_address, "AWADDR alignment and stability");
            require(wdata == payload && wstrb == strobe && wlast, "W payload and WLAST");

            repeat (2) begin
                @(posedge clk);
                #1;
                require(awvalid && wvalid, "AW/W remain asserted while stalled");
                require(awaddr == held_awaddr, "AWADDR stable while AWREADY=0");
                require(wdata == held_wdata && wstrb == held_wstrb,
                        "WDATA/WSTRB stable while WREADY=0");
            end

            if (aw_first) begin
                @(negedge clk);
                awready = 1'b1;
                #1;
                require(awvalid && !wready, "AW-first setup");
                @(posedge clk);
                #1;
                awready = 1'b0;
                require(!awvalid && wvalid, "AW accepted while W remains pending");
                require(!data_addr_ok, "Store waits for both address and data handshakes");
                repeat (2) begin
                    @(posedge clk);
                    #1;
                    require(wvalid && wdata == held_wdata && wstrb == held_wstrb,
                            "W held after independent AW handshake");
                end
                @(negedge clk);
                wready = 1'b1;
                #1;
                require(data_addr_ok, "Store request accepted on second channel handshake");
                @(posedge clk);
                #1;
                wready = 1'b0;
            end else begin
                @(negedge clk);
                wready = 1'b1;
                #1;
                require(wvalid && !awready, "W-first setup");
                @(posedge clk);
                #1;
                wready = 1'b0;
                require(wvalid == 1'b0 && awvalid, "W accepted while AW remains pending");
                require(!data_addr_ok, "Store waits for both data and address handshakes");
                repeat (2) begin
                    @(posedge clk);
                    #1;
                    require(awvalid && awaddr == held_awaddr,
                            "AW held after independent W handshake");
                end
                @(negedge clk);
                awready = 1'b1;
                #1;
                require(data_addr_ok, "Store request accepted on second channel handshake");
                @(posedge clk);
                #1;
                awready = 1'b0;
            end

            data_req = 1'b0;
            require(!data_addr_ok, "store address acceptance is one pulse");
            repeat (3) begin
                @(posedge clk);
                #1;
                require(bready && !data_data_ok, "Store waits for B response");
            end
            @(negedge clk);
            bid = 4'h1;
            bresp = 2'b00;
            bvalid = 1'b1;
            #1;
            require(data_data_ok, "successful B response completes Store");
            @(posedge clk);
            #1;
            bvalid = 1'b0;
            require(!bready && !data_data_ok, "B response consumed once");
            require(aw_hs_count == aw_before + 1, "one AW handshake per Store");
            require(w_hs_count == w_before + 1, "one W handshake per Store");
            require(b_hs_count == b_before + 1, "one B handshake per Store");
            require(data_done_count == done_before + 1, "one Store completion pulse");
            require(!axi_fault, "successful Store does not set AXI fault");
        end
    endtask

    task automatic run_bad_read(input logic wrong_id,
                                input logic bad_resp,
                                input logic missing_last);
        reg [3:0] bad_rid;
        reg [1:0] bad_rresp;
        reg bad_rlast;
        begin
            reset_case();
            @(negedge clk);
            data_req = 1'b1;
            data_wr = 1'b0;
            data_size = 2'd2;
            data_addr = 32'h0000_6000;
            release_case();
            wait_ar();
            require(arid == 4'h1 && araddr == 32'h0000_6000, "bad-response read owner");
            accept_ar();
            data_req = 1'b0;
            bad_rid = wrong_id ? 4'h0 : 4'h1;
            bad_rresp = bad_resp ? 2'b10 : 2'b00;
            bad_rlast = !missing_last;
            return_read(bad_rid, bad_rresp, bad_rlast, 32'h1234_5678, 1'b0, 1'b0);
            require(axi_fault, "malformed R response latches AXI fault");
            require(data_done_count == 0, "malformed R response cannot complete Load");
        end
    endtask

    task automatic run_bad_write(input logic wrong_id, input logic bad_resp);
        begin
            reset_case();
            @(negedge clk);
            data_req = 1'b1;
            data_wr = 1'b1;
            data_size = 2'd2;
            data_addr = 32'h0000_7000;
            data_wstrb = 4'b1111;
            data_wdata = 32'h55aa_55aa;
            release_case();
            cycles = 0;
            while (!(awvalid && wvalid) && cycles < 30) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
            end
            require(awvalid && wvalid, "write request watchdog");
            @(negedge clk);
            awready = 1'b1;
            wready = 1'b1;
            #1;
            require(data_addr_ok, "write address/data handshakes accepted");
            @(posedge clk);
            #1;
            awready = 1'b0;
            wready = 1'b0;
            data_req = 1'b0;
            require(bready, "BREADY after AW and W handshakes");
            @(negedge clk);
            bid = wrong_id ? 4'h0 : 4'h1;
            bresp = bad_resp ? 2'b10 : 2'b00;
            bvalid = 1'b1;
            #1;
            require(!data_data_ok, "malformed B response cannot complete Store");
            @(posedge clk);
            #1;
            bvalid = 1'b0;
            require(axi_fault, "malformed B response latches AXI fault");
            require(data_done_count == 0, "malformed B response has no completion pulse");
        end
    endtask

    initial begin
        reset_case();
        // Queue a Load before reset release while IF also starts requesting.
        // Load priority must be deterministic; IF remains pending and is served
        // after the Load response.
        @(negedge clk);
        data_req = 1'b1;
        data_wr = 1'b0;
        data_size = 2'd0;
        data_addr = 32'h0000_1001;
        release_case();
        wait_ar();
        require(arid == 4'h1, "Load wins shared AR arbitration");
        require(araddr == 32'h0000_1001 && arsize == 3'b000,
                "narrow byte read keeps address and byte size");
        require(arlen == 0 && arburst == 2'b01 && arlock == 0 && arcache == 0,
                "single-beat AXI3 read attributes");
        require(arprot == 3'b010, "data read protection attributes");
        begin : ar_stall_check
            reg [31:0] held_addr;
            reg [3:0] held_id;
            reg [2:0] held_size;
            held_addr = araddr;
            held_id = arid;
            held_size = arsize;
            repeat (3) begin
                @(posedge clk);
                #1;
                require(arvalid && araddr == held_addr && arid == held_id &&
                        arsize == held_size && arlen == 0,
                        "AR payload stable while ARREADY=0");
            end
        end
        require(data_addr_count == 1 && !data_addr_ok,
                "selected Load is accepted when the adapter locks its request");
        @(negedge clk);
        arready = 1'b1;
        #1;
        require(!data_addr_ok && !inst_addr_ok,
                "AXI AR handshake does not repeat the CPU address acceptance pulse");
        @(posedge clk);
        #1;
        arready = 1'b0;
        data_req = 1'b0;
        require(!data_addr_ok, "CPU address acceptance notification is a pulse");
        require(ar_hs_count == 1, "one shared read address handshake");

        // The responder must keep RVALID/data while RREADY is withheld. The
        // actual adapter can always store a response, so this force exercises
        // the AXI slave-side backpressure contract directly.
        @(negedge clk);
        rid = 4'h1;
        rresp = 2'b00;
        rlast = 1'b1;
        rdata = 32'h0000_ab00;
        rvalid = 1'b1;
        force dut.rready = 1'b0;
        repeat (2) begin
            @(posedge clk);
            #1;
            require(rvalid && !data_data_ok, "R response held under R backpressure");
        end
        release dut.rready;
        #1;
        require(rready && data_data_ok && data_rdata == 32'h0000_ab00,
                "Load response accepted once after RREADY resumes");
        @(posedge clk);
        #1;
        rvalid = 1'b0;
        rlast = 1'b0;
        require(r_hs_count == 1 && data_done_count == 1, "one Load response consumed");

        // The pending IF fetch now owns AR. Redirect while ARREADY is stalled:
        // the adapter has already accepted the request, so IF must mark its
        // response stale and wait for it to drain before fetching the target.
        wait_ar();
        require(arid == 4'h0 && araddr == 32'hbfc0_0000 && arsize == 3'b010,
                "IF fetch follows Load on shared AR");
        require(arprot == 3'b110, "instruction read protection attributes");
        @(negedge clk);
        trap_redirect = 1'b1;
        trap_vector = 32'h8000_0180;
        @(posedge clk);
        #1;
        trap_redirect = 1'b0;
        accept_ar();
        return_read(4'h0, 2'b00, 1'b1, 32'hdead_beef, 1'b1, 1'b1);
        require(!fs_to_ds_valid, "stale IF response is discarded after redirect");
        wait_ar();
        require(arid == 4'h0 && araddr == 32'h8000_0180,
                "redirect target is requested after stale response drain");
        accept_ar();
        return_read(4'h0, 2'b00, 1'b1, 32'h2408_0001, 1'b1, 1'b1);
        require(fs_to_ds_valid && fs_pc == 32'h8000_0180 && fs_inst == 32'h2408_0001,
                "redirected instruction is the only instruction delivered");
        $display("LAB11_AXI3_IF_REDIRECT_STALLED_AR_PASS");

        // Repeat with the old AR already accepted to cover the other redirect
        // timing point. The outstanding R must still be consumed and dropped.
        @(posedge clk);
        #1;
        wait_ar();
        require(arid == 4'h0 && araddr == 32'h8000_0184,
                "sequential fetch follows redirected instruction");
        accept_ar();
        @(negedge clk);
        eret_redirect = 1'b1;
        eret_target = 32'hbfc0_0400;
        @(posedge clk);
        #1;
        eret_redirect = 1'b0;
        return_read(4'h0, 2'b00, 1'b1, 32'hbad0_bad0, 1'b1, 1'b1);
        require(!fs_to_ds_valid, "accepted stale IF response is discarded");
        wait_ar();
        require(arid == 4'h0 && araddr == 32'hbfc0_0400,
                "ERET target follows stale response drain");
        accept_ar();
        return_read(4'h0, 2'b00, 1'b1, 32'h2409_0001, 1'b1, 1'b1);
        require(fs_to_ds_valid && fs_pc == 32'hbfc0_0400 && fs_inst == 32'h2409_0001,
                "ERET target instruction is delivered with its own PC");
        $display("LAB11_AXI3_IF_REDIRECT_ACCEPTED_AR_PASS");
        require(!axi_fault, "valid IF and Load reads preserve clean status");

        // Independently delayed AW/W channels, stable payloads, B latency, one
        // completion; also check narrow lane settings and SWL-style alignment.
        run_good_write(1'b1, 32'h0000_4002, 2'd0, 4'b0100,
                       32'h00aa_0000, 32'h0000_4002);
        run_good_write(1'b0, 32'h0000_5001, 2'd2, 4'b0011,
                       32'h0000_1234, 32'h0000_5000);
        require(aw_hs_count == 2 && w_hs_count == 2 && b_hs_count == 2,
                "two stores each use AW/W/B exactly once");
        $display("LAB11_AXI3_HANDSHAKE_PASS reads=2 stores=2 AW_first=1 W_first=1");

        run_bad_read(1'b1, 1'b0, 1'b0);
        $display("LAB11_AXI3_RID_CHECK_PASS");
        run_bad_read(1'b0, 1'b1, 1'b0);
        $display("LAB11_AXI3_RRESP_CHECK_PASS");
        run_bad_read(1'b0, 1'b0, 1'b1);
        $display("LAB11_AXI3_RLAST_CHECK_PASS");
        run_bad_write(1'b1, 1'b0);
        $display("LAB11_AXI3_BID_CHECK_PASS");
        run_bad_write(1'b0, 1'b1);
        $display("LAB11_AXI3_BRESP_CHECK_PASS");
        $display("LAB11_AXI3_BUS_PASS");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "LAB11_AXI3_WATCHDOG timeout");
    end
endmodule
