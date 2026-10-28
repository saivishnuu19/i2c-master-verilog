// -----------------------------------------------------------------------------
// i2c_master.v : Simple I2C master (single-byte write)
//   - 7-bit addressing, write transaction: START | ADDR+W | ACK | DATA | ACK | STOP
//   - Open-drain SDA, SCL driven by the master
//   - Parameterised system clock and I2C clock (default 50 MHz -> 100 kHz)
//   - ack_error is set if the slave NACKs the address or the data byte
// -----------------------------------------------------------------------------
module i2c_master #(
    parameter CLK_FREQ = 50_000_000,
    parameter I2C_FREQ = 100_000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,      // pulse for 1 clk when !busy to begin a write
    input  wire [6:0] addr,       // 7-bit slave address
    input  wire [7:0] data,       // byte to write
    output reg        busy,
    output reg        done,       // 1-clk pulse when transaction finishes
    output reg        ack_error,  // 1 = slave did not acknowledge
    output wire       scl,
    inout  wire       sda
);

    // One I2C bit = 4 phases, so tick every DIV system clocks
    localparam DIV = CLK_FREQ / (I2C_FREQ * 4);

    localparam [2:0] IDLE     = 3'd0,
                     START    = 3'd1,
                     ADDR     = 3'd2,
                     ADDR_ACK = 3'd3,
                     DATA     = 3'd4,
                     DATA_ACK = 3'd5,
                     STOP     = 3'd6;

    reg [2:0]  state;
    reg [15:0] cnt;
    reg [1:0]  phase;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;
    reg [7:0]  addr_byte;
    reg [7:0]  data_r;
    reg        scl_r;   // 1 = released (high)
    reg        sda_r;   // 1 = released (high)

    // Open-drain outputs
    assign scl = scl_r ? 1'b1 : 1'b0;
    assign sda = sda_r ? 1'bz : 1'b0;
    wire sda_in = sda;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            cnt       <= 0;
            phase     <= 0;
            bit_idx   <= 0;
            shreg     <= 0;
            addr_byte <= 0;
            data_r    <= 0;
            scl_r     <= 1'b1;
            sda_r     <= 1'b1;
            busy      <= 1'b0;
            done      <= 1'b0;
            ack_error <= 1'b0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                if (start) begin
                    addr_byte <= {addr, 1'b0};   // R/W = 0 (write)
                    data_r    <= data;
                    ack_error <= 1'b0;
                    busy      <= 1'b1;
                    state     <= START;
                    cnt       <= 0;
                    phase     <= 0;
                end
            end else if (cnt == DIV-1) begin
                cnt   <= 0;
                phase <= phase + 1'b1;

                case (state)
                    // ---------------- START condition ----------------
                    START: case (phase)
                        2'd0: begin scl_r <= 1; sda_r <= 1; end
                        2'd1: sda_r <= 0;                       // SDA falls while SCL high
                        2'd3: begin
                            scl_r   <= 0;
                            shreg   <= addr_byte;
                            bit_idx <= 3'd7;
                            state   <= ADDR;
                        end
                    endcase

                    // ---------------- Address byte (MSB first) ----------------
                    ADDR: case (phase)
                        2'd0: begin scl_r <= 0; sda_r <= shreg[bit_idx]; end
                        2'd1: scl_r <= 1;
                        2'd3: begin
                            scl_r <= 0;
                            if (bit_idx == 0) state <= ADDR_ACK;
                            else              bit_idx <= bit_idx - 1'b1;
                        end
                    endcase

                    // ---------------- Address ACK ----------------
                    ADDR_ACK: case (phase)
                        2'd0: begin scl_r <= 0; sda_r <= 1; end   // release SDA
                        2'd1: scl_r <= 1;
                        2'd2: if (sda_in) ack_error <= 1'b1;      // sample ACK (0 = ACK)
                        2'd3: begin
                            scl_r <= 0;
                            if (ack_error) state <= STOP;
                            else begin
                                shreg   <= data_r;
                                bit_idx <= 3'd7;
                                state   <= DATA;
                            end
                        end
                    endcase

                    // ---------------- Data byte (MSB first) ----------------
                    DATA: case (phase)
                        2'd0: begin scl_r <= 0; sda_r <= shreg[bit_idx]; end
                        2'd1: scl_r <= 1;
                        2'd3: begin
                            scl_r <= 0;
                            if (bit_idx == 0) state <= DATA_ACK;
                            else              bit_idx <= bit_idx - 1'b1;
                        end
                    endcase

                    // ---------------- Data ACK ----------------
                    DATA_ACK: case (phase)
                        2'd0: begin scl_r <= 0; sda_r <= 1; end
                        2'd1: scl_r <= 1;
                        2'd2: if (sda_in) ack_error <= 1'b1;
                        2'd3: begin scl_r <= 0; state <= STOP; end
                    endcase

                    // ---------------- STOP condition ----------------
                    STOP: case (phase)
                        2'd0: begin scl_r <= 0; sda_r <= 0; end
                        2'd1: scl_r <= 1;
                        2'd2: sda_r <= 1;                         // SDA rises while SCL high
                        2'd3: begin
                            state <= IDLE;
                            busy  <= 1'b0;
                            done  <= 1'b1;
                        end
                    endcase

                    default: state <= IDLE;
                endcase
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end

endmodule
