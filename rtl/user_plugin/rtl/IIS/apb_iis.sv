module apb_iis(
    input  logic              pclk,
    input  logic              presetn,
    input  logic              penable,
    input  logic              psel,
    input  logic              pwrite,
    input  logic [31:0]       paddr,
    input  logic [31:0]       pwdata,
    output logic [31:0]       prdata,
    output logic              pready,
    output logic              pslverr,
    output logic              irq,    // interrupt signals

    // iis send
    input  logic              sck_i,
    input  logic              ws_i,
    input  logic              sd_i,

    // iis receive
    output logic              sck_o,
    output logic              ws_o,
    output logic              sd_o
);

    // 内部信号声明
    logic        sck;
    logic        ws;
    logic        sd;
    
    logic        apb_write;
    logic        apb_read;
    
    logic        tx_fifo_rdclk;
    logic        tx_fifo_rden;
    logic        tx_fifo_vaild;
    logic        tx_fifo_empty;
    logic        tx_fifo_full;
    logic [15:0] send_data;
    
    logic        rx_fifo_wrclk;
    logic        rx_fifo_wren;
    logic        rx_fifo_vaild;
    logic        rx_fifo_empty;
    logic        rx_fifo_full;

    logic [15:0] receive_data;
    logic [3:0]  iis_tx_config;
    logic [3:0]  iis_status;
    logic [15:0] rd_data; // 从 rx_fifo 到 apb
    logic [31:0] receive_num;
    logic [31:0] send_num;

    // 寄存器地址参数
    localparam logic [11:0] IIS_TX_CONFIG = 12'h30, // iis tx 配置寄存器
                         IIS_RX_CONFIG = 12'h34, // iis rx 配置寄存器
                         IIS_INTMASK   = 12'h38, // 中断屏蔽寄存器
                         IIS_STATUS    = 12'h3C, // 状态寄存器
                         IIS_TX_FIFO   = 12'h40, // apb -> tx_fifo 数据
                         IIS_RX_FIFO   = 12'h44, // apb <- rx_fifo 数据
                         IIS_INTERRUPT = 12'h48; // 中断寄存器

    // 使能寄存器
    logic        iis_tx_en;
    logic        iis_tx_ws;
    logic [15:0] pwdata_tx;
    logic        iis_rx_en;
    logic        tx_fifo_en; // tx_fifo 开始写操作

    // 状态寄存器
    logic apb_to_fifo; // apb 总线数据 -> tx_fifo
    logic fifo_to_iis; // tx_fifo 数据 -> iis send 模块
    logic iis_to_fifo; // iis receive 数据 -> fifo
    logic fifo_to_apb; // rx_fifo 数据 -> apb 总线

    // 中断寄存器屏蔽
    logic tx_fifo_full_mask;
    logic rx_fifo_full_mask;
    
    // 中断寄存器状态
    logic tx_fifo_full_int;
    logic rx_fifo_full_int;
    
    // 生成 APB 写/读信号
    assign apb_write = pwrite && psel && penable;
    assign apb_read  = (!pwrite) && psel && penable;
    
    assign tx_fifo_wren = tx_fifo_en && apb_write && (!tx_fifo_full) && (!fifo_to_iis);
    assign rx_fifo_rden = apb_read  && (!rx_fifo_empty);

    assign iis_tx_config = {tx_fifo_en, 1'b1, iis_tx_ws, iis_tx_en};
    assign pready = 1'b1;
    assign pslverr = 1'b0;

    // 实例化模块
    async_fifo #(
        .data_width(16),
        .data_depth(128),
        .addr_width(7)
    ) tx_fifo (
        .rst(presetn),
        .wr_clk(pclk),
        .wr_en(tx_fifo_wren),
        .din(pwdata_tx),
        .rd_clk(tx_fifo_rdclk),
        .rd_en(tx_fifo_rden),
        .vaild(tx_fifo_vaild),
        .dout(send_data),
        .empty(tx_fifo_empty),
        .full(tx_fifo_full)
    );

    IIS_SEND #(
        .data_depth(128)
    ) IIS_SEND (
        .clk_in(pclk),
        .data_in(send_data),
        .rst(presetn),
        .send_ctrl(iis_tx_config[2:0]),
        .data(sd),
        .WS_reg(ws),
        .sck(sck),
        .rd_clk(tx_fifo_rdclk),
        .fifo_rden(tx_fifo_rden),
        .send_num(send_num),
        .send_finish(send_finish)
    );

    IIS_RECEIVE #(
        .data_depth(128)
    ) IIS_RECEIVE (
        .rst(presetn),
        .clk(sck),
        .WS_r(ws),
        .DATA(sd),
        .rx_en(iis_tx_config[0] && (!rx_fifo_full)),
        .wr_clk(rx_fifo_wrclk),
        .L_DATA(),
        .R_DATA(),
        .SDATA(receive_data),
        .fifo_wren(rx_fifo_wren),
        .receive_num(receive_num),
        .receive_finish(receive_finish)
    );

    async_fifo #(
        .data_width(16),
        .data_depth(128),
        .addr_width(7)
    ) rx_fifo (
        .rst(presetn),
        .wr_clk(rx_fifo_wrclk),
        .wr_en(rx_fifo_wren),
        .din(receive_data),
        .rd_clk(pclk),
        .rd_en(rx_fifo_rden),
        .vaild(rx_fifo_vaild),
        .dout(rd_data),
        .empty(rx_fifo_empty),
        .full(rx_fifo_full)
    );
    
    assign sck_o = sck;
    assign ws_o  = ws;
    assign sd_o  = sd;

    // iis send 状态 (apb 总线 -> tx_fifo)
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn)
            apb_to_fifo <= 1'b0;
        else if((!iis_tx_en) && (!tx_fifo_empty))
            apb_to_fifo <= 1'b1;
        else
            apb_to_fifo <= 1'b0;
    end

    // iis send 状态 (tx_fifo -> iis)
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn)
            fifo_to_iis <= 1'b0;
        else if(tx_fifo_vaild && iis_tx_en)
            fifo_to_iis <= 1'b1;
        else
            fifo_to_iis <= 1'b0;
    end

    // iis receive 状态 (iis -> rx_fifo)
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn)
            iis_to_fifo <= 1'b0;
        else if((receive_num != 32'd0) && (!receive_finish))
            iis_to_fifo <= 1'b1;
        else
            iis_to_fifo <= 1'b0;
    end

    // iis receive 状态 (rx_fifo -> apb 总线)
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn)
            fifo_to_apb <= 1'b0;
        else if(rx_fifo_vaild)
            fifo_to_apb <= 1'b1;
        else
            fifo_to_apb <= 1'b0;
    end

    // 生成 iis 状态信号供 CPU 读取
    assign iis_status = {apb_to_fifo, fifo_to_iis, iis_to_fifo, fifo_to_apb};

    // 生成中断状态: tx_fifo 满
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn)
            tx_fifo_full_int <= 1'b0;
        else if (tx_fifo_full)
            tx_fifo_full_int <= 1'b1;
        else
            tx_fifo_full_int <= 1'b0;
    end

    // 生成中断状态: rx_fifo 满
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn)
            rx_fifo_full_int <= 1'b0;
        else if (rx_fifo_full)
            rx_fifo_full_int <= 1'b1;
        else
            rx_fifo_full_int <= 1'b0;
    end

    // 生成中断信号
    assign irq = (tx_fifo_full_int && !tx_fifo_full_mask) ||
                 (rx_fifo_full_int && !rx_fifo_full_mask);

    // 写操作
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            iis_tx_en         <= 1'b0;
            iis_tx_ws         <= 1'b1;
            iis_rx_en         <= 1'b0;
            tx_fifo_en        <= 1'b0;
            pwdata_tx         <= 16'h0;
            tx_fifo_full_mask <= 1'b1;
            rx_fifo_full_mask <= 1'b1;
        end
        else if (apb_write) begin
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
                    tx_fifo_full_mask <= pwdata[1];
                    rx_fifo_full_mask <= pwdata[0];
                end
                default: ;
            endcase
        end
    end

    // 读操作
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn)
            prdata <= 32'h0;
        else if (apb_read) begin
            case(paddr[11:0])
                IIS_STATUS: // iis 状态寄存器
                    prdata <= {28'b0, apb_to_fifo, fifo_to_iis, iis_to_fifo, fifo_to_apb};
                IIS_RX_FIFO: // 读取 iis 接收数据
                    prdata <= {16'b0, rd_data};
                IIS_INTERRUPT:
                    prdata <= {30'b0, tx_fifo_full_int, rx_fifo_full_int};
                default: ;
            endcase
        end
    end

endmodule

