module IIS_SEND#(
	parameter data_depth = 64
)
(
	input clk_in, //from apb clk
	input [15:0] data_in,
	input rst,
	input [2:0] send_ctrl,
	output      data,
	output reg  WS_reg,
	output      sck,
	output      send_over,
	output      rd_clk, //to tx_fifo read clk  
	output reg [31:0] send_num,
	output reg fifo_rden,
	output send_finish
);	
	
	parameter  CLK1_DIV = 10;
	parameter  CLK2_DIV = 20;
	localparam IDLE = 2'b00,
		   LEFT = 2'b01,
		   RIGHT = 2'b10;
	
	//-------
	reg [4:0]  bit_cnt;
	reg [1:0]  state;
	reg [1:0]  next_state;
	reg [16:0] data_send;
	reg        WS_t;
	wire       ws_posedge; //
	wire       ws_negedge;
	wire       fifo_rden1;
	reg        fifo_rden2;	

	assign sck = clk_in;
	assign rd_clk = clk_in;
	
	always@(posedge sck or negedge rst) begin
	if(!rst)	
		state <= IDLE;
	else if(send_ctrl[0]) //enable signals
		state <= next_state;
	else
		state <= IDLE;
	end

	always@(*) begin
	case(state)
		IDLE:
		begin
			if(WS_reg)//
				next_state = LEFT;
			else
				next_state = RIGHT;
		end
		LEFT:
		begin
			if(send_over)
				next_state = IDLE;
			else 
				next_state = LEFT;
		end
		RIGHT:
		begin
			if(send_over)
				next_state = IDLE;
			else
				next_state = RIGHT;
		end
		default: next_state = IDLE;
	endcase
	end

	always@(posedge sck or negedge rst) begin
	if(!rst)
		bit_cnt <= 'd0;
	else if( (state!=IDLE) && (bit_cnt!='d18) )
	//else if( (ws_posedge||ws_negedge) && (bit_cnt!='d16) )
		bit_cnt <= bit_cnt + 1'b1;
	else
		bit_cnt <= 'd0;
	end
	
	//assign WS_reg = (send_ctrl[1]==1'b1);

	always@(posedge sck or negedge rst) begin //
	if(!rst)
		WS_reg <= 1'b0;
	else if(fifo_rden)
		WS_reg <= ~WS_reg;
	else
		WS_reg <= WS_reg;
	end	

	always@(posedge sck or negedge rst) begin
	if(!rst)
		WS_t <= 1'b0;
	else 
		WS_t <= WS_reg;
	end
	
	assign ws_posedge = WS_reg && (!WS_t);
	assign ws_negedge = (!WS_reg) && WS_t;

	always@(posedge sck or negedge rst) begin
	if(!rst)
		data_send <= 'd0;
	else if(send_ctrl[2]) 
	begin
		//if(ws_posedge || ws_negedge || (state==IDLE)||(bit_cnt=='d15))
		if(ws_posedge || ws_negedge )
			data_send <= {data_in,1'b0};
		else
			data_send <= {data_send[15:0],1'b0};
	end
	else 
		data_send <= 'b0;
	end
	
	assign data   = data_send[16];
	assign send_over = (bit_cnt=='d17) ? 1'b1:1'b0;
	assign fifo_rden1 = send_over ? 1'b1:1'b0;

	always@(posedge sck or negedge rst) begin
	if(!rst) begin
		fifo_rden2 <= 1'b0;
		fifo_rden  <= 1'b0;
	end
	else begin
		fifo_rden2 <= fifo_rden1;
		fifo_rden  <= fifo_rden2;
	end
	end
	
	always@(posedge sck or negedge rst) begin
	if(!rst)
		send_num <= 32'd0;
	else if(send_finish)
		send_num <= 32'd0;
	else if(fifo_rden)
		send_num <= send_num + 1'd1;
	else
		send_num <= send_num; 
	end	

	assign send_finish = (send_num==data_depth-1) ? 1'b1:1'b0;


endmodule

