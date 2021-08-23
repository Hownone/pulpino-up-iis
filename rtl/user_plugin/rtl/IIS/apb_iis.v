module apb_iis(
	input             pclk,
	input         	  presetn,
	input             penable,
	input             psel,
	input             pwrite,
	input [31:0]      paddr,
	input [31:0]      pwdata,
	//input             sck_i,
	//input             ws_i,
	//input             sd_i,
	//output            sck_o,
        //output            ws_o,
        //output            sd_o,
	output reg [31:0] prdata,
	output            pready,
	output            pslverr,
	output            irq,    //interrupt signals

	input  [7:0]      upio_in_i,
	output [7:0]      upio_out_o,
	output [7:0]      upio_dir_o

);
	wire        ws;
	wire        sd;
	
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
	wire [3:0]  iis_tx_config;
	wire [3:0]  iis_status; 
	wire [15:0] rd_data; //from rx_fifo -> apb
	wire [31:0] receive_num;
	wire [31:0] send_num;

	parameter IIS_TX_CONFIG  = 12'h30, //config iis tx register
		  IIS_RX_CONFIG  = 12'h34, //config iis rx register
		  IIS_INTMASK    = 12'h38, //interrupt mask register
		  IIS_STATUS     = 12'h3C,  //status register
		  IIS_TX_FIFO    = 12'h40, //data(apb->tx_fifo)
		  IIS_RX_FIFO    = 12'h44, //data(apb<-rd_fifo)
		  IIS_INTERRUPT  = 12'h48; //interrupt register

	
	//enable register
	reg 	   iis_tx_en;
	reg 	   iis_tx_ws;
	reg [15:0] pwdata_tx;
	reg        iis_rx_en;
	reg        tx_fifo_en; //tx_fifo start write operation	


	//status register
	reg apb_to_fifo; //apb bus data -> tx_fifo
	reg fifo_to_iis; //tx_fifo data -> iis send module
	reg iis_to_fifo;  //iis receive data -> fifo
	reg fifo_to_apb; //rx_fifo data -> apb bus

	//interrupt register mask
	reg        tx_fifo_full_mask;       
	reg        rx_fifo_full_mask;
	
	//interrupt register
	reg        tx_fifo_full_int;       
	reg        rx_fifo_full_int;
	
	assign apb_write    = pwrite && psel && penable;
	assign apb_read     = (!pwrite) && psel && penable;

	assign tx_fifo_wren = tx_fifo_en && apb_write && (!tx_fifo_full) && (!fifo_to_iis); 
	assign rx_fifo_rden = apb_read  && (!rx_fifo_empty); //rx fifo read enable
	
	assign iis_tx_config = {tx_fifo_en,1'b1,iis_tx_ws,iis_tx_en};	
	assign pready        = 1'b1;
	assign pslverr       = 1'b0;

	//instant module
	async_fifo
	#(
		.data_width (16),
		.data_depth (128),
		.addr_width (7)
	)
	tx_fifo
	(
		.rst(!presetn),
		.wr_clk(pclk),
		.wr_en(tx_fifo_wren),
		.din(pwdata_tx), //from apb bus
		.rd_clk(tx_fifo_rdclk),
		.rd_en(tx_fifo_rden),
		.vaild(tx_fifo_vaild),
		.dout(send_data),
		.empty(tx_fifo_empty),
		.full(tx_fifo_full)
);

	IIS_SEND#(
		.data_depth(128)
) 
	IIS_SEND(
		.clk_in(pclk),
		.data_in(send_data),
		.rst(!presetn),
		.send_ctrl(iis_tx_config[2:0]), //use register config
		.data(sd),
		.WS_reg(ws),
		.sck(sck),
		.rd_clk(tx_fifo_rdclk),
		.fifo_rden(tx_fifo_rden), //tx_fifo read enable signals
		.send_num(send_num),
		.send_finish(send_finish)
);		

	IIS_RECEIVE#(
		.data_depth(128)
) 
	IIS_RECEIVE(
		.rst(!presetn),
		.clk(sck),
		.WS_r(ws),
		.DATA(sd),
		.rx_en(iis_tx_config[0]&&(!rx_fifo_full)), //use register config
		.wr_clk(rx_fifo_wrclk), //to -> rx_fifo_wrclk
		.L_DATA(),
		.R_DATA(),
		.SDATA(receive_data),
		.fifo_wren(rx_fifo_wren),
		.receive_num(receive_num),
		.receive_finish(receive_finish)
);

	async_fifo
	#(
		.data_width (16),
		.data_depth (128),
		.addr_width (7)
	)
	rx_fifo
	(
		.rst(!presetn),
		.wr_clk(rx_fifo_wrclk),
		.wr_en(rx_fifo_wren),
		.din(receive_data),
		.rd_clk(pclk),
		.rd_en(rx_fifo_rden),
		.vaild(rx_fifo_vaild),
		.dout(rd_data),
		.empty(rx_fifo_empty),
		.full(rx_fifo_full) //to apb bus
);

	//iis send status (apb bus -> tx_fifo)
	always@(posedge pclk or negedge presetn) begin
	if(!presetn)
		apb_to_fifo <= 1'b0;
	else if((send_num!=32'd0) && (!send_finish))
		apb_to_fifo <= 1'b1;
	else
		apb_to_fifo <= 1'b0;
	end

	//iis send status (tx_fifo -> iis)
	always@(posedge pclk or negedge presetn) begin
	if(!presetn)
		fifo_to_iis <= 1'b0; 
	else if(tx_fifo_vaild && iis_tx_en)
		fifo_to_iis <= 1'b1;
	else
		fifo_to_iis <= 1'b0;
	end
	
	//iis receive status (iis -> rx_fifo)
	always@(posedge pclk or negedge presetn) begin
	if(!presetn)
		iis_to_fifo <= 1'b0;
	else if((receive_num!=32'd0) && (!receive_finish))
		iis_to_fifo <= 1'b1;
	else
		iis_to_fifo <= 1'b0;
	end

	//iis receive status (rx_fifo -> apb bus)
	always@(posedge pclk or negedge presetn) begin
	if(!presetn)
		fifo_to_apb <= 1'b0;
	else if(rx_fifo_vaild)
		fifo_to_apb <= 1'b1;
	else 
		fifo_to_apb <= 1'b0; 
	end
	
	//generate iis status for cpu
	assign iis_status = {apb_to_fifo,fifo_to_iis,iis_to_fifo,fifo_to_apb};
	
	//Generate interrupt state tx_fifo full
	always@(posedge pclk or negedge presetn) begin
	if(!presetn)
		tx_fifo_full_int <= 1'b0;
	else if(tx_fifo_full)
		tx_fifo_full_int <= 1'b1;
	else 
		tx_fifo_full_int <= 1'b0;
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
	
	//Generate interrupt signal
	assign irq = (tx_fifo_full_int  && !tx_fifo_full_mask)  ||
		     (rx_fifo_full_int  && !rx_fifo_full_mask);

	//write operation
	always@(posedge pclk or negedge presetn) begin
	if(!presetn) begin
		//reg <= initial
		iis_tx_en          <= 1'b0;
		iis_tx_ws          <= 1'b1;
		iis_rx_en          <= 1'b0;
		tx_fifo_en         <= 1'b0;
		pwdata_tx          <= 16'h0;
        	tx_fifo_full_mask  <= 1'b1; 
                rx_fifo_full_mask  <= 1'b1;
	end
	else if(apb_write) begin //write register
		case(paddr[11:0])
		IIS_TX_CONFIG: begin
			tx_fifo_en <= pwdata[3];
			iis_tx_ws  <= pwdata[1];
			iis_tx_en  <= pwdata[0];
		end
		IIS_RX_CONFIG:
			iis_rx_en <= pwdata[0];
		IIS_TX_FIFO:
			pwdata_tx <= pwdata[15:0];
		IIS_INTMASK: begin
                	tx_fifo_full_mask  <= pwdata[1]; 
                	rx_fifo_full_mask  <= pwdata[0];
		end
		default:;
		endcase
	end
	end	


	//read operation	
	always@(posedge pclk or negedge presetn) begin
	if(!presetn) 
		prdata <= 32'h0;
	else if(apb_read)
            case(paddr[11:0])
		IIS_STATUS: //i2s module status to cpu by apb bus
			prdata <= {28'b0,apb_to_fifo,fifo_to_iis,iis_to_fifo,fifo_to_apb};
		IIS_RX_FIFO: //apb read i2s receive data
			prdata <= {16'b0,rd_data};	
		IIS_INTERRUPT:
			prdata <= {30'b0,tx_fifo_full_int,rx_fifo_full_int}; //1 or 2
                default:;
            endcase
	end



endmodule

