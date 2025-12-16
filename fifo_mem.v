module fifo_mem(
    input        clk,
    input        rst,
    input        we,
    input [ADDR-1:0]  addr_wr,
    input [ADDR-1:0]  addr_rd,
    input [4:0]  data_in,
    output reg [4:0] data_out
);

parameter       ADDR = 4;

    reg [ADDR:0] mem [0:15];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1)
                mem[i] <= 4'b0000;
            data_out <= 0;
        end
        else begin
            if (we)
                mem[addr_wr] <= data_in;

            data_out <= mem[addr_rd];
        end
    end

endmodule
