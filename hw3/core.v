module core (                       //Don't modify interface
	input         i_clk,
	input         i_rst_n,
	input         i_op_valid,
	input  [3:0]  i_op_mode,
    output        o_op_ready,
	input         i_in_valid,
	input  [7:0]  i_in_data,
	output        o_in_ready,
	output        o_out_valid,
	output [12:0] o_out_data
);
// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
// outputs
reg	[12:0]	o_out_data_w, o_out_data_r;
reg			o_op_ready_w, o_op_ready_r, 
			o_in_ready_w, o_in_ready_r, 
			o_out_valid_w, o_out_valid_r;
// vars
//reg [7:0]	map [0:2047];
reg [12:0] map_0_7 [0:63];
reg [12:0] map_0_15 [0:63];
reg [12:0] map_0_31 [0:63];


reg	[2:0]	current_state, next_state;

reg [5:0] current_position, next_position; // 0~63, 6bits
reg column_overflow, row_overflow;

// display
reg [5:0] current_depth, next_depth; // 8, 16, 32
reg [10:0]current_out_idx, next_out_idx;
reg [9:0] current_out_count, next_out_count; // 0~128

// convolution
reg [16:0] current_acc0, next_acc0,
		   current_acc1, next_acc1,
           current_acc2, next_acc2,
           current_acc3, next_acc3;
reg [16:0] feature;
wire [3:0]  right_overflow, left_overflow, up_overflow, down_overflow;

reg [12:0] conv_reg;

// SRAM
wire [7:0] data;
wire [7:0] sram_o_Q; //output from sram
reg [11:0] sram_i_A;  //address 0~2047: 
wire sram_i_CEN, sram_i_WEN;

// paras
parameter STA_IDLE =       3'b000; // idle
parameter STA_FT =         3'b001; // o_op_ready =1
parameter STA_EX =         3'b010; // run opcode
parameter STA_LOAD_MAP =   3'b011; // load map 2045 cycles
parameter STA_CAL_CONV =   3'b100; // get output region
parameter STA_OUT_CONV =   3'b101; // get convolution results
parameter STA_OUT_DATA =   3'b110; // output (assign o_out_data)
parameter STA_END =        3'b111; // end

parameter OP_LOAD_MAP =    4'b0000;
parameter OP_SHIFT_RIGHT = 4'b0001;
parameter OP_SHIFT_LEFT =  4'b0010;
parameter OP_SHIFT_UP =    4'b0011;
parameter OP_SHIFT_DOWN =  4'b0100;
parameter OP_SCALE_DOWN =  4'b0101;
parameter OP_SCALE_UP =    4'b0110;
parameter OP_CONV_SHOW =   4'b0111;
parameter OP_OUT_SHOW =    4'b1000;

// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
assign o_op_ready	= o_op_ready_r;
assign o_in_ready	= o_in_ready_r;
assign o_out_valid	= o_out_valid_r;
assign o_out_data   = (current_state==STA_OUT_DATA) ? sram_o_Q : o_out_data_r;

assign right_overflow = current_position[2:0] + 1 + 1;
assign left_overflow  = current_position[2:0] - 1;
assign up_overflow    = current_position[5:3] - 1;
assign down_overflow  = current_position[5:3] + 1 + 1;

assign data = i_in_data;
assign sram_i_WEN = (current_state != STA_LOAD_MAP);

