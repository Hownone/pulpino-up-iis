module IIS_SEND(
	input clk_in, //from apb clk
	input [15:0] data_in,
	input rstn,
	input [2:0] send_ctrl,
	output      data,
	output reg  WS_t,
	output      sck,
	output      send_over
	output reg  rd_clk
);	
	
	parameter  CLK1_DIV = 10;
	parameter  CLK2_DIV = 20;
	localparam IELD = 2'b00,
		   LEFT = 2'b01,
		   RIGHT = 2'b10;
	
	//-------
	reg [3:0]  clk1_cnt;
	reg [4:0]  clk2_cnt;
	reg [4:0]  bit_cnt;
	reg [1:0]  state;
	reg [1:0]  next_state;
	reg [16:0] data_send;
	wire       WS_reg;
	wire       ws_posedge; //
	wire       ws_negedge;
	
	always@(negedge clk_in or negedge rstn) begin
	if(!rstn) begin
		clk1_cnt <= 4'd0;
		clk      <= 1'b1;
	end
	else if(clk1_cnt==CLK1_DIV-1) begin
		clk1_cnt <= 4'd0;
		clk      <= ~clk;
	end
	else begin
		clk1_cnt <= clk1_cnt + 1'd1;
		clk <= clk;
	end
	end
	
	always@(negedge clk_in or negedge rstn) begin
	if(!rstn) begin
		clk2_cnt <= 4'd0;
		rd_clk   <= 1'b1;
	end
	else if(clk2_cnt==CLK2_DIV-1) begin
		clk2_cnt <= 4'd0;
		rd_clk   <= ~rd_clk;
	end
	else begin
		clk2_cnt <= clk2_cnt + 1'd1;
		rd_clk   <= rd_clk;
	end
	end
	
	always@(negedge clk or negedge rstn) begin
	if(!rstn)	
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
			if(send_ctrl[1])
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

	always@(negedge clk or negedge rstn) begin
	if(!rstn)
		bit_cnt <= 'd0;
	else if( (state!=IDLE) && (bit_cnt!='d16) )
		bit_cnt <= bit_cnt + 1'b1;
	else
		bit_cnt <= 'd0;
	end
	
	always@(negedge clk or negedge rstn) begin
	if(!rstn)
		WS_t <= 1'b0;
	else 
		WS_t <= WS_reg;
	end
	
	assign ws_posedge = WS_reg && (!WS_t);
	assign ws_negedge = (!WS_reg) && WS_t;

	always@(negedge clk or negedge rstn) begin
	if(!rstn)
		data_send <= 'd0;
	else if(send_ctrl[2]) 
	begin
		if(ws_posedge || ws_negedge (state==IDLE)||(bit_cnt=='d15))
			data_send <= {data_in,1'b0};
		else
			data_send <= {data_send[15:0],1'b0};
	end
	else 
		data_send <= 'b0;
	end
	
	assign WS_reg = (send_ctrl[1]==1'b1);
	assign DATA   = data_send[16];
	assign send_over = (bit_cnt=='d15) ? 1'b1:1'b0;


endmodule

