`timescale 1ns/10ps
module IOTDF( clk, rst, in_en, iot_in, fn_sel, busy, valid, iot_out);
input          clk;
input          rst;
input          in_en;
input  [7:0]   iot_in;
input  [2:0]   fn_sel;
output         busy;
output         valid;
output [127:0] iot_out;
//------------------------------------------------
// i/os
reg			busy_w,    busy_r, 
            valid_w,   valid_r;
reg	[127:0]	iot_out_w, iot_out_r;
// vars
reg [127:0] current_data [7:0];
reg [7:0]   next_data;
reg	[2:0]   current_state,    next_state; // 000~111
reg [2:0]   current_count_8,  next_count_8; // 0~7
reg [3:0]   current_cycle,    next_cycle; // 0~15
reg [7:0]   data_bits; // 127
reg [3:0]   current_count_12, next_count_12; // 0~11
reg [2:0]   current_pos,      next_pos; // 0~7 for fns
reg [142:0] current_sum,      next_sum;
reg [3:0]   i;
// states
parameter STA_IDLE = 3'd0,
		  STA_LOAD = 3'd1,
		  STA_ALU  = 3'd2,
		  STA_OUT  = 3'd3,
		  STA_END  = 3'd4;
// functions
parameter FNS_MAX      = 3'b001,
		  FNS_MIN      = 3'b010,
		  FNS_AVG      = 3'b011,
		  FNS_EXTRACT  = 3'b100,
		  FNS_EXCLUDE  = 3'b101,
		  FNS_PEAK_MAX = 3'b110,
		  FNS_PEAK_MIN = 3'b111;
//-------------------------------------------------
assign busy    = busy_r;
assign valid   = valid_r;
assign iot_out = iot_out_r;
//-------------------------------------------------
// load data
always @(*) begin
	for(i=0; i<8; i=i+1) begin
		next_data[i] = current_data[i];
	end
	data_bits = 0;
	if(in_en) begin
		data_bits  = (current_cycle<<3);
		next_data  = iot_in;
		next_cycle = current_cycle + 1;
	end
	else begin
		next_cycle = current_cycle;
	end
end
// FMS
always @(*) begin
	next_count_8  = current_count_8;
	next_pos      = current_pos;
	next_count_12 = current_count_12;
	case(current_state)
		STA_IDLE: begin
			next_state = STA_LOAD;
		end
		STA_LOAD: begin
			if(current_cycle == 15) begin //done
				next_count_8 = current_count_8 + 1;
				next_pos     = current_count_8;
				next_state   = STA_ALU;
			end
			else begin
				next_state = STA_LOAD;
			end
		end
		STA_ALU: begin
			if(current_pos == 7) begin
				next_count_12 = current_count_12 + 1;
			end
			else begin
				next_count_12 = current_count_12;
			end
			if(current_count_12 == 12) begin // done all
				next_state = STA_END;
			end
			else begin
				next_state = STA_LOAD;
			end
			
		end
		STA_END: begin
			next_state = STA_END;
		end
		default: begin
			next_state	= STA_LOAD;
		end
	endcase
end
// functions
always @(*) begin
	valid_w	  = 0;
	busy_w	  = 0;
	iot_out_w = 0;
	next_sum  = current_sum;
	if(current_state==STA_ALU) begin
		case(fn_sel)
			FNS_MAX: begin
				next_sum  = (current_pos==0)? current_data[0] : (current_sum>current_data[current_pos])? current_sum: current_data[current_pos];
				valid_w   = (current_pos==7)? 1 : 0;
				iot_out_w = (current_pos==7)? (current_sum>current_data[current_pos])? current_sum : current_data[current_pos] : 0;
			end
			FNS_MIN: begin
				next_sum  = (current_pos==0)? current_data[0] : (current_sum<current_data[current_pos])? current_sum : current_data[current_pos];
				valid_w   = (current_pos==7)? 1 : 0;
				iot_out_w = (current_pos==7)? (current_sum<current_data[current_pos])? current_sum : current_data[current_pos] : 0;
			end
			FNS_AVG: begin
				next_sum  = (current_pos==0)? current_data[0] : current_sum + current_data[current_pos];
				valid_w   = (current_pos==7)? 1 : 0;
				iot_out_w = (current_pos==7)? (current_sum + current_data[current_pos]) >> 3 : 0;
			end
			FNS_EXTRACT: begin
				valid_w   = (current_data[current_pos]>128'h6FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF && current_data[current_pos]<128'hAFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)?   1 : 0;
				iot_out_w = (current_data[current_pos]>128'h6FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF && current_data[current_pos]<128'hAFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)? current_data[current_pos] : 0;
			end
			FNS_EXCLUDE: begin
				valid_w   = (current_data[current_pos]<128'h7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF || current_data[current_pos]>128'hBFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)? 1 : 0;
				iot_out_w = (current_data[current_pos]<128'h7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF || current_data[current_pos]>128'hBFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)? current_data[current_pos] : 0;
			end
			FNS_PEAK_MAX: begin
				next_sum = current_sum;
				if(current_count_12 == 0) begin // first
					if(current_pos == 0) begin // first
						next_sum = current_data[0];
					end
					else begin
						next_sum = (current_sum>current_data[current_pos])? current_sum : current_data[current_pos];
					end
					if(current_pos == 7) begin // accum
						valid_w   = 1;
						iot_out_w = (current_sum>current_data[current_pos])? current_sum : current_data[current_pos];
						next_sum  = (current_sum>current_data[current_pos])? current_sum : current_data[current_pos];
					end
					else begin
						valid_w	  = 0;
						iot_out_w = 0;
					end
				end
				else begin
					if(current_data[current_pos] > current_sum) begin //
						valid_w   = 1;
						iot_out_w = current_data[current_pos];
						next_sum  = (current_sum>current_data[current_pos])? current_sum : current_data[current_pos];
					end
					else begin
						valid_w   = 0;
						iot_out_w = 0;
					end
					if(current_pos == 7) begin
						next_sum = (current_sum>current_data[current_pos])? current_sum : current_data[current_pos];
					end
				end
			end
			FNS_PEAK_MIN: begin
				next_sum = current_sum;
				if(current_count_12 == 0) begin // first
					if(current_pos == 0) begin // first
						next_sum = current_data[0];
					end
					else begin
						next_sum = (current_sum<current_data[current_pos])? current_sum : current_data[current_pos];
					end
					if(current_pos == 7) begin // accum
						valid_w   = 1;
						iot_out_w = (current_sum<current_data[current_pos])? current_sum : current_data[current_pos];
						next_sum  = (current_sum<current_data[current_pos])? current_sum : current_data[current_pos]; //
					end
					else begin
						valid_w	  = 0;
						iot_out_w = 0;
					end
				end
				else begin
					if(current_data[current_pos] < current_sum) begin //
						valid_w   = 1;
						iot_out_w = current_data[current_pos]; 
						next_sum  = (current_sum<current_data[current_pos])? current_sum : current_data[current_pos];
					end
					else begin
						valid_w   = 0;
						iot_out_w = 0;
					end
					if(current_pos == 7) begin
						next_sum = (current_sum<current_data[current_pos])? current_sum : current_data[current_pos];
					end
				end
			end
			default: begin
				valid_w	  = 0;
				iot_out_w = 0;
			end
		endcase
	end
	else begin
		valid_w	  = 0;
		iot_out_w = 0;
	end
end
//------------------------------------------------
always @(posedge clk or posedge rst) begin
	if(rst) begin
		iot_out_r        <= 0;
		valid_r          <= 0;
		busy_r           <= 0;
		current_sum      <= 0;
		current_pos      <= 0;
		current_count_12 <= 0;
		current_count_8  <= 0;
		current_cycle    <= 0;
		current_state    <= STA_IDLE;
		for(i=0; i<8; i=i+1) 
			current_data[i] <= 0;
	end
	else begin
		iot_out_r        <= iot_out_w;
		valid_r          <= valid_w;
		busy_r           <= busy_w;
		current_sum      <= next_sum;
		current_pos      <= next_pos;
		current_count_12 <= next_count_12;
		current_count_8  <= next_count_8;
		current_cycle    <= next_cycle;
		current_state    <= next_state;
		current_data[current_count_8][data_bits +: 8] <= next_data;
	end
end
endmodule