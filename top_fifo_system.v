// top_fifo_system.v (updated: expose SDRAM pins)
module top_fifo_system(
    CLOCK_50, SW, KEY, HEX0, HEX2, HEX4, HEX5, LEDR,
    // SDRAM pins
    SDRAM_ADDR, SDRAM_BA, SDRAM_DQ, SDRAM_WE_N, SDRAM_CAS_N, SDRAM_RAS_N, SDRAM_DQM, SDRAM_CKE, SDRAM_CS_N, SDRAM_CLK
);

    parameter N = 4;

    input         CLOCK_50;
    input  [N-1:0]  SW;
    input  [3:0]  KEY;    // KEY0 write, KEY1 read, KEY3 reset
    output [6:0]  HEX0, HEX2, HEX4, HEX5;
    output [9:0]  LEDR;

    // SDRAM pins
    output [12:0] SDRAM_ADDR;
    output [1:0]  SDRAM_BA;
    inout  [15:0] SDRAM_DQ;
    output        SDRAM_WE_N;
    output        SDRAM_CAS_N;
    output        SDRAM_RAS_N;
    output [1:0]  SDRAM_DQM;
    output        SDRAM_CKE;
    output        SDRAM_CS_N;
    output        SDRAM_CLK;

    wire rst = ~KEY[3];       // RESET FIFO
    wire wr_raw = ~KEY[0];    // WRITE
    wire rd_raw = ~KEY[1];    // READ

    // --- Synchronize asynchronous inputs (2-stage synchronizer) ---
    // This prevents metastability issues with asynchronous button presses
    reg [2:0] wr_sync, rd_sync;
    reg [15:0] wr_debounce, rd_debounce;
    
    always @(posedge CLOCK_50) begin
        // First stage: capture asynchronous input
        wr_sync[0] <= wr_raw;
        rd_sync[0] <= rd_raw;
        // Second stage: synchronized version
        wr_sync[1] <= wr_sync[0];
        rd_sync[1] <= rd_sync[0];
        // Third stage: for edge detection
        wr_sync[2] <= wr_sync[1];
        rd_sync[2] <= rd_sync[1];
    end

    // Debounce counter
    // Counts up while button is pressed, generates stable signal after 2000 cycles
    always @(posedge CLOCK_50) begin
        if (!wr_sync[1]) begin
            wr_debounce <= 16'd0;  // Button released, reset counter
        end else if (wr_debounce < 16'd2000) begin
            wr_debounce <= wr_debounce + 1;  // Count up while pressed
        end
        
        if (!rd_sync[1]) begin
            rd_debounce <= 16'd0;  // Button released, reset counter
        end else if (rd_debounce < 16'd2000) begin
            rd_debounce <= rd_debounce + 1;  // Count up while pressed
        end
    end

    // Edge detection: Generate ONE-CYCLE pulse when debounce threshold is crossed
    // Store previous debounce state to detect rising edge
    reg wr_stable_prev, rd_stable_prev;
    always @(posedge CLOCK_50) begin
        wr_stable_prev <= (wr_debounce >= 16'd2000);  // Store previous state
        rd_stable_prev <= (rd_debounce >= 16'd2000);  // Store previous state
    end

    // Pulse generated only on rising edge: 0→1 transition
    wire wr_stable = (wr_debounce >= 16'd2000);
    wire rd_stable = (rd_debounce >= 16'd2000);
    wire wr = wr_stable && !wr_stable_prev;  // Edge detection: HIGH only 1 cycle
    wire rd = rd_stable && !rd_stable_prev;  // Edge detection: HIGH only 1 cycle

    // FIFO signals
    wire [N-1:0] wr_addr, rd_addr;
    wire [N-1:0] fifo_out;

    // Memory -> replaced with SDRAM-backed FIFO memory
    fifo_sdram #(.ADDR(N), .DATA_WIDTH(N)) u_mem(
        .clk(CLOCK_50),
        .rst(rst),
        .we(wr),
        .addr_wr(wr_addr),
        .addr_rd(rd_addr),
        .data_in(SW),
        .data_out(fifo_out),

        // connect SDRAM pins through top-level
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

    // Logic
    fifo_logic #(.ADDR(N)) u_logic(
        .clk(CLOCK_50),
        .rst(rst),
        .wr(wr),
        .rd(rd),
        .wr_addr(wr_addr),
        .rd_addr(rd_addr)
    );

    // HEX display assignments
    // HEX0: value read from current read address
    hex_decoder HEX0_hex(
        .num(fifo_out[3:0]),  // Extract only 4 bits of read data
        .segments(HEX0)
    );

    // HEX2: current read address
    hex_decoder HEX2_hex(
        .num(rd_addr),
        .segments(HEX2)
    );

    // HEX4: value to be written (from switches)
    hex_decoder HEX4_hex(
        .num(SW[3:0]),
        .segments(HEX4)
    );

    // HEX5: current write address
    hex_decoder HEX5_hex(
        .num(wr_addr),
        .segments(HEX5)
    );

    assign LEDR[N-1:0] = SW;
    assign LEDR[9:N] = 0;
    
    // SDRAM clock - direct passthrough
    assign SDRAM_CLK = CLOCK_50;

endmodule
