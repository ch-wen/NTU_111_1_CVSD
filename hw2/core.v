module core #(                             //Don't modify interface
	parameter ADDR_W = 32,
	parameter INST_W = 32,
	parameter DATA_W = 32
)(
	input                   i_clk,
	input                   i_rst_n,
	output [ ADDR_W-1 : 0 ] o_i_addr,
	input  [ INST_W-1 : 0 ] i_i_inst,
	output                  o_d_wen,
	output [ ADDR_W-1 : 0 ] o_d_addr,
	output [ DATA_W-1 : 0 ] o_d_wdata,
	input  [ DATA_W-1 : 0 ] i_d_rdata,
	output [        1 : 0 ] o_status,
	output                  o_status_valid
);

// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
// ---- Add your own wires and registers here if needed ---- //
	// input and output 
reg [ADDR_W-1 : 0] o_i_addr_r,       o_i_addr_w,       o_d_addr_r, o_d_addr_w;
reg [DATA_W-1 : 0] o_d_wdata_r,      o_d_wdata_w;
reg [1:0] 		   o_status_r,       o_status_w;
reg				   o_status_valid_r, o_status_valid_w, o_d_wen_r,  o_d_wen_w;
	// 32 registers
reg [31:0] registers [0:31];
reg [5: 0] i; // 0~32
	// 7 states, 3bits
reg [2:0] current_state, next_state;
parameter IDLE = 3'd0;
parameter IF   = 3'd1;
parameter ID   = 3'd2;
parameter ALU  = 3'd3;
parameter DWB  = 3'd4;
parameter NPG  = 3'd5;
parameter PE   = 3'd6;
parameter OF   = 3'd7; // overflow 
	// program controller
reg [ADDR_W-1 : 0] current_pc, next_pc;
	// IF
reg [INST_W-1 : 0] i_i_inst_w;
	// ID
reg [5:0]  opcode;
reg [4:0]  ss, tt, dd;
reg [15:0] im;
reg [1:0]  type; // 3 types
	//ALU