sram_4096x8	sram_4096x8(
	.Q(sram_o_Q),
	.CLK(i_clk),
	.CEN(1'b0),
	.WEN(sram_i_WEN),
	.A(sram_i_A),
	.D(data)
);

// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
always@(*)begin
	// init
	o_out_valid_w	= 0;
	o_in_ready_w	= 1;
	o_op_ready_w	= 0;
	
	next_out_count  = current_out_count; 
	next_state		= 0;
	next_out_idx    = current_out_idx;
	next_position   = current_position;
	next_depth      = current_depth;
	next_acc0        = current_acc0;
	next_acc1        = current_acc1;
	next_acc2        = current_acc2;
	next_acc3        = current_acc3;

	conv_reg = 0;
	o_out_data_w = 0;
	sram_i_A = 0;
	case(current_state)
		STA_IDLE: begin
			o_out_valid_w	= 0;
			o_in_ready_w	= 1;

			next_state		= STA_FT;
		end
		STA_FT: begin
			o_out_valid_w	= 0;
			o_op_ready_w	= 1;
			o_in_ready_w 	= 1;

			row_overflow    = 0;
            column_overflow = 0;

			next_state		= STA_EX;
		end
		STA_EX: begin
			o_op_ready_w	= 0;
			o_in_ready_w	= 1;
			if(!i_op_valid) begin // wait until i_op_valid
				next_state = STA_EX;
			end else begin
				case(i_op_mode)
					OP_LOAD_MAP: begin
						next_depth = 6'b100000;
						next_out_count = 0; //new
						next_out_idx	= 0;
						next_state	= STA_LOAD_MAP;
					end
					OP_SHIFT_RIGHT: begin 
						{column_overflow, next_position[2:0]} = current_position[2:0] + 1 + 1;
						if(column_overflow) begin
							next_position[2:0] = current_position[2:0];
						end // test overflow != shift
						else begin
							next_position[2:0] = current_position[2:0] + 1;
						end
						next_state = STA_FT;
					end
					OP_SHIFT_LEFT: begin 
						{column_overflow, next_position[2:0]} = current_position[2:0] - 1;
						if(column_overflow) begin
							next_position[2:0] = current_position[2:0];
						end // test overflow == shift
						next_state = STA_FT;
					end
					OP_SHIFT_UP: begin 
						{row_overflow, next_position[5:3]} = current_position[5:3] - 1;
						if(row_overflow) begin
							next_position[5:3] = current_position[5:3];
						end
						next_state = STA_FT;
					end
					OP_SHIFT_DOWN: begin 
						{row_overflow, next_position[5:3]} = current_position[5:3] + 1 + 1;
						if(row_overflow) begin
							next_position[5:3] = current_position[5:3];
						end
						else begin
							next_position[5:3] = current_position[5:3] + 1;
						end
						next_state = STA_FT;
					end
					OP_SCALE_DOWN: begin
						if(current_depth==6'b001000) begin// mim: 8
							next_depth = current_depth;
						end
						else begin
							next_depth = current_depth >> 1; // divide 2
						end
						next_state = STA_FT;
					end
					OP_SCALE_UP: begin
						if(current_depth==6'b100000) begin// max: 32
							next_depth = current_depth;
						end
						else begin
							next_depth = current_depth << 1; // multiply 2
						end
						next_state = STA_FT;
					end
					OP_CONV_SHOW: begin
						next_out_idx = 0;
						next_out_count = 0;
						next_acc0 = 0;
						next_acc1 = 0;
						next_acc2 = 0;
						next_acc3 = 0;
						next_state = STA_CAL_CONV;
					end
					OP_OUT_SHOW: begin
						next_out_idx = 0;
						next_out_count = 0;
            			next_state = STA_OUT_DATA;
					end
					default: begin
						next_state = STA_FT;
					end
				endcase
			end
		end
		STA_CAL_CONV: begin
			if(current_out_count == 16) begin//(current_depth*10'd16)) begin //done one calculation, total 4
				next_out_count = 0;
				next_state = STA_OUT_CONV;
			end
			else begin
				case(current_out_count[3:0])
					4'd0: begin // acc0
						if(up_overflow[3]||left_overflow[3]) begin // zero-padding
							feature = 0;
						end
						else begin
							if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
							else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
							else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
						end

						next_acc0 = current_acc0 + (feature >> 4);

						next_out_idx = current_out_idx + 1;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
					4'd1 :begin //acc0 acc1
						if(up_overflow[3]) begin // zero-padding
							feature = 0;
						end
						else begin
							if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
							else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
							else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
							//feature = {map[(current_position-9) + current_out_idx], 4'b0};
						end

						next_acc0 = current_acc0 + (feature >> 3);
						next_acc1 = current_acc1 + (feature >> 4);

						next_out_idx = current_out_idx + 1;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
					4'd2: begin //acc0 acc1
						if(up_overflow[3]) begin // zero-padding
							feature = 0;
						end
						else begin
							if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
							else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
							else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
							//feature = {map[(current_position-9) + current_out_idx], 4'b0};
						end

						next_acc0 = current_acc0 + (feature >> 4);
						next_acc1 = current_acc1 + (feature >> 3);

						next_out_idx = current_out_idx + 1;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
					4'd3: begin //acc1
						if(up_overflow[3]||right_overflow[3]) begin // zero-padding
							feature = 0;
						end
						else begin
							if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
							else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
							else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
							//feature = {map[(current_position-9) + current_out_idx], 4'b0};
						end

						next_acc1 = current_acc1 + (feature >> 4);

						next_out_idx = current_out_idx + 5;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
					4'd4: begin //acc0 acc2
						if(left_overflow[3]) begin // zero-padding
							feature = 0;
						end
						else begin
							if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
							else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
							else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
							//feature = {map[(current_position-9) + current_out_idx], 4'b0};
						end

						next_acc0 = current_acc0 + (feature >> 3);
						next_acc2 = current_acc2 + (feature >> 4);

						next_out_idx = current_out_idx + 1;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
					4'd5 :begin //acc0 acc1 acc2 acc3
						if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
						else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
						else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
						//feature = {map[(current_position-9) + current_out_idx], 4'b0};

						next_acc0 = current_acc0 + (feature >> 2);
						next_acc1 = current_acc1 + (feature >> 3);
						next_acc2 = current_acc2 + (feature >> 3);
						next_acc3 = current_acc3 + (feature >> 4);

						next_out_idx = current_out_idx + 1;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
					4'd6: begin //acc0 acc1 acc2 acc3
						if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
						else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
						else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
						//feature = {map[(current_position-9) + current_out_idx], 4'b0};

						next_acc0 = current_acc0 + (feature >> 3);
						next_acc1 = current_acc1 + (feature >> 2);
						next_acc2 = current_acc2 + (feature >> 4);
						next_acc3 = current_acc3 + (feature >> 3);

						next_out_idx = current_out_idx + 1;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
					4'd7: begin //acc1 acc3
						if(right_overflow[3]) begin // zero-padding
							feature = 0;
						end
						else begin
							if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
							else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
							else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
							//feature = {map[(current_position-9) + current_out_idx], 4'b0};
						end

						next_acc1 = current_acc1 + (feature >> 3);
						next_acc3 = current_acc3 + (feature >> 4);

						next_out_idx = current_out_idx + 5;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
					4'd8: begin //acc0 acc2
						if(left_overflow[3]) begin // zero-padding
							feature = 0;
						end
						else begin
							if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
							else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
							else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
							//feature = {map[(current_position-9) + current_out_idx], 4'b0};
						end

						next_acc0 = current_acc0 + (feature >> 4);
						next_acc2 = current_acc2 + (feature >> 3);
						
						next_out_idx = current_out_idx + 1;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
					4'd9: begin //acc0 acc1 acc2 acc3
						if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
						else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
						else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
						//feature = {map[(current_position-9) + current_out_idx], 4'b0};

						next_acc0 = current_acc0 + (feature >> 3);
						next_acc1 = current_acc1 + (feature >> 4);
						next_acc2 = current_acc2 + (feature >> 2);
						next_acc3 = current_acc3 + (feature >> 3);

						next_out_idx = current_out_idx + 1;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
					4'd10: begin //acc0 acc1 acc2 acc3
						if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
						else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
						else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
						//feature = {map[(current_position-9) + current_out_idx], 4'b0};

						next_acc0 = current_acc0 + (feature >> 4);
						next_acc1 = current_acc1 + (feature >> 3);
						next_acc2 = current_acc2 + (feature >> 3);
						next_acc3 = current_acc3 + (feature >> 2);

						next_out_idx = current_out_idx + 1;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
					4'd11: begin //acc1 acc3
						if(right_overflow[3]) begin // zero-padding
							feature = 0;
						end
						else begin
							if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
							else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
							else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
							//feature = {map[(current_position-9) + current_out_idx], 4'b0};
						end

						next_acc1 = current_acc1 + (feature >> 4);
						next_acc3 = current_acc3 + (feature >> 3);

						next_out_idx = current_out_idx + 5;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
					4'd12: begin //acc2
						if(left_overflow[3]||down_overflow[3]) begin // zero-padding
							feature = 0;
						end
						else begin
							if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
							else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
							else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
							//feature = {map[(current_position-9) + current_out_idx], 4'b0};
						end

						next_acc2 = current_acc2 + (feature >> 4);

						next_out_idx = current_out_idx + 1;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
					4'd13: begin //acc2 acc3
						if(down_overflow[3]) begin // zero-padding
							feature = 0;
						end
						else begin
							if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
							else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
							else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
							//feature = {map[(current_position-9) + current_out_idx], 4'b0};
						end

						next_acc2 = current_acc2 + (feature >> 3);
						next_acc3 = current_acc3 + (feature >> 4);

						next_out_idx = current_out_idx + 1;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
					4'd14: begin //acc2 acc3
						if(down_overflow[3]) begin // zero-padding
							feature = 0;
						end
						else begin
							if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
							else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
							else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
							//feature = {map[(current_position-9) + current_out_idx], 4'b0};
						end

						next_acc2 = current_acc2 + (feature >> 4);
						next_acc3 = current_acc3 + (feature >> 3);

						next_out_idx = current_out_idx + 1;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
					4'd15: begin //acc3
						if(right_overflow[3]||down_overflow[3]) begin // zero-padding
							feature = 0;
						end
						else begin
							if(current_depth==32) feature = {map_0_31[(current_position-9) + current_out_idx], 4'b0};
							else if(current_depth==16) feature = {map_0_15[(current_position-9) + current_out_idx], 4'b0};
							else feature = {map_0_7[(current_position-9) + current_out_idx], 4'b0};
							//feature = {map[(current_position-9) + current_out_idx], 4'b0};
						end

						next_acc3 = current_acc3 + (feature >> 4);

						next_out_idx = current_out_idx + 37;
						next_out_count = current_out_count + 1;
						next_state = STA_CAL_CONV;
					end
				endcase
			end
		end
		STA_OUT_CONV: begin
			o_out_valid_w = 1;
			case(current_out_count)
				2'd0: o_out_data_w = (current_acc0[3]) ? current_acc0[16:4] + 1 : current_acc0[16:4];
				2'd1: o_out_data_w = (current_acc1[3]) ? current_acc1[16:4] + 1 : current_acc1[16:4];
				2'd2: o_out_data_w = (current_acc2[3]) ? current_acc2[16:4] + 1 : current_acc2[16:4];
				2'd3: o_out_data_w = (current_acc3[3]) ? current_acc3[16:4] + 1 : current_acc3[16:4];
				default: o_out_data_w = 0;
			endcase
            if(current_out_count == 2'd3) begin //0~127, depth default = 32, 2*2*32=128
                next_state = STA_FT;
            end
            else begin
				next_out_count = current_out_count + 1;
				next_state = STA_OUT_CONV;
            end
		end
		STA_OUT_DATA: begin
			o_out_valid_w = 1;
			if(current_out_count == (current_depth*10'd4)) begin
				o_out_valid_w = 0;
				next_state = STA_FT;
			end 
            else if(current_out_count == (current_depth*10'd4)-1) begin //0~127, depth default = 32, 2*2*32=128
				sram_i_A = current_position + current_out_idx;
				next_out_count = current_out_count + 1;
                next_state = STA_OUT_DATA;
            end
            else begin
				sram_i_A = current_position + current_out_idx;
				case(current_out_count[1:0])
					2'd0: begin
						next_out_idx = current_out_idx + 1;
						next_out_count = current_out_count + 1;
						next_state = STA_OUT_DATA;
					end
					2'd1 :begin
						next_out_idx = current_out_idx + 7;
						next_out_count = current_out_count + 1;
						next_state = STA_OUT_DATA;
					end
					2'd2: begin
						next_out_idx = current_out_idx + 1;
						next_out_count = current_out_count + 1;
						next_state = STA_OUT_DATA;
					end
					2'd3: begin
						next_out_idx = current_out_idx + 55;
						next_out_count = current_out_count + 1;
						next_state = STA_OUT_DATA;
					end
				endcase
            end
		end
		STA_LOAD_MAP: begin
			if(!i_in_valid) begin // wait until i_in_valid
				next_state = STA_LOAD_MAP;
			end 
			else begin // load 
				//------- set map to sram -------//
				sram_i_A = current_out_idx;/// Adress
				//---------------------------------//
				//map[current_out_idx] = i_in_data;
				if(current_out_idx<64)
					conv_reg = i_in_data;
				else
					conv_reg = i_in_data + map_0_31[current_out_count];
				
				if(current_out_idx == 2047) begin
					next_state = STA_FT;
				end 
				else begin
					if(current_out_count == 63) begin
						next_out_count = 0;
					end
					else begin
						next_out_count = current_out_count + 1;
					end
					next_out_idx = current_out_idx + 1;
					next_state = STA_LOAD_MAP;
				end
			end
		end
		STA_END: begin
			next_state = STA_END;
		end
	endcase
end

// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
always@(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin
		o_op_ready_r	 <= 0;
		o_in_ready_r	 <= 0;
		o_out_valid_r	 <= 0;
		o_out_data_r     <= 0;

		current_state    <= STA_IDLE;
		current_position <= 0;
		current_out_idx  <= 0;
		current_out_count<= 0;
		current_depth    <= 0; //default: 32
		current_acc0     <= 0;
		current_acc1     <= 0;
		current_acc2     <= 0;
		current_acc3     <= 0;

		row_overflow     <= 0;
		column_overflow  <= 0;
	end else begin
		o_op_ready_r	 <= o_op_ready_w;
		o_in_ready_r	 <= o_in_ready_w;
		o_out_valid_r	 <= o_out_valid_w;
		o_out_data_r     <= o_out_data_w;

		current_state    <= next_state;
		current_position <= next_position;
		current_out_idx  <= next_out_idx;
		current_out_count<= next_out_count;
		current_depth    <= next_depth;
		current_acc0     <= next_acc0;
		current_acc1     <= next_acc1;
		current_acc2     <= next_acc2;
		current_acc3     <= next_acc3;
		if(current_state == STA_LOAD_MAP) begin
			if(current_out_idx > 1023) begin// map_0_31
				map_0_31[current_out_count] <= conv_reg;
			end
			else if(current_out_idx > 511 && current_out_idx < 1024) begin// map_0_15 0_31
				map_0_31[current_out_count] <= conv_reg;
				map_0_15[current_out_count] <= conv_reg;
			end
			else begin// map_0_7 0_15 0_31
				map_0_31[current_out_count] <= conv_reg;
				map_0_15[current_out_count] <= conv_reg;
				map_0_7[current_out_count] <= conv_reg;
			end
		end
	end
end
endmodule