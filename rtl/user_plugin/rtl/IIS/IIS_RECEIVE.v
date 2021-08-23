module IIS_RECEIVE#(
	parameter data_depth = 1024
)
(
	input             clk,
	input             rst,
	input             WS_r,
	input             rx_en,
	input             DATA,
	output            wr_clk,
	output reg [15:0] L_DATA,
	output reg [15:0] R_DATA,
	output reg [15:0] SDATA,
	output reg        fifo_wren,
	output reg [31:0] receive_num,
	output            receive_finish

);
	localparam IDLE      = 2'b00,
		   GET_LEFT  = 2'b01,
		   GET_RIGHT = 2'b10;
	
	reg [4:0] receive_cnt;
	reg [1:0] state,next_state;

	reg  WS_reg;
	wire ws_posedge,ws_negedge;
	wire fifo_wren1;
	reg  fifo_wren2;
	wire recv_over;

	assign wr_clk = clk;

	always@(posedge clk or posedge rst)
	begin
		if(rst)
			WS_reg <= 1'b0;
		else 
			WS_reg <= WS_r;

	end
	assign ws_posedge = WS_r && (!WS_reg);
	assign ws_negedge = (!WS_r) && WS_reg;

	always@(posedge clk or posedge rst) begin
	if(rst)
		state <= IDLE;
	else if(rx_en)
		state <= next_state;
	else
		state <= IDLE;
	end
	
	always@(*) begin
	case(state)
	IDLE:
		begin
			if(ws_posedge)
				next_state = GET_LEFT;
			else if(ws_negedge)
				next_state = GET_RIGHT;
			else
				next_state = IDLE;
		end
	GET_LEFT:
		begin
			if(receive_cnt=='d15)
				next_state = IDLE;
			else
				next_state = GET_LEFT;
		end
	GET_RIGHT:
		begin
			if(receive_cnt=='d15)
				next_state = IDLE;
			else
				next_state = GET_RIGHT;
		end
	default: next_state = IDLE;
	endcase
	end
	
	always@(posedge clk or posedge rst) begin
	if(rst)
		receive_cnt <= 'd0;
	else if( (state==GET_LEFT) || (state==GET_RIGHT) )
	begin
		if(receive_cnt!='d16) 
			receive_cnt <= receive_cnt + 1'b1;
		else
			receive_cnt <= 'd0;
	end
	else
		receive_cnt <= 'd0;

	end
	
	always@(posedge clk or posedge rst) begin
	if(rst)	
		L_DATA <= 'd0;
	else if((state==GET_LEFT) && (receive_cnt<'d16) )
		L_DATA <= {L_DATA[14:0],DATA}; //
	else
		L_DATA <= L_DATA;
	end

	always@(posedge clk or posedge rst) begin
	if(rst)
		R_DATA <= 'd0;
	else if( (state==GET_RIGHT)&&(receive_cnt <'d16) )
		R_DATA <= {R_DATA[14:0],DATA};
	else
		R_DATA <= R_DATA;
	end
/*
	always@(posedge clk or posedge rst) begin
	if(rst)
		SDATA <= 16'd0;	
	else if(ws_negedge && (receive_cnt=='d17))
		SDATA <= L_DATA;
	else if(ws_posedge && (receive_cnt=='d17))
		SDATA <= R_DATA;
	end
*/	
	always@(posedge clk or posedge rst) begin
	if(rst)
		SDATA <= 16'd0;	
	else if(ws_posedge && (next_state==GET_LEFT))
		SDATA <= L_DATA;
	else if(ws_negedge && (next_state==GET_RIGHT))
		SDATA <= R_DATA;
	end
	
	
	assign recv_over = (receive_cnt=='d16) ? 1'b1:1'b0;
	assign fifo_wren1 = recv_over ? 1'b1:1'b0;

	always@(posedge clk or posedge rst) begin
	if(rst) 
		fifo_wren  <= 1'b0;
	else if(receive_num>1 && (receive_num))
		fifo_wren  <= fifo_wren1;
	end	

	always@(posedge clk or posedge rst) begin
	if(rst)
		receive_num <= 32'd0;
	else if(rx_en) begin
		if(receive_finish)
			receive_num <= 32'd0;
		else if(fifo_wren1)
			receive_num <= receive_num + 1'd1;
		else
			receive_num <= receive_num;
	end
	else
		receive_num <= 32'd0;
	end

	assign receive_finish = (receive_num==data_depth)?1'b1:1'b0;


endmodule

