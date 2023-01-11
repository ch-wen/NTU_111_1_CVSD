module alu #(
    parameter INT_W  = 3,
    parameter FRAC_W = 5,
    parameter INST_W = 3,
    parameter DATA_W = INT_W + FRAC_W // 8bits, 7:0
)(
    input                     i_clk,
    input                     i_rst_n,
    input                     i_valid,
    input signed [DATA_W-1:0] i_data_a, //8Q5
    input signed [DATA_W-1:0] i_data_b, //8Q5
    input        [INST_W-1:0] i_inst,
    output                    o_valid,
    output       [DATA_W-1:0] o_data
);
    
// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
    reg [DATA_W:0] o_data_w, o_data_r;
    reg            o_valid_w, o_valid_r;
// ---- Add your own wires and registers here if needed ---- //
    // addition, subtraction
    reg [DATA_W:0] out_add;
    // multiplication
    reg [(DATA_W*2)-1:0] out_mul_16q10;
    reg [(DATA_W*2)-FRAC_W:0] out_mul_11q5; // add one bit 
    reg out_mul_carry;
    // sigmoid
    reg [DATA_W-1:0] out_dvide;
    // right circular shift
    reg [DATA_W-1:0] amount;
// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
    assign o_valid = o_valid_r;
    assign o_data = o_data_r;
// ---- Add your own wire data assignments here if needed ---- //
// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your combinational block design here ---- //
    always@(*) begin
        if(i_valid == 1) begin
            o_valid_w = 1;
            case(i_inst)
                3'b000: begin // addition
                    out_add = {i_data_a[7], i_data_a} + {i_data_b[7], i_data_b};
                    o_data_w = (out_add[8:7] == 2'b00 || out_add[8:7] == 2'b11) ? out_add : {out_add[8], {7{!out_add[8]}}};
                end
                3'b001: begin // subtraction
                    out_add = {i_data_a[7], i_data_a} - {i_data_b[7], i_data_b};
                    o_data_w = (out_add[8:7] == 2'b00 || out_add[8:7] == 2'b11) ? out_add : {out_add[8], {7{!out_add[8]}}};
                end
                3'b010: begin // multiplication
                    out_mul_16q10 = i_data_a * i_data_b;
                    // 16q10->11q5
                    out_mul_carry = out_mul_16q10 [15] ? (out_mul_16q10 [4] & (|out_mul_16q10 [3:0])) : out_mul_16q10 [4];
                    out_mul_11q5 = {out_mul_16q10 [15], out_mul_16q10 [15:5]} + out_mul_carry;
                    // 11q5 -> 8q5
                    o_data_w = (out_mul_11q5[11:8]==4'b0000 || out_mul_11q5[11:8]==4'b1111) ? out_mul_11q5 : {out_mul_11q5[11], {7{!out_mul_11q5[11]}}};
                end
                3'b011: begin // NAND
                    o_data_w = ~(i_data_a & i_data_b);
                end
                3'b100: begin // XOR
                    o_data_w = ~(i_data_a ^ i_data_b);
                end
                3'b101: begin // sigmoid
                    if(i_data_a[7] && !i_data_a[6]==1'b1) //<-2
                        o_data_w = 8'b00000000;
                    else if(!i_data_a[7] && i_data_a[6]==1'b1) //>2
                        o_data_w = 8'b00100000;
                    else begin
                        out_dvide = (i_data_a >>> 2); // /4+0.5
                        out_add = {out_dvide[7], out_dvide} + {1'b0, 8'b00010000};
                        o_data_w = out_add;
                    end
                end
                3'b110: begin // right circular shift
                    amount = i_data_b % 8'd8; // /8
                    o_data_w = (i_data_a >> amount) | (i_data_a << (8'b00001000-amount));
                end
                3'b111: begin // find min
                    o_data_w = (i_data_a<=i_data_b) ? i_data_a : i_data_b;
                end
                default: o_data_w = 0;
            endcase
        end
        else begin
            o_data_w = 0;
            o_valid_w = 0;
        end
    end
// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //
    always@(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            o_data_r  <= 0;
            o_valid_r <= 0; //low
        end else begin
            o_data_r <= o_data_w;
            o_valid_r <= o_valid_w; // high
        end
    end
endmodule
