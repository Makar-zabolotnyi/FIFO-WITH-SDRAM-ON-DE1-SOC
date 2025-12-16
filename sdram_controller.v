module sdram_controller #(
    parameter ROW_WIDTH = 13,
    parameter COL_WIDTH = 9,
    parameter BANK_WIDTH = 2,
    parameter HADDR_WIDTH = 24,
    // IS42S16320D-6TL timing parameters (at 50MHz = 20ns per cycle):
    // tRCD = 18ns = 1 cycle, but we use 2 for safety
    // tCAS = 3 cycles (CAS Latency for 50MHz)
    // tWR = 2 cycles
    // tRP = 18ns = 1 cycle, but we use 2 for safety
    parameter tRCD = 2,
    parameter tCAS = 3,
    parameter tWR  = 2,
    parameter tRP  = 2
)(
    input               clk,
    input               rst,
    input               wr_req,
    input [23:0]        wr_addr,
    input [15:0]        wr_data,
    output reg          wr_ack,
    input               rd_req,
    input [23:0]        rd_addr,
    output reg [15:0]   rd_data,
    output reg          rd_valid,

    output reg [12:0]   SDRAM_ADDR,
    output reg [1:0]    SDRAM_BA,
    inout [15:0]        SDRAM_DQ,
    output reg          SDRAM_WE_N,
    output reg          SDRAM_CAS_N,
    output reg          SDRAM_RAS_N,
    output reg [1:0]    SDRAM_DQM,
    output reg          SDRAM_CKE,
    output reg          SDRAM_CS_N
);

    reg [3:0] state;
    localparam IDLE=0, ACT=1, READ=2, WRITE=3, WAIT=4, PRE=5;

    reg drive_data;
    reg [15:0] data_out_reg;
    assign SDRAM_DQ = drive_data ? data_out_reg : 16'bz;

    reg [3:0] timer;

    reg have_wr, have_rd;
    reg [23:0] addr_latch;
    reg [15:0] wdata_latch;
    reg prev_wr_req, prev_rd_req;
    
    // Debug signals (calculated in sequential block)
    reg wr_edge, rd_edge;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            wr_ack <= 0;
            rd_valid <= 0;
            timer <= 0;
            drive_data <= 0;
            SDRAM_RAS_N <= 1;
            SDRAM_CAS_N <= 1;
            SDRAM_WE_N <= 1;
            SDRAM_CS_N <= 0;
            SDRAM_CKE <= 1;
            SDRAM_DQM <= 2'b11;  // Initialize disabled
            prev_wr_req = 0;
            prev_rd_req = 0;
            wr_edge = 0;
            rd_edge = 0;
        end else begin
            // Calculate edge detection BEFORE updating prev values
            wr_edge = wr_req && !prev_wr_req;
            rd_edge = rd_req && !prev_rd_req;
            
            // Update previous states for NEXT cycle
            prev_wr_req = wr_req;
            prev_rd_req = rd_req;
            
            // capture requests on rising edge
            if (state == IDLE) begin
                if (wr_edge) begin
                    have_wr <= 1;
                    have_rd <= 0;
                    addr_latch <= wr_addr;
                    wdata_latch <= wr_data;
                    state <= ACT;
                    timer <= tRCD;
                    SDRAM_RAS_N <= 0;  // Activate row immediately
                    SDRAM_CAS_N <= 1;
                    SDRAM_WE_N <= 1;
                    SDRAM_DQM <= 2'b11;
                    SDRAM_BA <= wr_addr[23:22];
                    SDRAM_ADDR <= wr_addr[21:9];
                end else if (rd_edge) begin
                    have_wr <= 0;
                    have_rd <= 1;
                    addr_latch <= rd_addr;
                    state <= ACT;
                    timer <= tRCD;
                    SDRAM_RAS_N <= 0;  // Activate row immediately
                    SDRAM_CAS_N <= 1;
                    SDRAM_WE_N <= 1;
                    SDRAM_DQM <= 2'b11;
                    SDRAM_BA <= rd_addr[23:22];
                    SDRAM_ADDR <= rd_addr[21:9];
                end else begin
                    // Stay in IDLE: maintain NOP commands
                    SDRAM_RAS_N <= 1;
                    SDRAM_CAS_N <= 1;
                    SDRAM_WE_N <= 1;
                    SDRAM_DQM <= 2'b11;
                    drive_data <= 0;
                end
            end

            // timer decrement
            if (timer > 0)
                timer <= timer - 1;

            // state machine
            case(state)
                IDLE: begin
                    // Handled above in the "if (state == IDLE)" section
                    // Do nothing here - state transitions already set above
                end
                ACT: begin
                    SDRAM_RAS_N <= 0;  // Keep row activation active
                    SDRAM_CAS_N <= 1;
                    SDRAM_WE_N <= 1;
                    SDRAM_DQM <= 2'b11;
                    if(timer==0) begin
                        state <= (have_wr ? WRITE : READ);
                        timer <= (have_wr ? tWR : tCAS);
                    end
                end
                WRITE: begin
                    drive_data <= 1;
                    data_out_reg <= wdata_latch;
                    SDRAM_RAS_N <= 1;  // End row activation
                    SDRAM_CAS_N <= 0;  // Column Select (write command)
                    SDRAM_WE_N <= 0;   // Write enable
                    SDRAM_DQM <= 2'b00;  // Enable both bytes (0 = write enabled)
                    // Keep BA and ADDR from ACT state
                    state <= WAIT;
                end
                READ: begin
                    SDRAM_RAS_N <= 1;  // End row activation
                    SDRAM_CAS_N <= 0;  // Column Select (read command)
                    SDRAM_WE_N <= 1;   // Read mode (WE_N high)
                    SDRAM_DQM <= 2'b00;  // Enable both bytes (0 = read enabled)
                    // Keep BA and ADDR from ACT state
                    state <= WAIT;
                end
                WAIT: begin
                    // Keep command signals stable during wait (NOP commands after write/read)
                    SDRAM_RAS_N <= 1;  // RAS = 1 (NOP)
                    SDRAM_CAS_N <= 1;  // CAS = 1 (NOP)
                    SDRAM_WE_N <= 1;   // WE = 1 (NOP)
                    SDRAM_DQM <= 2'b11;  // Disable (DQM = 1)
                    drive_data <= 0;   // Stop driving data
                    
                    if(timer==0) begin
                        if(have_wr) begin
                            wr_ack <= 1;
                        end else begin
                            rd_valid <= 1;
                            rd_data <= SDRAM_DQ;  // Capture read data from bus
                        end
                        // Go to precharge before idle
                        state <= PRE;
                        timer <= tRP;
                        have_wr <= 0;
                        have_rd <= 0;
                    end else begin
                        wr_ack <= 0;
                        rd_valid <= 0;
                    end
                end
                PRE: begin
                    // Precharge command
                    SDRAM_RAS_N <= 0;  // RAS = 0
                    SDRAM_CAS_N <= 1;  // CAS = 1
                    SDRAM_WE_N <= 0;   // WE = 0 (precharge)
                    SDRAM_ADDR[10] <= 1;  // A10 = 1 for all banks precharge
                    
                    if(timer==0) begin
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase

        end
    end

endmodule
