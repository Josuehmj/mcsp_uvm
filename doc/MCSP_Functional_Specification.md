# MCSP - Multi-Channel Stream Processor

**Functional specification of a DUT designed for UVM verification (agents through RAL)** - Version 1.0

## 1. Purpose


The block is a 4-channel packet processor. Packets arrive on a valid/ready stream, are transformed per channel (XOR, add, byte swap, bit reverse, LUT substitution, rotate, scrambler), optionally parity-checked, length-limited and check-summed, and leave on a second valid/ready stream. A 32-bit APB3 slave configures everything and reports status; a level interrupt and a sideband pause/busy pair complete the interface set.

## 2. Block diagram

```
            APB3 slave (registers + LUT RAM)                         irq
                     |                                                ^
              +------v------+   config / LUT      +-----------------+ |
              |  mcsp_regs  +--------------------->                 | |
              |  (RAL view) <--------------------+   mcsp_core     | |
              +-------------+  events / status    |                 | |
                                                  |  in FIFO(16)    | |
   s_* stream  ---------------------------------->  -> FSM/xform   | |
   (valid/ready, 4 channels)                      |  -> out FIFO(16)+--> m_* stream
                                                  +--------^--------+
   ext_pause ---------------------------------------------+    busy -->
```

Files: `mcsp_pkg.sv` (constants), `mcsp_fifo.sv`, `mcsp_core.sv` (datapath), `mcsp_regs.sv` (APB, registers, LUT RAM), `mcsp_top.sv` (top level `mcsp_top`), `filelist.f`.

## 3. Top-level interface (`mcsp_top`)

Single clock `clk`. All signals are synchronous to `clk` unless noted.

| Port | Dir | Width | Description |
|---|---|---|---|
| clk | in | 1 | Clock |
| rst_n | in | 1 | Active-low reset, asynchronous assert. De-assert synchronously to clk |
| psel, penable, pwrite | in | 1 | APB3 control |
| paddr | in | 12 | APB byte address (word aligned) |
| pwdata | in | 32 | APB write data |
| prdata | out | 32 | APB read data |
| pready | out | 1 | APB ready (see 4.1) |
| pslverr | out | 1 | APB slave error (see 4.1) |
| s_valid | in | 1 | Stream input valid |
| s_ready | out | 1 | Stream input ready |
| s_data | in | 32 | Stream input data |
| s_keep | in | 4 | Byte-valid mask (meaningful on last beat only) |
| s_last | in | 1 | Last beat of packet |
| s_chan | in | 2 | Channel number (sampled on first beat of a packet) |
| s_par | in | 1 | Even-parity bit of s_data (checked only if enabled) |
| m_valid | out | 1 | Stream output valid |
| m_ready | in | 1 | Stream output ready |
| m_data | out | 32 | Stream output data |
| m_keep | out | 4 | Byte-valid mask |
| m_last | out | 1 | Last beat of output packet |
| m_chan | out | 2 | Channel of the packet |
| m_err | out | 1 | Parity-error flag for this beat (see 5.6) |
| ext_pause | in | 1 | Sideband: pause the output stream between beats |
| busy | out | 1 | Sideband: packet processing in progress |
| irq | out | 1 | Level interrupt, active high |

## 4. Interface protocols

### 4.1 APB3 slave

- Standard APB3 (no PSTRB, no PPROT). 32-bit word accesses only. Valid addresses are word aligned.
- A transfer has a setup phase (PSEL=1, PENABLE=0) followed by an access phase (PSEL=1, PENABLE=1). The transfer completes at the clock edge ending the first access-phase cycle in which PREADY=1.
- **Wait states:** the number of access-phase cycles with PREADY=0 equals `CTRL.APB_WS` (0..15) sampled during the setup phase. A write to CTRL itself completes with the old value; the new value applies from the next transfer. Applies to all registers and to the LUT RAM.
- PREADY is driven high whenever the access phase is not active (it only gates the access phase).
- **PSLVERR** is asserted together with PREADY in the access phase when the address is not mapped (see register map; includes misaligned addresses and holes). The access has no effect and PRDATA reads 0. PSLVERR is 0 at all other times.
- Writes to read-only registers and to reserved bits are silently ignored (no PSLVERR). Reserved bits read as 0.
- Register side effects (read-to-clear, write-1-to-clear, soft reset trigger) happen when the transfer completes.

