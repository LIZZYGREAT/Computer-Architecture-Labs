module tb_cache_directed;
    timeunit 1ns;
    timeprecision 1ps;

    reg clk;
    reg resetn;
    reg valid;
    reg op;
    reg [7:0] index;
    reg [19:0] tag;
    reg [3:0] offset;
    reg [3:0] wstrb;
    reg [31:0] wdata;

    wire addr_ok;
    wire data_ok;
    wire [31:0] rdata;
    wire rd_req;
    wire [2:0] rd_type;
    wire [31:0] rd_addr;
    reg rd_rdy;
    reg ret_valid;
    reg ret_last;
    reg [31:0] ret_data;
    wire wr_req;
    wire [2:0] wr_type;
    wire [31:0] wr_addr;
    wire [3:0] wr_wstrb;
    wire [127:0] wr_data;
    reg wr_rdy;

    reg hold_rd;
    reg hold_ret;
    reg hold_wr;

    reg [127:0] backing [0:4][0:15];
    integer reads_by_tag [0:4][0:15];
    integer writes_by_tag [0:4][0:15];
    reg rd_pending;
    reg [31:0] rd_line_addr;
    integer rd_slot;
    reg [19:0] rd_tag;
    integer rd_delay;
    reg [1:0] rd_beat;
    integer rd_handshakes;
    integer wr_handshakes;
    integer accepted_count;
    integer completed_count;
    integer cancelled_count;

    reg rd_stall_prev;
    reg [31:0] rd_addr_stalled;
    reg [2:0] rd_type_stalled;
    reg wr_stall_prev;
    reg [31:0] wr_addr_stalled;
    reg [2:0] wr_type_stalled;
    reg [3:0] wr_wstrb_stalled;
    reg [127:0] wr_data_stalled;
    reg data_ok_prev;

    integer i;
    integer j;
    integer k;
    integer timeout;
    integer baseline_reads;
    integer baseline_writes;
    reg [31:0] expected_word;
    reg [31:0] dirty_word;
    reg [127:0] dirty_line;

    cache dut (
        .clk_g(clk),
        .resetn(resetn),
        .valid(valid),
        .op(op),
        .index(index),
        .tag(tag),
        .offset(offset),
        .wstrb(wstrb),
        .wdata(wdata),
        .addr_ok(addr_ok),
        .data_ok(data_ok),
        .rdata(rdata),
        .rd_req(rd_req),
        .rd_type(rd_type),
        .rd_addr(rd_addr),
        .rd_rdy(rd_rdy),
        .ret_valid(ret_valid),
        .ret_last(ret_last),
        .ret_data(ret_data),
        .wr_req(wr_req),
        .wr_type(wr_type),
        .wr_addr(wr_addr),
        .wr_wstrb(wr_wstrb),
        .wr_data(wr_data),
        .wr_rdy(wr_rdy)
    );

    always #5 clk = ~clk;

    function integer index_slot(input [7:0] idx);
        begin
            case (idx)
                8'h2a: index_slot = 0;
                8'h2b: index_slot = 1;
                8'h2c: index_slot = 2;
                8'h2d: index_slot = 3;
                8'h2e: index_slot = 4;
                default: index_slot = -1;
            endcase
        end
    endfunction

    function [31:0] line_word(input [127:0] line_value, input [1:0] word_index);
        begin
            case (word_index)
                2'd0: line_word = line_value[31:0];
                2'd1: line_word = line_value[63:32];
                2'd2: line_word = line_value[95:64];
                default: line_word = line_value[127:96];
            endcase
        end
    endfunction

    function [31:0] merge_word(
        input [31:0] old_word,
        input [31:0] new_word,
        input [3:0] byte_enable
    );
        begin
            merge_word = old_word;
            if (byte_enable[0]) merge_word[7:0] = new_word[7:0];
            if (byte_enable[1]) merge_word[15:8] = new_word[15:8];
            if (byte_enable[2]) merge_word[23:16] = new_word[23:16];
            if (byte_enable[3]) merge_word[31:24] = new_word[31:24];
        end
    endfunction

    always @* begin
        rd_rdy = !rd_pending && !hold_rd;
        ret_valid = rd_pending && (rd_delay == 0) && !hold_ret;
        ret_last = ret_valid && (rd_beat == 2'd3);
        case (rd_beat)
            2'd0: ret_data = backing[rd_slot][rd_tag[3:0]][31:0];
            2'd1: ret_data = backing[rd_slot][rd_tag[3:0]][63:32];
            2'd2: ret_data = backing[rd_slot][rd_tag[3:0]][95:64];
            default: ret_data = backing[rd_slot][rd_tag[3:0]][127:96];
        endcase
        wr_rdy = !hold_wr;
    end

    always @(posedge clk) begin
        if (!resetn) begin
            rd_pending <= 1'b0;
            rd_line_addr <= 32'b0;
            rd_slot <= 0;
            rd_tag <= 20'b0;
            rd_delay <= 0;
            rd_beat <= 2'b0;
            rd_stall_prev <= 1'b0;
            wr_stall_prev <= 1'b0;
            data_ok_prev <= 1'b0;
        end else begin
            if (rd_stall_prev &&
                (!rd_req || rd_addr !== rd_addr_stalled || rd_type !== rd_type_stalled))
                $fatal(1, "DIRECTED_FAIL=read_payload_changed_under_backpressure");
            if (wr_stall_prev &&
                (!wr_req || wr_addr !== wr_addr_stalled || wr_type !== wr_type_stalled ||
                 wr_wstrb !== wr_wstrb_stalled || wr_data !== wr_data_stalled))
                $fatal(1, "DIRECTED_FAIL=write_payload_changed_under_backpressure");
            if (data_ok_prev && data_ok)
                $fatal(1, "DIRECTED_FAIL=data_ok_was_not_a_pulse");

            rd_stall_prev <= rd_req && !rd_rdy;
            if (rd_req && !rd_rdy) begin
                rd_addr_stalled <= rd_addr;
                rd_type_stalled <= rd_type;
            end
            wr_stall_prev <= wr_req && !wr_rdy;
            if (wr_req && !wr_rdy) begin
                wr_addr_stalled <= wr_addr;
                wr_type_stalled <= wr_type;
                wr_wstrb_stalled <= wr_wstrb;
                wr_data_stalled <= wr_data;
            end
            data_ok_prev <= data_ok;

            if (rd_req && rd_rdy) begin
                rd_line_addr <= rd_addr;
                rd_slot <= index_slot(rd_addr[11:4]);
                rd_tag <= rd_addr[31:12];
                rd_delay <= 2;
                rd_beat <= 2'b0;
                rd_pending <= 1'b1;
                rd_handshakes <= rd_handshakes + 1;
                if (index_slot(rd_addr[11:4]) < 0 || rd_addr[31:28] != 0)
                    $fatal(1, "DIRECTED_FAIL=unsupported_read_address %08x", rd_addr);
                reads_by_tag[index_slot(rd_addr[11:4])][rd_addr[15:12]] <=
                    reads_by_tag[index_slot(rd_addr[11:4])][rd_addr[15:12]] + 1;
            end else if (rd_pending) begin
                if (rd_delay > 0)
                    rd_delay <= rd_delay - 1;
                else if (ret_valid) begin
                    if (ret_last) begin
                        rd_pending <= 1'b0;
                        rd_beat <= 2'b0;
                    end else begin
                        rd_beat <= rd_beat + 2'd1;
                    end
                end
            end

            if (wr_req && wr_rdy) begin
                if (wr_wstrb !== 4'b1111 || wr_addr[3:0] !== 4'b0000)
                    $fatal(1, "DIRECTED_FAIL=bad_writeback_format");
                if (index_slot(wr_addr[11:4]) < 0 || wr_addr[31:28] != 0)
                    $fatal(1, "DIRECTED_FAIL=unsupported_write_address %08x", wr_addr);
                backing[index_slot(wr_addr[11:4])][wr_addr[15:12]] <= wr_data;
                writes_by_tag[index_slot(wr_addr[11:4])][wr_addr[15:12]] <=
                    writes_by_tag[index_slot(wr_addr[11:4])][wr_addr[15:12]] + 1;
                wr_handshakes <= wr_handshakes + 1;
            end
        end
    end

    task wait_cache_ready;
        integer n;
        begin
            n = 0;
            while (!addr_ok && n < 400) begin
                @(negedge clk);
                n = n + 1;
            end
            if (!addr_ok) $fatal(1, "DIRECTED_FAIL=cache_reset_clear_timeout");
        end
    endtask

    task issue_request(
        input reg write_op,
        input [7:0] req_index,
        input [19:0] req_tag,
        input [3:0] req_offset,
        input [3:0] req_wstrb,
        input [31:0] req_wdata
    );
        begin
            wait_cache_ready();
            @(negedge clk);
            valid = 1'b1;
            op = write_op;
            index = req_index;
            tag = req_tag;
            offset = req_offset;
            wstrb = req_wstrb;
            wdata = req_wdata;
            @(posedge clk);
            if (!addr_ok) $fatal(1, "DIRECTED_FAIL=request_was_not_accepted");
            accepted_count = accepted_count + 1;
            @(negedge clk);
            valid = 1'b0;
        end
    endtask

    task await_result(input [31:0] expected);
        integer n;
        reg observed;
        begin
            n = 0;
            observed = 1'b0;
            while (!observed && n < 10000) begin
                @(negedge clk);
                if (data_ok) begin
                    if (rdata !== expected)
                        $fatal(1, "DIRECTED_FAIL=result expected=%08x actual=%08x", expected, rdata);
                    completed_count = completed_count + 1;
                    observed = 1'b1;
                end
                n = n + 1;
            end
            if (!observed) $fatal(1, "DIRECTED_FAIL=data_ok_timeout");
        end
    endtask

    task transact(
        input reg write_op,
        input [7:0] req_index,
        input [19:0] req_tag,
        input [3:0] req_offset,
        input [3:0] req_wstrb,
        input [31:0] req_wdata,
        input [31:0] expected
    );
        begin
            issue_request(write_op, req_index, req_tag, req_offset, req_wstrb, req_wdata);
            await_result(expected);
        end
    endtask

    initial begin
        clk = 1'b0;
        resetn = 1'b0;
        valid = 1'b0;
        op = 1'b0;
        index = 8'b0;
        tag = 20'b0;
        offset = 4'b0;
        wstrb = 4'b0;
        wdata = 32'b0;
        hold_rd = 1'b0;
        hold_ret = 1'b0;
        hold_wr = 1'b0;
        rd_pending = 1'b0;
        rd_line_addr = 32'b0;
        rd_slot = 0;
        rd_tag = 20'b0;
        rd_delay = 0;
        rd_beat = 2'b0;
        rd_handshakes = 0;
        wr_handshakes = 0;
        accepted_count = 0;
        completed_count = 0;
        cancelled_count = 0;
        rd_stall_prev = 1'b0;
        wr_stall_prev = 1'b0;
        data_ok_prev = 1'b0;
        for (i = 0; i < 5; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                reads_by_tag[i][j] = 0;
                writes_by_tag[i][j] = 0;
                for (k = 0; k < 4; k = k + 1)
                    backing[i][j][k*32 +: 32] = 32'ha0000000 | (i << 20) | (j << 8) | k;
            end
        end
        backing[0][1] = {32'h11110003, 32'h11110002, 32'h11110001, 32'h11110000};
        backing[1][1] = {32'h22220003, 32'h22220002, 32'h22220001, 32'h11110000};
        backing[2][6] = {32'ha1b2c3d4, 32'h33330002, 32'h33330001, 32'h33330000};

        repeat (5) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;
        wait_cache_ready();

        expected_word = line_word(backing[0][1], 2'd0);
        transact(1'b0, 8'h2a, 20'd1, 4'h0, 4'b0000, 32'b0, expected_word);
        transact(1'b0, 8'h2a, 20'd1, 4'h4, 4'b0000, 32'b0,
                 line_word(backing[0][1], 2'd1));
        $display("WAVE_CASE=READ_MISS_THEN_HIT time=%0t", $time);
        dirty_word = merge_word(line_word(backing[0][1], 2'd0), 32'haabbccdd, 4'b0101);
        transact(1'b1, 8'h2a, 20'd1, 4'h0, 4'b0101, 32'haabbccdd, dirty_word);
        transact(1'b0, 8'h2a, 20'd1, 4'h0, 4'b0000, 32'b0, dirty_word);

        baseline_writes = wr_handshakes;
        for (i = 10; i <= 13; i = i + 1)
            transact(1'b0, 8'h2d, i, 4'h0, 4'b0000, 32'b0,
                     line_word(backing[3][i], 2'd0));
        transact(1'b0, 8'h2d, 20'd14, 4'h0, 4'b0000, 32'b0,
                 line_word(backing[3][14], 2'd0));
        if (wr_handshakes != baseline_writes)
            $fatal(1, "DIRECTED_FAIL=clean_victim_was_written_back");
        baseline_reads = rd_handshakes;
        transact(1'b0, 8'h2d, 20'd10, 4'h0, 4'b0000, 32'b0,
                 line_word(backing[3][10], 2'd0));
        if (rd_handshakes != baseline_reads + 1 || reads_by_tag[3][10] != 2)
            $fatal(1, "DIRECTED_FAIL=clean_round_robin_replacement");
        $display("WAVE_CASE=CLEAN_FIFTH_TAG_REPLACEMENT time=%0t", $time);

        expected_word = merge_word(line_word(backing[2][6], 2'd3), 32'haa112233, 4'b0111);
        transact(1'b1, 8'h2c, 20'd6, 4'hc, 4'b0111, 32'haa112233, expected_word);
        transact(1'b0, 8'h2c, 20'd6, 4'hc, 4'b0000, 32'b0, expected_word);
        if (expected_word !== 32'ha1112233)
            $fatal(1, "DIRECTED_FAIL=byte_mask_reference_error");

        transact(1'b0, 8'h2b, 20'd1, 4'h0, 4'b0000, 32'b0,
                 line_word(backing[1][1], 2'd0));
        dirty_word = merge_word(line_word(backing[1][1], 2'd0), 32'haabbccdd, 4'b0101);
        transact(1'b1, 8'h2b, 20'd1, 4'h0, 4'b0101, 32'haabbccdd, dirty_word);
        dirty_line = backing[1][1];
        dirty_line[31:0] = dirty_word;
        for (i = 2; i <= 4; i = i + 1)
            transact(1'b0, 8'h2b, i, 4'h0, 4'b0000, 32'b0,
                     line_word(backing[1][i], 2'd0));

        baseline_writes = wr_handshakes;
        hold_wr = 1'b1;
        hold_rd = 1'b1;
        expected_word = line_word(backing[1][5], 2'd0);
        issue_request(1'b0, 8'h2b, 20'd5, 4'h0, 4'b0000, 32'b0);
        timeout = 0;
        while (!wr_req && timeout < 1000) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (!wr_req || wr_rdy || wr_addr !== {20'd1, 8'h2b, 4'b0000} ||
            wr_data !== dirty_line)
            $fatal(1, "DIRECTED_FAIL=dirty_victim_payload");
        repeat (3) begin
            @(posedge clk);
            if (!wr_req || wr_rdy || wr_addr !== {20'd1, 8'h2b, 4'b0000} ||
                wr_data !== dirty_line)
                $fatal(1, "DIRECTED_FAIL=writeback_stall_payload");
        end
        $display("WAVE_CASE=DIRTY_WRITEBACK_STALLED time=%0t", $time);
        @(negedge clk);
        hold_wr = 1'b0;
        timeout = 0;
        while (!rd_req && timeout < 1000) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (!rd_req || rd_rdy || rd_addr !== {20'd5, 8'h2b, 4'b0000})
            $fatal(1, "DIRECTED_FAIL=refill_request_after_writeback");
        repeat (3) begin
            @(posedge clk);
            if (!rd_req || rd_rdy || rd_addr !== {20'd5, 8'h2b, 4'b0000})
                $fatal(1, "DIRECTED_FAIL=read_request_stall_payload");
        end
        @(negedge clk);
        hold_rd = 1'b0;
        await_result(expected_word);
        $display("WAVE_CASE=DIRTY_WRITEBACK_REFILL_COMPLETE time=%0t", $time);
        if (wr_handshakes != baseline_writes + 1 || writes_by_tag[1][1] != 1 ||
            backing[1][1][31:0] !== dirty_word)
            $fatal(1, "DIRECTED_FAIL=dirty_victim_writeback");
        transact(1'b0, 8'h2b, 20'd1, 4'h0, 4'b0000, 32'b0, dirty_word);
        if (reads_by_tag[1][1] != 2)
            $fatal(1, "DIRECTED_FAIL=written_back_data_was_not_refilled");

        hold_ret = 1'b1;
        issue_request(1'b0, 8'h2e, 20'd7, 4'h0, 4'b0000, 32'b0);
        timeout = 0;
        while (!rd_pending && timeout < 1000) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (!rd_pending || data_ok)
            $fatal(1, "DIRECTED_FAIL=reset_test_did_not_reach_refill");
        $display("WAVE_CASE=RESET_CANCELLATION_PENDING_REFILL time=%0t", $time);
        repeat (2) @(negedge clk);
        resetn = 1'b0;
        cancelled_count = cancelled_count + 1;
        repeat (4) @(posedge clk);
        @(negedge clk);
        if (data_ok) $fatal(1, "DIRECTED_FAIL=cancelled_request_completed");
        resetn = 1'b1;
        hold_ret = 1'b0;
        wait_cache_ready();
        transact(1'b0, 8'h2e, 20'd7, 4'h0, 4'b0000, 32'b0,
                 line_word(backing[4][7], 2'd0));

        if (accepted_count != completed_count + cancelled_count)
            $fatal(1, "DIRECTED_FAIL=request_accounting accepted=%0d complete=%0d cancelled=%0d",
                   accepted_count, completed_count, cancelled_count);
        if (wr_handshakes != 1 || rd_handshakes < 13)
            $fatal(1, "DIRECTED_FAIL=memory_accounting reads=%0d writes=%0d",
                   rd_handshakes, wr_handshakes);

        $display("DIRECTED_CHECKS=20");
        $display("DIRECTED_REQUESTS accepted=%0d completed=%0d cancelled=%0d",
                 accepted_count, completed_count, cancelled_count);
        $display("DIRECTED_MEMORY read_handshakes=%0d writeback_handshakes=%0d",
                 rd_handshakes, wr_handshakes);
        $display("DIRECTED_PASS");
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "DIRECTED_FAIL=watchdog_timeout");
    end
endmodule