reg overflow;
reg [31:0] temp_1, temp_2;
reg [32:0] sum;
// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
// ---- Add your own wire data assignments here if needed ---- //
assign o_i_addr       = o_i_addr_r;
assign o_d_addr       = o_d_addr_r;
assign o_d_wdata      = o_d_wdata_r;
assign o_status       = o_status_r;
assign o_status_valid = o_status_valid_r;
assign o_d_wen        = o_d_wen_r;
// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your conbinational block design here ---- //
always @(current_state) begin
	if(i_rst_n) begin
		case(current_state)
			IDLE: begin
				o_i_addr_w		 = 0;
				o_d_addr_w		 = 0;
				o_d_wdata_w		 = 0;
				o_status_w		 = 0;
				o_status_valid_w = 0;
				o_d_wen_w		 = 0;
				overflow         = 0;
				i_i_inst_w       = 0;
				opcode           = 0;
				ss               = 0;
				tt               = 0;
				dd               = 0;
				im               = 0;
				type             = 0;
				temp_1           = 0;
				temp_2           = 0;
				sum              = 0;
				next_state       = IF;
			end
			IF: begin
				i_i_inst_w = i_i_inst;
				next_pc = current_pc + 4;
				next_state = (i_i_inst==0) ? IDLE : ID; 
			end
			ID: begin
				opcode = i_i_inst_w[31:26];
				ss     = i_i_inst_w[25:21]; //s2
				tt     = i_i_inst_w[20:16]; //s3
				dd     = i_i_inst_w[15:11]; //s1
				im     = i_i_inst_w[15: 0];
				case(opcode)
					`OP_ADD, `OP_SUB, `OP_ADDU, `OP_SUBU, `OP_AND, `OP_OR, `OP_NOR, `OP_SLT: begin
						type = 2'd0; // R
						next_state = ALU;
					end
					`OP_ADDI, `OP_LW, `OP_SW, `OP_BEQ, `OP_BNE: begin
						type = 2'd1; // I
						next_state = ALU;
					end
					default: begin
						type = 2'd2; // EOF
						next_state = PE;
					end
				endcase				
			end
			ALU: begin
				case(opcode)
					`OP_ADD: begin
						temp_1 = registers[ss];
						temp_2 = registers[tt];
						sum = {temp_1[31], temp_1} + {temp_2[31], temp_2};
						registers[dd] = sum[31:0];
						overflow = ^sum[32:31];
					end
					`OP_SUB: begin
						temp_1 = registers[ss];
						temp_2 = registers[tt];
						sum = {temp_1[31], temp_1} - {temp_2[31], temp_2};
						registers[dd] = sum[31:0];
						overflow = ^sum[32:31];
					end
					`OP_ADDU: begin
						{overflow, registers[dd]} = registers[ss] + registers[tt];
					end
					`OP_SUBU: begin
						registers[dd] = registers[ss] - registers[tt];
						overflow = (registers[ss] < registers[tt]) ? 1 : 0;
					end
					`OP_ADDI: begin		
						temp_1 = registers[ss];
						sum = {temp_1[31], temp_1} + {{16{im[15]}}, im};
						registers[tt] = sum[31:0];
						overflow = ^sum[32:31];			
					end
					`OP_LW: begin			
						{overflow, o_d_addr_w} = registers[ss] + im;			
					end
					`OP_SW: begin
						{overflow, o_d_addr_w} = registers[ss] + im;
						o_d_wdata_w = registers[tt];
						o_d_wen_w = 1;
					end
					`OP_AND: begin
						registers[dd] = registers[ss] & registers[tt];
					end
					`OP_OR: begin
						registers[dd] = registers[ss] | registers[tt];
					end
					`OP_NOR: begin
						registers[dd] = ~(registers[ss] | registers[tt]);
					end
					`OP_BEQ: begin
						next_pc = (registers[ss]==registers[tt]) ? next_pc + im : next_pc;
					end
					`OP_BNE: begin
						next_pc = (registers[ss]!=registers[tt]) ? next_pc + im : next_pc;
					end
					`OP_SLT: begin
						registers[dd] = (registers[ss] < registers[tt]) ? 1 : 0;
					end
				endcase
				next_state = OF;				
			end
			OF : begin
				if(!overflow) begin
					if(opcode==`OP_LW)
						registers[tt] = i_d_rdata;
				end
				next_state = DWB;
			end
			DWB: begin
				if(!overflow) begin
					case(opcode)
						`OP_LW: registers[tt] = i_d_rdata;
						`OP_SW: o_d_wen_w = 0;
					endcase
				end
				next_state = NPG;
			end
			NPG: begin
				current_pc       = next_pc;
				o_i_addr_w       = next_pc;
				o_status_valid_w = 1;
				if(overflow) begin
					o_status_w = `MIPS_OVERFLOW;
					next_state = PE;
				end
				else begin
					if(type == 2'd0)
						o_status_w = `R_TYPE_SUCCESS;
					else
						o_status_w = `I_TYPE_SUCCESS;
					next_state = IDLE;
				end
			end
			PE: begin
				o_status_w       = `MIPS_END;
				o_status_valid_w = 1;
				next_state       = PE;
			end
		endcase
	end
end
// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //
always @(posedge i_clk or negedge i_rst_n) begin
	if(!i_rst_n) begin //set 0
		o_i_addr_r			 <= 0;
		o_d_addr_r			 <= 0;
		o_d_wdata_r			 <= 0;
		o_status_r			 <= 0;
		o_status_valid_r	 <= 0;
		o_d_wen_r			 <= 0;
		o_i_addr_w			 <= 0;
		o_d_addr_w			 <= 0;
		o_d_wdata_w			 <= 0;
		o_status_w			 <= 0;
		o_status_valid_w	 <= 0;
		o_d_wen_w			 <= 0;
		i_i_inst_w           <= 0;
		opcode               <= 0;
		ss                   <= 0;
		tt                   <= 0;
		dd                   <= 0;
		im                   <= 0;
		current_state        <= 0;
		next_state           <= 1; //begin
		overflow             <= 0;
		current_pc           <= 0;
		next_pc              <= 0;
		type                 <= 0;
		temp_1               <= 0;
		temp_2               <= 0;
		sum                  <= 0;
		for(i=0; i<32; i=i+1)
			registers[i] <=0;
	end
	else begin
		o_i_addr_r			 <= o_i_addr_w;
		o_d_addr_r			 <= o_d_addr_w;
		o_d_wdata_r			 <= o_d_wdata_w;
		o_status_r			 <= o_status_w;
		o_status_valid_r	 <= o_status_valid_w;
		o_d_wen_r			 <= o_d_wen_w;
	end
end
always @(negedge i_clk) begin
	if(i_rst_n)
		current_state = next_state;
	else
		current_state = current_state;
end
endmodule