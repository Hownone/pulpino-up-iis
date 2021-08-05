module apb_iis(
	input             pclk,
	input         	  presetn,
	input             penable,
	input             psel,
	input             write,
	input [31:0]      paddr,
	input [15:0]      pwdata,
	input             sck_i,
	input             ws_i,
	input             sd_i,
	
	output            sck_o;
        output            ws_o;
        output            sd_o;
	output reg [15:0] prdata,
	output            pready,
	output            irq

);
	wire        sck_o;
	wire        ws_o;
	wire        sd_o;
	
	wire        irq;

	wire        apb_write;
	wire        apb_read;
	
	wire        tx_fifo_rdclk;
	wire        tx_fifo_rden;
	wire        tx_fifo_vaild;
	wire	    tx_fifo_empty;
	wire 	    tx_fifo_full;
	wire [15:0] send_data;
	
	wire        rx_fifo_wrclk;
	wire        rx_fifo_wren;
	wire        rx_fifo_vaild;
	wire	    rx_fifo_empty;
	wire 	    rx_fifo_full;
	wire [15:0] receive_data;
	wire [2:0]  iis_tx_config;
	wire [15:0] rd_data; //from rx_fifo
	
	parameter TX_CONFIG_ADDR = 32'h04,
		  RX_CONFIG_ADDR = 32'h08,
		  RX_DATA_ADDR   = 32'h12,
		  INTMASK_ADDR   = 32'h16;
	
	//register
	reg 	   iis_tx_en;
	reg 	   iis_tx_ws;
	reg [15:0] pwdata_tx;
	reg        iis_rx_en;
	//reg [15:0] pwdata_rx;
	
	//interrupt register mask
	reg        tx_fifo_tmpty_maks;
	reg        tx_fifo_full_mask;       
	reg        rx_fifo_full_mask;
	reg        rx_fifo_tmpty_mask;
	
	//interrupt register
	reg        tx_fifo_tmpty_int;
	reg        tx_fifo_full_int;       
	reg        rx_fifo_full_int;
	reg        rx_fifo_tmpty_int;


	//instant module
	async_fifo
	#(
		.data_width = 16,
		.data_depth = 1024,
		.addr_width = 10
	)
	tx_fifo
	(
		.rst(!presetn),
		.wr_clk(pclk),
		.wr_en(apb_write),
		.din(pwdata_tx), //from apb bus
		.rd_clk(tx_fifo_rdclk),
		.rd_en(tx_fifo_rden),
		.vaild(tx_fifo_vaild),
		.dout(send_data),
		.empty(tx_fifo_empty),
		.full(tx_fifo_full)
);

	IIS_SEND IIS_SEND(
		.clk_in(pclk),
		.data_in(send_data),
		.rstn(!presetn),
		.send_ctrl(iis_tx_config), //use register config
		.data(sd_o),
		.WS_t(ws_o),
		.sck(sck_o),
		.send_over(tx_fifo_rden) //tx_fifo read enable signals
		.rd_clk(tx_fifo_rdclk)
);	

	async_fifo
	#(
		.data_width = 16,
		.data_depth = 1024,
		.addr_width = 10
	)
	rx_fifo
	(
		.rst(!presetn),
		.wr_clk(rx_fifo_wrclk),
		.wr_en(rx_fifo_wren),
		.din(receive_data),
		.rd_clk(pclk),
		.rd_en(apb_read),
		.vaild(rx_fifo_vaild),
		.dout(),
		.empty(rx_fifo_empty),
		.full(rx_fifo_full) //to apb bus
);

	IIS_RECEIVE IIS_RECEIVE(
		.clk(sck_i),
		.rstn(!presetn),
		.WS_r(ws_i),
		.rx_en(iis_rx_en), //use register config
		.DATA(sd_i),
		.wr_clk(rx_fifo_wrclk),
		.L_DATA(),
		.R_DATA(),
		.SDATA(receive_data),
		.recv_over(rx_fifo_wren)
);

	assign apb_write = pwrite && psel && penable;
	assign apb_read  = (!pwrite) && psel && penable;
	assign iis_tx_config = {1'b1,iis_tx_ws,iis_tx_en};	
	assign pready = 1'b1;


	//Generate interrupt state tx_fifo full
	always@(posedge pclk or negedge presetn) begin
	if(!presetn)
		tx_fifo_full_int <= 1'b0;
	else if(tx_fifo_full)
		tx_fifo_full_int <= 1'b1;
	else 
		tx_fifo_full_int <= 1'b0;
	end
	
	//Generate interrupt state tx_fifo empty
	always@(posedge pclk or negedge presetn) begin
	if(!presetn)
		tx_fifo_empty_int <= 1'b0;
	else if(tx_fifo_empty)
		tx_fifo_empty_int <= 1'b1;
	else 
		tx_fifo_empty_int <= 1'b0;
	end
	
	//Generate interrupt state rx_fifo full
	always@(posedge pclk or negedge presetn) begin
	if(!presetn)
		rx_fifo_full_int <= 1'b0;
	else if(rx_fifo_full)
		rx_fifo_full_int <= 1'b1;
	else 
		rx_fifo_full_int <= 1'b0;
	end
	
	//Generate interrupt state rx_fifo empty
	always@(posedge pclk or negedge presetn) begin
	if(!presetn)
		rx_fifo_empty_int <= 1'b0;
	else if(rx_fifo_empty)
		rx_fifo_empty_int <= 1'b1;
	else 
		rx_fifo_empty_int <= 1'b0;
	end

	//Generate interrupt signal
	assign irq = (tx_fifo_empty_int && !tx_fifo_empty_mask) ||
		     (tx_fifo_full_int  && !tx_fifo_full_mask)  ||
		     (rx_fifo_empty_int && !rx_fifo_empty_mask) ||
		     (rx_fifo_full_int  && !rx_fifo_full_mask);

	//write operation
	always@(posedge pclk or negedge presetn) begin
	if(!presetn) begin
		//reg <= initial
		iis_tx_en          <= 1'b0;
		iis_tx_ws          <= 1'b1;
		iis_rx_en          <= 1'b0;
		pwdata_tx          <= 16'h0;
		tx_fifo_tmpty_maks <= 1'b0;
        	tx_fifo_full_mask  <= 1'b0; 
                rx_fifo_full_mask  <= 1'b0;
                rx_fifo_tmpty_mask <= 1'b0;
	end
	else if(apb_write) begin //write register
		case(paddr[31:0])
		TX_CONFIG_ADDR: begin
			pwdata_tx <= pwdata[17:2];
			iis_tx_ws <= pwdata[1];
			iis_tx_en <= pwdata[0];
		end
		RX_CONFIG_ADDR: begin
			iis_rx_en <= pwdata[0];
		end
		INTMASK_ADDR: begin
			tx_fifo_tmpty_maks <= pwdata[3]; 		
                	tx_fifo_full_mask  <= pwdata[2]; 
                	rx_fifo_full_mask  <= pwdata[1];
			rx_fifo_tmpty_mask <= pwdata[0];
		end
		default:;
		endcase
	end
	end	

	//read operation
	always@(posedge pclk or negedge presetn) begin
	if(!presetn)
		prdata <= 16'h0;
	end
	else if(apd_read && (paddr==RX_DATA_ADDR))
	end



endmodule

