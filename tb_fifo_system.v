`timescale 1ns / 1ps

module tb_fifo_system();

    reg CLOCK_50;
    reg [3:0] SW;
    reg [3:0] KEY;
    wire [6:0] HEX0, HEX2, HEX4;
    wire [9:0] LEDR;

    // SDRAM pins
    wire [12:0] SDRAM_ADDR;
    wire [1:0]  SDRAM_BA;
    wire [15:0] SDRAM_DQ;
    wire        SDRAM_WE_N;
    wire        SDRAM_CAS_N;
    wire        SDRAM_RAS_N;
    wire [1:0]  SDRAM_DQM;
    wire        SDRAM_CKE;
    wire        SDRAM_CS_N;

    // clock generation 50MHz
    initial begin
        CLOCK_50 = 0;
        forever #10 CLOCK_50 = ~CLOCK_50;
    end

    // instantiate top module
    top_fifo_system uut(
        .CLOCK_50(CLOCK_50),
        .SW(SW),
        .KEY(KEY),
        .HEX0(HEX0),
        .HEX2(HEX2),
        .HEX4(HEX4),
        .LEDR(LEDR),
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

    // stimulus
    initial begin
        // Initialize
        KEY = 4'b1111;  // all inactive (KEY pulls down to activate)
        SW = 4'b0000;

        #40;  // wait 4 cycles

        // TEST 1: RESET
        $display("=== TEST 1: RESET ===");
        KEY[3] = 0;  // press RESET
        #40;
        KEY[3] = 1;  // release RESET
        #40;
        $display("After reset: SDRAM signals should idle");

        // TEST 2: Write 0x5 to FIFO
        $display("\n=== TEST 2: WRITE DATA 0x5 ===");
        SW = 4'b0101;  // input data 5
        #20;  // wait for SW to settle
        KEY[0] = 0;    // press WRITE
        #20;
        $display("Write request sent");
        
        KEY[0] = 1;    // release WRITE
        #400;  // wait for write to complete
        $display("Write completed");

        // TEST 3: Write 0xA to FIFO
        $display("\n=== TEST 3: WRITE DATA 0xA ===");
        SW = 4'b1010;  // input data A
        #20;
        KEY[0] = 0;    // press WRITE
        #20;
        KEY[0] = 1;
        #400;
        $display("Second write completed");

        // TEST 4: Read from FIFO
        $display("\n=== TEST 4: READ DATA ===");
        KEY[1] = 0;    // press READ
        #20;
        $display("Read request sent");
        
        KEY[1] = 1;    // release READ
        #400;
        $display("Read completed");

        #200;
        $finish;
    end

    // Monitor signals
    reg [31:0] state_val;
    reg [63:0] state_str;
    
    always @(posedge CLOCK_50) begin
        state_val = uut.u_mem.u_sdram.state;
        case(state_val)
            0: state_str = "IDLE";
            1: state_str = "ACT ";
            2: state_str = "READ";
            3: state_str = "WRT ";
            4: state_str = "WAIT";
            5: state_str = "PRE ";
            default: state_str = "????";
        endcase
        
        $display("[%tns] wr_in=%b rd_in=%b rst=%b | wr_req=%b rd_req=%b wr_edge=%b rd_edge=%b prev_wr=%b | state=%s | RAS=%b CAS=%b WE=%b DQM=%b | DQ=%h",
                 $time, uut.wr, uut.rd, uut.rst,
                 uut.u_mem.wr_req, uut.u_mem.rd_req, 
                 uut.u_mem.u_sdram.wr_edge, uut.u_mem.u_sdram.rd_edge,
                 uut.u_mem.u_sdram.prev_wr_req,
                 state_str,
                 SDRAM_RAS_N, SDRAM_CAS_N, SDRAM_WE_N, SDRAM_DQM,
                 SDRAM_DQ);
    end

endmodule
