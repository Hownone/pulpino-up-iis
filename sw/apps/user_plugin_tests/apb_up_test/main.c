#include <stdio.h>
#include "int.h"
#include "event.h"
#include "user_plugin/apb.h"

#define IRQ_UP_IDX 22

// Must use volatile,
// because it is used to communicate between IRQ and main thread.
volatile int g_up_int_triggers = 0;

void ISR_UP() {
    // Clear interrupt within user plugin peripheral
    UP_APB_CMD = UP_CMD_CLR_INT_BIT;
    ICP = 1 << IRQ_UP_IDX;

    ++g_up_int_triggers;
    printf("In User Plugin interrupt\n");
}

void show_and_check_regs(int* errors, unsigned expected_ctrl, unsigned expected_status) {
    // cmd reg is always zero, when reading
    unsigned expected_cmd = 0;

    unsigned ctrl = UP_APB_CTRL;
    unsigned cmd = UP_APB_CMD;
    unsigned status = UP_APB_STATUS;

    printf("ctrl: 0x%X\n", ctrl);
    printf("cmd: 0x%X\n", cmd);
    printf("status: 0x%X\n", status);
    if (ctrl != expected_ctrl) {
        ++(*errors);
        printf("Expected ctrl reg: 0x%X, but got: 0x%X\n", expected_ctrl, ctrl);
    }
    if (cmd != expected_cmd) {
        ++(*errors);
        printf("Expected cmd reg: 0x%X, but got: 0x%X\n", expected_cmd, cmd);
    }
    if (status != expected_status) {
        ++(*errors);
        printf("Expected status reg: 0x%X, but got: 0x%X\n", expected_status, status);
    }
}

void check_ABS(int* errors) {
    UP_APB_A = 0x05;
    UP_APB_B = 0xA0;
    unsigned expected = 0x05 | 0xA0;

    unsigned a = UP_APB_A;
    unsigned b = UP_APB_B;
    unsigned s = UP_APB_S;

    printf("A = 0x%X, B = 0x%X, S = 0x%X\n", a, b, s);
    if (s != expected) {
        ++(*errors);
        printf("Expect 0x%X, but got 0x%X\n", expected, s);
    }
}

// Check ctrl / cmd / status regs behavior without irq.
void check_ccs_no_irq(int* errors) {
    printf("Initial ctrl/status values:\n");
    show_and_check_regs(errors, 0, 0);

    // Enable interrupt
    UP_APB_CTRL = UP_CTRL_INT_EN_BIT;
    printf("User Plugin Interrupt enabled\n");
    show_and_check_regs(errors, UP_CTRL_INT_EN_BIT, 0);;

    // Set interrupt pending
    UP_APB_CMD = UP_CMD_SET_INT_BIT;
    printf("User Plugin Interrupt pending set\n");
    show_and_check_regs(errors, UP_CTRL_INT_EN_BIT, UP_STATUS_INT_BIT);

    // Clear interrupt pending
    UP_APB_CMD = UP_CMD_CLR_INT_BIT;
    printf("User Plugin Interrupt pending set\n");
    show_and_check_regs(errors, UP_CTRL_INT_EN_BIT, 0);

    // Set interrupt pending
    UP_APB_CMD = UP_CMD_SET_INT_BIT;
    // Disable interrupt
    UP_APB_CTRL = 0;
    printf("User Plugin Interrupt pending set, but interrupt disabled\n");
    show_and_check_regs(errors, 0, UP_STATUS_INT_BIT);
}

// Check ctrl / cmd / status regs behavior with irq.
void check_ccs_irq(int* errors) {
    //
    // Make sure no irq pending
    //
    // Disable irq within user plugin peripherals.
    UP_APB_CTRL = 0;
    // Clear pending int
    UP_APB_CMD = UP_CMD_CLR_INT_BIT;

    //
    // Global enable User plugin interrupt
    //
    // Clear all events
    ECP = 0xFFFFFFFF;
    // Clear all interrupts
    ICP = 0xFFFFFFFF;
    int_enable();
    IER = IER | (1 << IRQ_UP_IDX); // Enable User plugin interrupt

    g_up_int_triggers = 0;

    // Enable interrupt within user plugin peripheral
    UP_APB_CTRL = UP_CTRL_INT_EN_BIT;
    // Set interrupt pending, and interrupt handler will be called.
    printf("User Plugin Interrupt has been enabled\n");
    printf("Going to set int pending bit, and int handler will be called\n");
    UP_APB_CMD = UP_CMD_SET_INT_BIT;
    // For zeroriscy cpu core, the interrupt is handled after one 'nop'.
    // For ri5cy cpu core, the interrupt is handled after two 'nop's.
    asm volatile("nop");
    asm volatile("nop");

    if (g_up_int_triggers != 1) {
        ++(*errors);
        printf("Expect to enter interrupt handler once, but actual number: %d\n", g_up_int_triggers);
    }
}

