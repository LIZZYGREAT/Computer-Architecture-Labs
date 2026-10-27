`include "mycpu.h"

module hilo_unit(
    input         clk,
    input         resetn,
    input         start,
    input         is_mult,
    input         is_multu,
    input         is_div,
    input         is_divu,
    input         consume_done,
    input  [31:0] operand_a,
    input  [31:0] operand_b,
    input         write_hi_en,
    input         write_lo_en,
    input  [31:0] write_data,
    output        busy,
    output        done,
    output [31:0] hi_value,
    output [31:0] lo_value
);

localparam HILO_IDLE      = 3'd0;
localparam HILO_MULT_WAIT = 3'd1;
localparam HILO_DIV_SEND  = 3'd2;
localparam HILO_DIV_WAIT  = 3'd3;
localparam HILO_DONE      = 3'd4;

reg [2:0] state;
reg [31:0] hi_reg;
reg [31:0] lo_reg;
reg        div_signed;
reg        dividend_negative;
reg        divisor_negative;
reg [31:0] div_dividend_data;
reg [31:0] div_divisor_data;

wire        mult_request;
wire        div_request;
wire        accept_mult;
wire        accept_div;
wire [32:0] mult_operand_a;
wire [32:0] mult_operand_b;
wire [65:0] mult_product;
wire [31:0] dividend_magnitude;
wire [31:0] divisor_magnitude;
wire        divisor_ready;
wire        dividend_ready;
wire        div_input_valid;
wire        div_pair_accept;
wire        div_result_valid;
wire [63:0] div_result;
wire [31:0] quotient_magnitude;
wire [31:0] remainder_magnitude;
wire [31:0] quotient_result;
wire [31:0] remainder_result;

assign mult_request = is_mult | is_multu;
assign div_request  = is_div | is_divu;
assign accept_mult  = resetn && (state == HILO_IDLE) && start && mult_request;
assign accept_div   = resetn && (state == HILO_IDLE) && start && div_request;
assign div_input_valid = resetn && (state == HILO_DIV_SEND);
assign div_pair_accept = div_input_valid && dividend_ready && divisor_ready;
assign busy         = (state == HILO_MULT_WAIT) || (state == HILO_DIV_SEND) ||
                      (state == HILO_DIV_WAIT);
assign done         = (state == HILO_DONE);
assign hi_value     = hi_reg;
assign lo_value     = lo_reg;

// Extend unsigned operands with zero and signed operands with their sign bit.
// The 33x33 signed product's low 64 bits implement both MIPS MULT variants.
assign mult_operand_a = {(is_mult && operand_a[31]), operand_a};
assign mult_operand_b = {(is_mult && operand_b[31]), operand_b};

// Divider Generator is configured as a 32-bit unsigned quotient/remainder
// engine. Signed DIV uses magnitudes, then restores MIPS signs after completion.
assign dividend_magnitude = (is_div && operand_a[31]) ? (~operand_a + 32'd1) : operand_a;
assign divisor_magnitude  = (is_div && operand_b[31]) ? (~operand_b + 32'd1) : operand_b;
assign quotient_magnitude = div_result[63:32];
assign remainder_magnitude = div_result[31:0];
assign quotient_result = (div_signed && (dividend_negative ^ divisor_negative)) ?
                         (~quotient_magnitude + 32'd1) : quotient_magnitude;
assign remainder_result = (div_signed && dividend_negative) ?
                           (~remainder_magnitude + 32'd1) : remainder_magnitude;

lab6_mult33 u_mult(
    .CLK (clk),
    .A   (mult_operand_a),
    .B   (mult_operand_b),
    .CE  (accept_mult),
    .P   (mult_product)
);

lab6_div32 u_div(
    .aclk                    (clk),
    .aresetn                 (resetn),
    .s_axis_divisor_tvalid   (div_input_valid),
    .s_axis_divisor_tready   (divisor_ready),
    .s_axis_divisor_tdata    (div_divisor_data),
    .s_axis_dividend_tvalid  (div_input_valid),
    .s_axis_dividend_tready  (dividend_ready),
    .s_axis_dividend_tdata   (div_dividend_data),
    .m_axis_dout_tvalid      (div_result_valid),
    .m_axis_dout_tdata       (div_result)
);

always @(posedge clk) begin
    if (!resetn) begin
        state              <= HILO_IDLE;
        hi_reg              <= 32'b0;
        lo_reg              <= 32'b0;
        div_signed          <= 1'b0;
        dividend_negative   <= 1'b0;
        divisor_negative    <= 1'b0;
        div_dividend_data   <= 32'b0;
        div_divisor_data    <= 32'b0;
    end
    else begin
        if (write_hi_en) begin
            hi_reg <= write_data;
        end
        if (write_lo_en) begin
            lo_reg <= write_data;
        end

        case (state)
            HILO_IDLE: begin
                if (accept_mult) begin
                    state <= HILO_MULT_WAIT;
                end
                else if (accept_div) begin
                    div_signed        <= is_div;
                    dividend_negative <= operand_a[31];
                    divisor_negative  <= operand_b[31];
                    div_dividend_data <= dividend_magnitude;
                    div_divisor_data  <= divisor_magnitude;
                    state             <= HILO_DIV_SEND;
                end
            end
            HILO_DIV_SEND: begin
                // Divider Generator NonBlocking mode consumes its two input
                // channels as one paired operation. Keep both TVALIDs and
                // their registered payloads stable until the pair is ready.
                // TVALID is deliberately independent of TREADY.
                if (div_pair_accept) begin
                    state <= HILO_DIV_WAIT;
                end
            end
            HILO_MULT_WAIT: begin
                hi_reg <= mult_product[63:32];
                lo_reg <= mult_product[31:0];
                state  <= HILO_DONE;
            end
            HILO_DIV_WAIT: begin
                if (div_result_valid) begin
                    hi_reg <= remainder_result;
                    lo_reg <= quotient_result;
                    state  <= HILO_DONE;
                end
            end
            HILO_DONE: begin
                if (consume_done) begin
                    state <= HILO_IDLE;
                end
            end
            default: begin
                state <= HILO_IDLE;
            end
        endcase
    end
end

endmodule
