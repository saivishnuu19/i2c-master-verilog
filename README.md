# I2C Master Controller (Verilog)

A simple, synthesizable **I2C master** in Verilog that performs a single-byte write to a 7-bit addressed slave. Includes a self-checking testbench with a behavioural slave model.

## Features
- 7-bit addressing, write transaction
- Open-drain SDA (`inout`), configurable clock (default 50 MHz system → 100 kHz SCL)
- START / address / ACK / data / ACK / STOP FSM
- `ack_error` flag when the slave NACKs
- Self-checking testbench (valid address + wrong-address NACK test)

## Interface
| Port | Dir | Description |
|---|---|---|
| `clk`, `rst_n` | in | System clock, active-low async reset |
| `start` | in | Pulse for 1 clk (when `busy = 0`) to begin a write |
| `addr[6:0]` | in | 7-bit slave address |
| `data[7:0]` | in | Byte to write |
| `busy` | out | High during a transaction |
| `done` | out | 1-clk pulse at end of transaction |
| `ack_error` | out | 1 = slave did not acknowledge |
| `scl`, `sda` | out / inout | I2C bus (needs external pull-up on SDA) |

## FSM
`IDLE → START → ADDR → ADDR_ACK → DATA → DATA_ACK → STOP → IDLE`

Each I2C bit is split into 4 phases (one tick = `CLK_FREQ / (4 × I2C_FREQ)` clocks), so SDA changes only while SCL is low, and START/STOP happen while SCL is high.

## Run the simulation
```bash
# Icarus Verilog + GTKWave
iverilog -o sim.out rtl/i2c_master.v tb/tb_i2c_master.v
vvp sim.out
gtkwave i2c_master.vcd
```

Expected output:
```
PASS T1: wrote 0xA5 to 0x50, ACK received, slave data = 0xa5
PASS T2: wrong address correctly NACKed (ack_error = 1)
ALL TESTS PASSED
```

## Waveform
_Add a GTKWave screenshot here (`docs/waveform.png`)._

## Possible extensions
- Read transactions and repeated START
- Multi-byte burst writes
- Clock stretching support
- Synthesis on FPGA with a real I2C slave (e.g. EEPROM / sensor)

## Repo structure
```
rtl/i2c_master.v
tb/tb_i2c_master.v
README.md
```
