`timescale 1ns/1ps

module tb_lab14_tlb;
    reg resetn = 1'b0;
    reg clk = 1'b0;

    wire [15:0] led;
    wire [1:0] led_rg0;
    wire [1:0] led_rg1;
    wire [7:0] num_csn;
    wire [6:0] num_a_g;
    wire [3:0] btn_key_col;
    reg [7:0] switch = 8'hff;
    reg [3:0] btn_key_row = 4'd0;
    reg [1:0] btn_step = 2'd3;

    reg [31:0] last_num_data = 32'b0;
    integer score_points = 0;
    integer cycles = 0;

    always #5 clk = ~clk;

    initial begin
        #2000;
        resetn = 1'b1;
    end

    soc_axi_lite_top #(.SIMULATION(1'b1)) soc_lite (
        .resetn(resetn),
        .clk(clk),
        .led(led),
        .led_rg0(led_rg0),
        .led_rg1(led_rg1),
        .num_csn(num_csn),
        .num_a_g(num_a_g),
        .switch(switch),
        .btn_key_col(btn_key_col),
        .btn_key_row(btn_key_row),
        .btn_step(btn_step)
    );

    always @(posedge clk) begin
        #1;
        if (!resetn) begin
            last_num_data = 32'b0;
            score_points = 0;
        end else if (soc_lite.u_confreg.num_data !== last_num_data) begin
            if (soc_lite.u_confreg.num_data[7:0] !== last_num_data[7:0] + 8'd1)
                $fatal(1, "LAB14_SCORE_LOW_BYTE expected=%02x observed=%02x",
                       last_num_data[7:0] + 8'd1, soc_lite.u_confreg.num_data[7:0]);
            if (soc_lite.u_confreg.num_data[31:24] !== last_num_data[31:24] + 8'd1)
                $fatal(1, "LAB14_TEST_SEQUENCE expected=%02x observed=%02x",
                       last_num_data[31:24] + 8'd1, soc_lite.u_confreg.num_data[31:24]);
            if (soc_lite.u_confreg.num_data[23:8] !== 16'b0)
                $fatal(1, "LAB14_SCORE_RESERVED_BITS=%04x",
                       soc_lite.u_confreg.num_data[23:8]);
            last_num_data = soc_lite.u_confreg.num_data;
            score_points = score_points + 1;
            $display("LAB14_TESTPOINT=%0d SCORE=%0d", score_points,
                     soc_lite.u_confreg.num_data[7:0]);
        end
    end

    initial begin
        repeat (2_000_000) begin
            @(posedge clk);
            #2;
            cycles = cycles + 1;
            if ((led_rg0 === 2'b01) && (led_rg1 === 2'b01)) begin
                if (soc_lite.u_confreg.num_data !== 32'h0600_0006 || score_points != 6)
                    $fatal(1, "LAB14_SCORE_MISMATCH num_data=%08x points=%0d",
                           soc_lite.u_confreg.num_data, score_points);
                $display("LAB14_N1_N6_PASS score=6/6 cycles=%0d", cycles);
                $finish;
            end
            if ((led_rg0 === 2'b10) && (led_rg1 === 2'b10))
                $fatal(1, "LAB14_SOFTWARE_REPORTED_FAILURE num_data=%08x",
                       soc_lite.u_confreg.num_data);
        end
        $fatal(1, "LAB14_WATCHDOG_TIMEOUT pc=%08x num_data=%08x",
               soc_lite.debug_wb_pc, soc_lite.u_confreg.num_data);
    end
endmodule
