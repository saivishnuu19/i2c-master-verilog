`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// Self-checking testbench for i2c_master
//   Test 1: write 0xA5 to slave 0x50    -> expect ACK, slave receives 0xA5
//   Test 2: write to wrong address 0x2A -> expect ack_error = 1
// -----------------------------------------------------------------------------
module tb_i2c_master;

    localparam [6:0] SLAVE_ADDR = 7'h50;

    reg        clk = 0;
    reg        rst_n = 0;
    reg        start = 0;
    reg  [6:0] addr;
    reg  [7:0] data;
    wire       busy, done, ack_error, scl;
    wire       sda;

    pullup(sda);   // I2C bus pull-up

    i2c_master #(.CLK_FREQ(50_000_000), .I2C_FREQ(100_000)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .addr(addr), .data(data),
        .busy(busy), .done(done), .ack_error(ack_error),
        .scl(scl), .sda(sda)
    );

    always #10 clk = ~clk;   // 50 MHz

    // ---------------- Simple behavioural I2C slave ----------------
    reg       slave_pull_low = 0;
    reg       in_xfer = 0;
    reg       matched = 0;
    reg [3:0] bitcnt  = 0;
    reg [1:0] byte_n  = 0;
    reg [7:0] rx      = 0;
    reg [7:0] slave_data = 8'h00;

    assign sda = slave_pull_low ? 1'b0 : 1'bz;

    always @(negedge sda) if (scl === 1'b1) begin   // START
        in_xfer <= 1; bitcnt <= 0; byte_n <= 0; matched <= 0;
    end
    always @(posedge sda) if (scl === 1'b1) in_xfer <= 0;   // STOP

    always @(posedge scl) if (in_xfer && bitcnt < 8) begin
        rx     <= {rx[6:0], sda};
        bitcnt <= bitcnt + 1;
    end

    always @(negedge scl) if (in_xfer) begin
        if (bitcnt == 8) begin
            if (byte_n == 0) begin
                matched        <= (rx[7:1] == SLAVE_ADDR) && (rx[0] == 1'b0);
                slave_pull_low <= (rx[7:1] == SLAVE_ADDR) && (rx[0] == 1'b0);
            end else begin
                slave_pull_low <= matched;
                if (matched) slave_data <= rx;
            end
            bitcnt <= 9;
        end else if (bitcnt == 9) begin
            slave_pull_low <= 0;
            bitcnt <= 0;
            byte_n <= byte_n + 1;
        end
    end

    // ---------------- Stimulus ----------------
    integer errors = 0;

    task i2c_write(input [6:0] a, input [7:0] d);
    begin
        @(posedge clk);
        addr  <= a;
        data  <= d;
        start <= 1;
        @(posedge clk);
        start <= 0;
        wait (done);
        @(posedge clk);
    end
    endtask

    initial begin
        $dumpfile("i2c_master.vcd");
        $dumpvars(0, tb_i2c_master);

        #100 rst_n = 1;
        #100;

        // Test 1: valid address
        i2c_write(SLAVE_ADDR, 8'hA5);
        if (ack_error !== 1'b0)        begin $display("FAIL T1: unexpected NACK"); errors = errors + 1; end
        else if (slave_data !== 8'hA5) begin $display("FAIL T1: slave got %h", slave_data); errors = errors + 1; end
        else $display("PASS T1: wrote 0xA5 to 0x%h, ACK received, slave data = 0x%h", SLAVE_ADDR, slave_data);

        #5000;

        // Test 2: wrong address -> NACK expected
        i2c_write(7'h2A, 8'h3C);
        if (ack_error !== 1'b1) begin $display("FAIL T2: expected NACK"); errors = errors + 1; end
        else $display("PASS T2: wrong address correctly NACKed (ack_error = 1)");

        #5000;
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

    // Timeout guard
    initial begin
        #5_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