/*
  	Programming steps:
	1: continue send voice_data to tx_fifo from apb bus according tx_fifo address

	2: wait tx_fifo in full status, report interrupt to cpu

	3: configue iis send module and receive module ,then start it to send and receive data 
	 3.1:The sending module takes only a piece of data from tx_fifo and sends it out each time
	 3.2:The sending module can send the next a piece of data only when the "send_over" signals is vaild
	 3.3:The receive module receives continuous message
	
	4: wait rx_fifo in full status, report interrupt to cpu

	5: continue receive data from rx_fifo according rx_fifo address

	6: wait rx_fifo in empty status ,report interrupt to cpu
*/

int main(){
	int errors = 0;
	int out_voice = 0;
	int i=0;
	int j=0;int k=0;
	int voice_data[] = 
	{ 0x200, 0x203, 0x206, 0x209, 0x20d, 0x210, 0x213, 0x216, 0x219, 0x21c, 0x21f, 0x223, 
	  0x226, 0x229, 0x22c, 0x22f, 0x232, 0x235, 0x238, 0x23c, 0x23f, 0x242, 0x245, 0x248,
	  0x24b, 0x24e, 0x251, 0x254, 0x258, 0x25b, 0x25e, 0x261, 0x264, 0x267, 0x26a, 0x26d, 
	  0x270, 0x273, 0x276, 0x279, 0x27c, 0x27f, 0x282, 0x286, 0x289, 0x28c, 0x28f, 0x292,
	  0x295, 0x298, 0x29b, 0x29e, 0x2a1, 0x2a4, 0x2a7, 0x2aa, 0x2ac, 0x2af, 0x2b2, 0x2b5, 
	  0x2b8, 0x2bb, 0x2be, 0x2c1, 0x2c4, 0x2c7, 0x2ca, 0x2cd, 0x2cf, 0x2d2, 0x2d5, 0x2d8, 
	  0x2db, 0x2de, 0x2e1, 0x2e3, 0x2e6, 0x2e9, 0x2ec, 0x2ef, 0x2f1, 0x2f4, 0x2f7, 0x2fa, 
	  0x2fc, 0x2ff, 0x302, 0x305, 0x307, 0x30a, 0x30d, 0x30f, 0x312, 0x315, 0x317, 0x31a, 
	  0x31c, 0x31f, 0x322, 0x324, 0x327, 0x329, 0x32c, 0x32e, 0x331, 0x334, 0x336, 0x339, 
	  0x33b, 0x33d, 0x340, 0x342, 0x345, 0x347, 0x34a, 0x34c, 0x34e, 0x351, 0x353, 0x355, 
	  0x358, 0x35a, 0x35c, 0x35f, 0x361, 0x363, 0x366, 0x368
	};
	int voice_data2[] = {
	0x00, 0x02, 0x04, 0x06, 0x08, 0x0a, 0x0c, 0x0e, 0x10, 0x12, 0x14, 0x16, 0x18, 0x1a, 
	0x1c, 0x1e, 0x20, 0x22, 0x24, 0x26, 0x28, 0x2a, 0x2c, 0x2e, 0x30, 0x32, 0x34, 0x36,
	0x38, 0x3a, 0x3c, 0x3e, 0x40, 0x42, 0x44, 0x46, 0x48, 0x4a, 0x4c, 0x4e, 0x50, 0x52, 
	0x54, 0x56, 0x58, 0x5a, 0x5c, 0x5e, 0x60, 0x62, 0x64, 0x66, 0x68, 0x6a, 0x6c, 0x6e, 
	0x70, 0x72, 0x74, 0x76, 0x78, 0x7a, 0x7c, 0x7e, 0x80, 0x82, 0x84, 0x86, 0x88, 0x8a, 
	0x8c, 0x8e, 0x90, 0x92, 0x94, 0x96, 0x98, 0x9a, 0x9c, 0x9e, 0xa0, 0xa2, 0xa4, 0xa6, 
	0xa8, 0xaa, 0xac, 0xae, 0xb0, 0xb2, 0xb4, 0xb6, 0xb8, 0xba, 0xbc, 0xbe, 0xc0, 0xc2, 
	0xc4, 0xc6, 0xc8, 0xca, 0xcc, 0xce, 0xd0, 0xd2, 0xd4, 0xd6, 0xd8, 0xda, 0xdc, 0xde, 
	0xe0, 0xe2, 0xe4, 0xe6, 0xe8, 0xea, 0xec, 0xee, 0xf0, 0xf2, 0xf4, 0xf6, 0xf8, 0xfa, 
	0xfc, 0xfe, 										
	};
	//continue send voice_data to tx_fifo from apb bus according tx_fifo address
	//asm volatile("wfi");
	//wait tx_fifo full
	IIS_INTMASK_REG = 0x00;
	int flag = IIS_INTERRUPT_REG;
	int num = 0;
	IIS_TX_CONFIG_REG = 0x08; //0010->1010
	while( flag != 0x02 )
	{
		IIS_TX_FIFO_REG = voice_data[i];
		//printf("[%d]write once success\n",i);
		i++;   
		flag = IIS_INTERRUPT_REG; //read operation
		printf("[%d]flag=%d\n",i,flag);
	};
	
	asm volatile("wfi");
	printf("tx_fifo has full\n");	

	//configure iis send module and receive module ,then start it to send and receive data 
	
	IIS_TX_CONFIG_REG = 0x07; //first config send module ws signals 0111 -> close tx_fifo write operation

	printf("send module enable and ws signals has config\n");
	//IIS_RX_CONFIG_REG = 0x01;
	printf("receive module enable has config\n");
	
	while(flag!=1)
	{
		flag = IIS_INTERRUPT_REG; //read operation
		printf("flag=%d\n",flag);
	}
	printf("rx_fifo has full!!!\n");	
	IIS_TX_CONFIG_REG = 0x00;
	//IIS_RX_CONFIG_REG = 0x00;
	printf("send and receive module has close!\n");

	//asm volatile("wfi");	
	for(i=0;i<128;i++){
		out_voice = IIS_RX_FIFO_REG;
		printf("out_voice = %x\n",out_voice);
	}
	
	printf("The first transmit has complete!!\n");
	

	IIS_TX_CONFIG_REG = 0x08;
	while( flag != 0x02 )
	{
		IIS_TX_FIFO_REG = voice_data2[k];
		//printf("[%d]write once success\n",i);
		k++;   
		flag = IIS_INTERRUPT_REG; //read operation
		printf("[%d]flag=%d\n",k,flag);
	};
	
	asm volatile("wfi");
	printf("tx_fifo has full\n");	

	//configure iis send module and receive module ,then start it to send and receive data 
	
	IIS_TX_CONFIG_REG = 0x07; //first config send module ws signals 0111 -> close tx_fifo write operation

	printf("send module enable and ws signals has config\n");
	//IIS_RX_CONFIG_REG = 0x01;
	printf("receive module enable has config\n");
	
	while(flag!=1)
	{
		flag = IIS_INTERRUPT_REG; //read operation
		printf("flag=%d\n",flag);
	}
	printf("rx_fifo has full!!!\n");	
	IIS_TX_CONFIG_REG = 0x00;
	//IIS_RX_CONFIG_REG = 0x00;
	printf("send and receive module has close!\n");

	//asm volatile("wfi");	
	for(i=0;i<128;i++){
		out_voice = IIS_RX_FIFO_REG;
		printf("out_voice = %x\n",out_voice);
	}
	
	printf("The first transmit has complete!!\n");
	

    	//check_ABS(&errors);
   	// check_ccs_no_irq(&errors);
    	//check_ccs_irq(&errors);
    	return !(errors == 0);
}
