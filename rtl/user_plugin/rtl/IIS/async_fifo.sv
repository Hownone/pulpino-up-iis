module async_fifo #(
    parameter int data_width = 16,
    parameter int data_depth = 1024,
    parameter int addr_width = 10
)
(
    input  logic                      rst,
    input  logic                      wr_clk,
    input  logic                      wr_en,
    input  logic [data_width-1:0]     din,
    input  logic                      rd_clk,
    input  logic                      rd_en,
    output logic                      vaild, // 数据有效信号（注意拼写与原代码保持一致）
    output logic [data_width-1:0]     dout,
    output logic                      empty,
    output logic                      full
);

    // 指针宽度为 addr_width+1，用于检测溢出/空情况
    logic [addr_width:0] wr_addr_ptr, rd_addr_ptr;
    // 用于 RAM 访问的地址：取低 addr_width 位
    logic [addr_width-1:0] wr_addr, rd_addr;

    // 灰码指针：用于跨时钟域同步
    logic [addr_width:0] wr_addr_gray, rd_addr_gray;
    logic [addr_width:0] rd_addr_gray_d1, rd_addr_gray_d2;
    logic [addr_width:0] wr_addr_gray_d1, wr_addr_gray_d2;

    // 内部 FIFO 存储阵列
    logic [data_width-1:0] fifo_ram [0:data_depth-1];

    // 写地址生成与写操作
    always_ff @(posedge wr_clk or negedge rst) begin
        if (!rst)
            wr_addr_ptr <= '0;
        else if (wr_en && !full) begin
            fifo_ram[wr_addr] <= din;
            wr_addr_ptr <= wr_addr_ptr + 1'b1;
        end
    end

    // 读地址生成与读操作
    always_ff @(posedge rd_clk or negedge rst) begin
        if (!rst) begin
            rd_addr_ptr <= '0;
            dout <= '0;
            vaild <= 1'b0;
        end
        else if (rd_en && !empty) begin
            dout <= fifo_ram[rd_addr];
            rd_addr_ptr <= rd_addr_ptr + 1'b1;
            vaild <= 1'b1;
        end
        else begin
            vaild <= 1'b0;
        end
    end

    // 提取 RAM 读写地址（低 addr_width 位）
    assign wr_addr = wr_addr_ptr[addr_width-1:0];
    assign rd_addr = rd_addr_ptr[addr_width-1:0];

    // 灰码转换
    assign wr_addr_gray = (wr_addr_ptr >> 1) ^ wr_addr_ptr;
    assign rd_addr_gray = (rd_addr_ptr >> 1) ^ rd_addr_ptr;

    // 在写时钟域中同步读指针灰码
    always_ff @(posedge wr_clk) begin
        rd_addr_gray_d1 <= rd_addr_gray;
        rd_addr_gray_d2 <= rd_addr_gray_d1;
    end

    // 在读时钟域中同步写指针灰码
    always_ff @(posedge rd_clk) begin
        wr_addr_gray_d1 <= wr_addr_gray;
        wr_addr_gray_d2 <= wr_addr_gray_d1;
    end

    // full 信号检测（写时钟域）
    // 此处采用原始代码中的判断方法：
    assign full = (wr_addr_gray == { ~ (rd_addr_gray_d2[addr_width -: 2]),
                                      rd_addr_gray_d2[addr_width-2:0] });

    // empty 信号检测（读时钟域）
    assign empty = (rd_addr_gray == wr_addr_gray_d2);

endmodule
