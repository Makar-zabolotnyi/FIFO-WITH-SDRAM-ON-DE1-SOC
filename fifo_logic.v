// fifo_logic.v
module fifo_logic(
    input clk,
    input rst,
    input wr,
    input rd,
    output reg [ADDR-1:0] wr_addr = 0,
    output reg [ADDR-1:0] rd_addr = 0
);

parameter       ADDR = 4;

    always @(posedge clk) begin
        if (rst) begin
            wr_addr <= 0;
            rd_addr <= 0;
        end
        else begin
            if (wr)
                wr_addr <= wr_addr + 1;

            if (rd)
                rd_addr <= rd_addr + 1;
        end
    end

endmodule
