module gray2bin#(
	parameter addr_width = 10
)
(
	input [addr_width-1:0] gray,
	input [addr_width-1:0] binary
)
;
	integer i;
	always@(gray) begin
		binary[addr_width-1] = gray[addr_width-1];
		for(i=addr_width-2;i>=0;i=i-1)
		binary[i] = binary[i+1] ^ gray[i];
	end

endmodule
