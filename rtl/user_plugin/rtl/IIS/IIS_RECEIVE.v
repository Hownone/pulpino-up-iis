module IIS_RECEIVE(
	input             clk,
	input             rstn,
	input             WS_r,
	input             rx_en,
	input             DATA,
	output            wr_clk;
	output reg [15:0] L_DATA,
	output reg [15:0] R_DATA,
	output reg [15:0] SDATA,
	output            recv_over

);
	localparam IDLE      = 2'b00,
		   GET_LEFT  = 2'b01,
		   GET_RIGHT = 2'b10;
	
	reg [4:0] receive_cnt;
	reg [1:0] state,next_state;

	reg WS_reg;
	wire ws_posedge,ws_negedge;

	assign wr_clk = clk;

	always@(negedge clk or negedge rstn)
	begin
		if(!rstn)
			WS_reg <= 1'b0;
		else 
			WS_reg <= WS_r;

	end
	assign ws_posedge = WS_r && (!WS_reg);
	assign ws_negedge = (!WS_r) && WS_reg;

	always@(negedge clk or negedge rstn) begin
	if(!rstn)
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
				next_state = GET_RIGHT;
		end
	GET_RIGHT:
		begin
			if(receive_cnt=='d15)
				next_state = IDLE;
			else
				next_state = GET_RIGHT
		end
	default: next_state = IDLE;
	endcase
	end
	
	always@(negedge clk or negedge rstn) begin
	if(!rstn)
		receive_cnt <= 'd0;
	else if(state==!IDLE)
	begin
		if(receive_cnt!='d16) 
			receive_cnt <= receive_cnt + 1'b1;
		else
			receive_cnt <= 'd0;
	end
	else
		receive_cnt <= 'd0;

	end
	
	always@(negedge clk or negedge rstn) begin
	if(!rstn)	
		L_DATA <= 'd0;
	else if((state==GET_LEFT) && (receive_cnt<'d16) )
		L_DATA <= {L_DATA[14:0],DATA}; //
	else
		L_DATA <= L_DATA;
	end

	always@(negedge clk or negedge rstn) begin
	if(!rstn)
		R_DATA <= 'd0;
	else if( (state==GET_RIGHT)&&(receive_cnt <'d16) )
		R_DATA <= {R_DATA[14:0],DATA};
	else
		R_DATA <= R_DATA;
	end

	assign recv_over = (receive_cnt=='d16) ? 1'b1:1'b0;
	
	always@(negedge clk or negedge rstn) begin
	if(!rstn)
		SDATA <= 16'd0;	
	else if(ws_negedge && (receive_cnt=='d16))
		SDATA <= L_DATA;
	else if(ws_posedge && (receive_cnt=='d16))
		SDATA <= R_DATA;
	end


endmodule

