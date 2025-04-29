# `cpu.vhd` – 8‑bit CPU Core

## Key facts
* **Purpose:** Executes a minimal instruction set tailored for a BrainF*** interpreter embedded in ROM.
* **Data width:** 8 bits
* **Address width:** 13 bits (8 KiB data memory)
* **Clocking:** Single rising‑edge synchronous design
* **Reset:** Active‑high asynchronous `RESET`

## External interface
| Signal | Dir | Width | Function |
|--------|-----|-------|----------|
| `CLK`  | in  | 1 | System clock |
| `RESET`| in  | 1 | Global reset (async, active‑high) |
| `EN`   | in  | 1 | Clock‑enable for single‑step operation |
| **Data RAM** ||||
| `DATA_ADDR` | out | 13 | Byte address into external RAM |
| `DATA_WDATA`| out | 8  | Write data |
| `DATA_RDATA`| in  | 8  | Read data |
| `DATA_RDWR` | out | 1  | 0 = read, 1 = write |
| `DATA_EN`   | out | 1  | Access strobe |
| **Input port** ||||
| `IN_DATA` | in  | 8 | External input byte |
| `IN_VLD`  | in  | 1 | Input data valid |
| `IN_REQ`  | out | 1 | Request next byte |
| **Output port** ||||
| `OUT_DATA`| out | 8 | Output byte |
| `OUT_BUSY`| in  | 1 | Output target busy |
| `OUT_WE`  | out | 1 | Write enable |
| **Status** ||||
| `READY` | out | 1 | Core finished reset/start‑up |
| `DONE`  | out | 1 | Program halted |

## Typical use
Connect `DATA_*` to a single‑port RAM and hook `IN_* / OUT_*` to your I/O (e.g. the UART receiver below). Drive `EN` high for free‑running execution or toggle it for instruction‑by‑instruction tracing.