### 4.2 Stream input

- `s_ready = CTRL.EN & ~in_fifo_full & ~soft_reset_pulse`. It does not depend on `s_valid`. A beat transfers on every clock edge where `s_valid & s_ready`.
- With `CTRL.EN = 0` the input stalls (s_ready=0); nothing is dropped.
- A **packet** is a run of consecutive accepted beats ending with a beat that has `s_last=1`. Packets may be back-to-back with no idle cycles. Packets of any length are accepted.
- `s_chan` is sampled on the **first** beat of a packet. `s_chan` on later beats of the same packet is ignored.
- `s_keep` is used only on the beat with `s_last=1`; on other beats it is ignored (treated as 4'hF). Any 4-bit pattern is legal on the last beat (not restricted to contiguous low bytes).
- `s_par` must equal the XOR-reduction of `s_data` (even parity over the 32 data bits) when the channel has `PAR_CHK_EN=1`; otherwise it is ignored.

### 4.3 Stream output

- Standard valid/ready. Once `m_valid` is high it stays high, and `m_data/m_keep/m_last/m_chan/m_err` stay stable, until the cycle with `m_ready=1`.
- `ext_pause=1` prevents a **new** beat from being offered (the pause is registered, so it takes effect one cycle after being asserted). A beat that is already being offered is never withdrawn.
- While `m_valid=0` all `m_*` payload outputs are 0.
- An output packet is a run of beats ending with `m_last=1`. `m_chan` is constant within a packet.

### 4.4 Sideband and interrupt

- `busy` is 1 whenever either FIFO is non-empty or the processing FSM is in the middle of a packet (including a checksum beat still to be emitted, or a packet remainder still being dropped). It is 0 only when everything has fully drained.
- `irq = |(IRQ_STATUS & IRQ_MASK)` (level).

### 4.5 Reset

- **Hard reset** (`rst_n=0`): all registers return to their reset values, FIFOs and FSM are emptied. LUT RAM content is not reset (see 8).
- **Soft reset** (write 1 to `CTRL.SOFT_RST`): a one-cycle internal pulse, starting the cycle after the write transfer completes. It flushes both FIFOs and the FSM and clears all statistics (ERR_CNT, PKT_CNT_TOTAL, IN_BEATS, OUT_BEATS, all CH_PKT_CNT, all CH_LAST_CSUM), IRQ_STATUS and DBG_CTRL.INJECT_ERR. It does **not** touch configuration: CTRL.EN, CTRL.APB_WS, IRQ_MASK, THRESH, SCRATCH, CH_CTRL, CH_KEY and the LUT RAM keep their values. During the pulse cycle `s_ready=0` and `m_valid=0`; data in flight is discarded and `m_valid` may fall without a handshake. Traffic should be quiesced before a soft reset.

## 5. Functional description

### 5.1 Packet processing overview

For each packet the DUT looks at the channel number of its first beat and applies that channel's configuration (CH_CTRL, CH_KEY) to every beat of the packet.

1. **Channel disabled** (`CH_CTRL.EN=0`): the whole packet is consumed and dropped. Nothing is output. `ERR_CNT` increments by 1 and `IRQ_STATUS.CHAN_DIS` is set, once per packet (at its first beat).
2. **Channel enabled:** each beat goes through: parity check, transform, keep masking, checksum accumulation, length limit, output.

The global `CTRL.EN` only gates the input handshake (4.2); beats already inside the FIFOs continue to be processed and output when EN=0.

### 5.2 Transforms (`CH_CTRL.MODE`)

| MODE | Name | Output word (before keep masking) |
|---|---|---|
| 0 | BYPASS | `d` |
| 1 | XOR | `d ^ KEY` |
| 2 | ADD | `(d + KEY) mod 2^32` |
| 3 | BSWAP | bytes reversed: `{d[7:0], d[15:8], d[23:16], d[31:24]}` |
| 4 | BREV | 32-bit bit reversal |
| 5 | LUT | each byte `b` of `d` replaced by `LUT_byte[b]` (see 8) |
| 6 | ROTL | rotate left by `KEY[4:0]` |
| 7 | SCRAMBLE | `d ^ s_i`, with LFSR state `s_i` (below) |

KEY is unused in modes 0, 3, 4 and 5.

**SCRAMBLE:** `s_0 = KEY` at the first beat of every packet. For every processed beat `out = d ^ s_i` and then `s_(i+1) = {s_i[30:0], s_i[31] ^ s_i[21] ^ s_i[1] ^ s_i[0]}`. With `KEY=0` the state stays 0 and the mode is the identity. The state advances once per processed beat and restarts at each packet.

### 5.3 Keep masking

On the last beat of a packet the transformed word is ANDed byte-wise with `s_keep` (byte lane k kept if `s_keep[k]=1`, otherwise forced to 0), and `m_keep = s_keep`. All other beats have `m_keep = 4'hF` and are not masked. The transform is applied to the full 32-bit word first, then masked.

### 5.4 Maximum packet length (`CH_CTRL.MAX_LEN`)

- `MAX_LEN=0`: unlimited.
- Otherwise at most `MAX_LEN` data beats are output. If the beat with 0-based index `MAX_LEN-1` arrives with `s_last=0`, the packet is **truncated**: that beat is output with `m_last=1` (or, with checksum, as the final data beat) and `m_keep=4'hF` (no masking), `IRQ_STATUS.LEN_ERR` is set, `ERR_CNT` increments by 1, and all remaining input beats of that packet are dropped silently until the input `s_last`.
- A packet whose length equals `MAX_LEN` exactly is not an error.

### 5.5 Checksum (`CH_CTRL.APPEND_CSUM`)

The checksum is the sum modulo 2^32 of all output data words of the packet (after transform and keep masking, before error injection). It is computed for every forwarded packet and stored in `CH_LAST_CSUM` when the packet's last data beat is processed, regardless of `APPEND_CSUM`.

If `APPEND_CSUM=1`, the final data beat is output with `m_last=0` and one extra beat follows: `m_data = checksum`, `m_keep = 4'hF`, `m_last = 1`, `m_err = OR of the parity errors of all beats of the packet`. This also applies to truncated packets. The extra beat costs one additional cycle in the processing stage.

### 5.6 Parity (`CH_CTRL.PAR_CHK_EN`)

When enabled, every input beat of the packet (raw `s_data`, all 32 bits, regardless of keep) is checked: error if `s_par != ^s_data`. On error the beat is still processed and forwarded, `m_err=1` for that output beat, `IRQ_STATUS.PAR_ERR` is set and `ERR_CNT` increments by 1 **per bad beat**. If both a parity error and a truncation occur on the same beat, ERR_CNT increases by 2.

### 5.7 Error injection (`DBG_CTRL.INJECT_ERR`)

Writing 1 arms a one-shot corruption: the next processed data beat (any channel; never a checksum beat) has bit 0 of `m_data` inverted after the checksum was computed. The bit is cleared by hardware when the corruption is applied. Intended to confirm that a scoreboard detects a faulty DUT.

### 5.8 Statistics

- `IN_BEATS`: every beat accepted at the input (including beats of dropped or truncated-away packets).
- `OUT_BEATS`: every beat accepted at the output (including checksum beats).
- `PKT_CNT_TOTAL` and `CH_PKT_CNT[n]`: incremented when a beat with `m_last=1` is accepted at the output, for the channel in `m_chan`.
- `ERR_CNT`: sum of parity errors (per beat), truncations and disabled-channel drops. `IRQ_FORCE` does not increment it.

### 5.9 Timing

- Latency: 2 clock cycles from an input handshake to the first output beat being offered (measured, empty pipeline, `ext_pause=0`).
- Throughput: 1 beat per cycle sustained when the output is not stalled and no checksum is appended.
- FIFOs: 16 entries each (40-bit entries). `STATUS` exposes both levels.

## 6. Register map

APB byte addresses, 32-bit registers. Reserved bits read 0 and ignore writes. Unlisted addresses give PSLVERR.

### 6.1 Global registers

| Offset | Name | Access | Reset | Description |
|---|---|---|---|---|
| 0x000 | ID | RO | 0x56454952 | ASCII "VERI" |
| 0x004 | VERSION | RO | 0x00010000 | Version 1.0 |
| 0x008 | CTRL | mixed | 0x00000000 | See 6.2 |
| 0x00C | STATUS | RO (volatile) | 0x0000000A | See 6.3 |
| 0x010 | IRQ_STATUS | W1C (volatile) | 0 | See 6.4 |
| 0x014 | IRQ_MASK | RW | 0 | Bits [4:0] |
| 0x018 | IRQ_FORCE | WO | - | Bits [4:0]: write 1 sets the matching IRQ_STATUS bit. Reads 0 |
| 0x01C | THRESH | RW | 0 | Bits [4:0]: output-FIFO level threshold, 0 = disabled |
| 0x020 | DBG_CTRL | mixed | 0 | Bit 0 INJECT_ERR: W1S, cleared by hardware (volatile) |
| 0x024 | SCRATCH | RW | 0xCAFEF00D | Full 32-bit scratch register |
| 0x028 | ERR_CNT | RC (volatile) | 0 | Error counter, saturating at 0xFFFFFFFF; a read returns the value and clears it |
| 0x02C | PKT_CNT_TOTAL | RO (volatile) | 0 | Completed output packets |
| 0x030 | IN_BEATS | RO (volatile) | 0 | Input beats accepted |
| 0x034 | OUT_BEATS | RO (volatile) | 0 | Output beats accepted |

### 6.2 CTRL (0x008)

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 0 | EN | RW | 0 | Global enable of the input handshake |
| 1 | SOFT_RST | WO (self-clearing pulse) | - | Write 1 triggers soft reset (4.5). Reads 0 |
| 11:8 | APB_WS | RW | 0 | APB wait states for all following transfers |
| others | reserved | RO | 0 | |

### 6.3 STATUS (0x00C)

| Bits | Field | Description |
|---|---|---|
| 0 | BUSY | Same as the `busy` pin |
| 1 | IN_EMPTY | Input FIFO empty |
| 2 | IN_FULL | Input FIFO full |
| 3 | OUT_EMPTY | Output FIFO empty |
| 4 | OUT_FULL | Output FIFO full |
| 12:8 | IN_LEVEL | Input FIFO occupancy (0..16) |
| 20:16 | OUT_LEVEL | Output FIFO occupancy (0..16) |

### 6.4 IRQ_STATUS / IRQ_MASK / IRQ_FORCE bits

| Bit | Name | Set by hardware when |
|---|---|---|
| 0 | PKT_DONE | A beat with `m_last=1` is accepted at the output |
| 1 | PAR_ERR | The processing stage handles a beat with a parity error |
| 2 | LEN_ERR | A packet is truncated by MAX_LEN |
| 3 | CHAN_DIS | A packet is dropped because its channel is disabled |
| 4 | FIFO_THRESH | A push into the output FIFO leaves its level (after any simultaneous pop) at or above THRESH, with THRESH != 0 |

IRQ_STATUS is write-1-to-clear. If hardware (or IRQ_FORCE) sets a bit in the same cycle as a clear, the set wins. Bits 5 and up are reserved. PAR_ERR, LEN_ERR and CHAN_DIS are raised at the processing stage, i.e. a variable number of cycles after the corresponding input beat (FIFO dependent); PKT_DONE is aligned with the output handshake.

### 6.5 Per-channel registers

Channel n (0..3) base address `0x100 + n*0x20`.

| Offset | Name | Access | Reset | Description |
|---|---|---|---|---|
| +0x00 | CH_CTRL | RW | 0 | See below |
| +0x04 | CH_KEY | RW | 0 | 32-bit key / offset / seed |
| +0x08 | CH_PKT_CNT | RO (volatile) | 0 | Completed output packets of this channel |
| +0x0C | CH_LAST_CSUM | RO (volatile) | 0 | Checksum of the last forwarded packet of this channel |

CH_CTRL fields: bit 0 `EN`, bits 3:1 `MODE`, bit 4 `APPEND_CSUM`, bit 5 `PAR_CHK_EN`, bits 15:8 `MAX_LEN`; all RW with reset 0; other bits reserved.

Channel blocks occupy 0x100-0x17F. Offsets +0x10..+0x1C inside each block and 0x180-0x3FF are unmapped.

### 6.6 Access policy coverage

For RAL work the register set contains: RW, RO, WO, W1C, W1S, RC, volatile fields, constant ID registers, non-zero reset values, reserved bits, a register array (4 identical channel blocks), and one memory. Fields that change by themselves (STATUS, counters, IRQ_STATUS, DBG_CTRL, CH_LAST_CSUM) are volatile and need to be excluded from, or handled in, built-in sequences that assume stable values.

## 7. Interrupt behavior

`irq` is level-sensitive: high while any `IRQ_STATUS` bit is set with its `IRQ_MASK` bit set. Clearing is by writing 1 to the status bit. `IRQ_FORCE` allows software-triggered interrupts without traffic.

## 8. LUT RAM

- Address range `0x400-0x4FC`, 64 words of 32 bits, RW, front door via APB (same wait-state rule as registers).
- It holds a 256-entry byte table. Byte `b` lives in word `b/4`, lane `b%4` (little endian: word bits `[8*(b%4)+7 : 8*(b%4)]`).
- At power-up it is initialised to the identity table (`LUT_byte[b] = b`) by a simulation `initial` block. Neither hard nor soft reset modifies it.
- Modifying the table while LUT-mode traffic is in flight is allowed but the result is timing dependent (each beat uses the content at the cycle it is processed).

## 9. Back-door HDL paths

Relative to the `mcsp_top` instance. Each architectural register is a full 32-bit signal with unused bits tied to 0.

| Register | Path |
|---|---|
| ID, VERSION, STATUS | `u_regs.r_id`, `u_regs.r_version`, `u_regs.r_status` (wires) |
| CTRL, IRQ_STATUS, IRQ_MASK, THRESH | `u_regs.r_ctrl`, `u_regs.r_irq_status`, `u_regs.r_irq_mask`, `u_regs.r_thresh` |
| DBG_CTRL, SCRATCH, ERR_CNT | `u_regs.r_dbg_ctrl`, `u_regs.r_scratch`, `u_regs.r_err_cnt` |
| PKT_CNT_TOTAL, IN_BEATS, OUT_BEATS | `u_regs.r_pkt_cnt_total`, `u_regs.r_in_beats`, `u_regs.r_out_beats` |
| CH_CTRL[n], CH_KEY[n] | `u_regs.ch_ctrl[n]`, `u_regs.ch_key[n]` |
| CH_PKT_CNT[n], CH_LAST_CSUM[n] | `u_regs.ch_pkt_cnt[n]`, `u_regs.ch_last_csum[n]` |
| LUT word w | `u_regs.lut_mem[w]` |

IRQ_FORCE and the SOFT_RST bit have no storage. A back-door read of ERR_CNT does not clear it.
