
module user_plugin
(
    // Common clk/rst
    input logic        clk_i,
    input logic        rst_n,

    APB_BUS.Slave      apb_slv,
    AXI_BUS.Slave      axi_slv,
    AXI_BUS.Master     axi_mstr,
	

    input logic  [7:0] upio_in_i,
    output logic [7:0] upio_out_o,
    output logic [7:0] upio_dir_o,

    // Interupt signal
    output logic  int_o
);  

    logic apb_up_int_o;
    logic axi_up_int_o;

    assign int_o = apb_up_int_o | axi_up_int_o;

    apb_iis apb_iis_up
    (
        .pclk       ( clk_i               ),
        .presetn    ( rst_n               ),

        .paddr      ( apb_slv.paddr    ),
        .pwdata     ( apb_slv.pwdata      ),
        .pwrite     ( apb_slv.pwrite      ),
        .psel       ( apb_slv.psel        ),
        .penable    ( apb_slv.penable     ),
        .prdata     ( apb_slv.prdata      ),
        .pready     ( apb_slv.pready      ),
        .pslverr    ( apb_slv.pslverr     ),
        .irq        ( apb_up_int_o        ),
	
	.upio_in_i  ( upio_in_i           ),
    	.upio_out_o ( upio_out_o          ),
    	.upio_dir_o ( upio_dir_o          )

    );

    axi_up axi_up_i
    (
        .ACLK    ( clk_i        ),
        .ARESETn ( rst_n        ),
        .slv     ( axi_slv      ),
        .mstr    ( axi_mstr     ),
        .int_o   ( axi_up_int_o )
    );

endmodule
