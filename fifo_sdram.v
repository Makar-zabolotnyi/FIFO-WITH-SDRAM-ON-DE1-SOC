module fifo_sdram #(
    parameter ADDR = 4,
    parameter DATA_WIDTH = 4
)(
    input                      clk,
    input                      rst,
    input                      we,
    input      [ADDR-1:0]      addr_wr,
    input      [ADDR-1:0]      addr_rd,
    input      [DATA_WIDTH-1:0] data_in,
    output reg [DATA_WIDTH-1:0] data_out,

    // Physical SDRAM pins passthrough
    output [12:0] SDRAM_ADDR,
    output [1:0]  SDRAM_BA,
    inout  [15:0] SDRAM_DQ,
    output        SDRAM_WE_N,
    output        SDRAM_CAS_N,
    output        SDRAM_RAS_N,
    output [1:0]  SDRAM_DQM,
    output        SDRAM_CKE,
    output        SDRAM_CS_N
);

    // signals to talk to sdram_controller
    reg         wr_req, rd_req;
    reg [23:0]  req_addr;
    reg [15:0]  req_wdata;
    wire        wr_ack;
    wire [15:0] rdata;
    wire        rvalid;

    // instantiate controller
    sdram_controller u_sdram (
        .clk(clk),
        .rst(rst),
        .wr_req(wr_req),
        .wr_addr(req_addr),
        .wr_data(req_wdata),
        .wr_ack(wr_ack),
        .rd_req(rd_req),
        .rd_addr(req_addr),
        .rd_data(rdata),
        .rd_valid(rvalid),
        .SDRAM_ADDR(SDRAM_ADDR),
        .SDRAM_BA(SDRAM_BA),
        .SDRAM_DQ(SDRAM_DQ),
        .SDRAM_WE_N(SDRAM_WE_N),
        .SDRAM_CAS_N(SDRAM_CAS_N),
        .SDRAM_RAS_N(SDRAM_RAS_N),
        .SDRAM_DQM(SDRAM_DQM),
        .SDRAM_CKE(SDRAM_CKE),
        .SDRAM_CS_N(SDRAM_CS_N)
    );

    // map small FIFO address into SDRAM linear word address
    // SDRAM address format: [23:22]=BA[1:0], [21:9]=ADDR[12:0], [8:0]=column
    // We use bits [12:9] of SDRAM_ADDR for our 4-bit FIFO address
    function [23:0] map_addr;
        input [ADDR-1:0] a;
        begin
            // Place FIFO address [3:0] into SDRAM_ADDR[12:9]
            // This gives unique row/column combinations for each FIFO address
            map_addr = {20'd0, a, 9'd0}; // a[3:0] in bits [12:9], 9 zeros for column
        end
    endfunction

    // simple handshake flags
    reg write_in_progress, read_in_progress;
    reg [ADDR-1:0] last_addr_rd;

    always @(posedge clk) begin
        if (rst) begin
            wr_req <= 0;
            rd_req <= 0;
            req_addr <= 0;
            req_wdata <= 0;
            write_in_progress <= 0;
            read_in_progress <= 0;
            data_out <= 0;
            last_addr_rd <= 0;
        end else begin
            // WRITE - keep request until ack
            if (we && !write_in_progress && !read_in_progress) begin
                wr_req <= 1;
                req_addr <= map_addr(addr_wr);
                req_wdata <= { {(16-DATA_WIDTH){1'b0}}, data_in };
                write_in_progress <= 1;
            end
            if (write_in_progress && wr_ack) begin
                wr_req <= 0;
                write_in_progress <= 0;
            end

            // READ - keep request until valid, only request when address changes
            if (!write_in_progress && !read_in_progress && (addr_rd != last_addr_rd)) begin
                rd_req <= 1;
                req_addr <= map_addr(addr_rd);
                read_in_progress <= 1;
                last_addr_rd <= addr_rd;
            end
            if (read_in_progress && rvalid) begin
                rd_req <= 0;
                data_out <= rdata[DATA_WIDTH-1:0];
                read_in_progress <= 0;
            end
        end
    end

endmodule
