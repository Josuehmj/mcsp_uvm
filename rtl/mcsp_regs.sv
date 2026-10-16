// -----------------------------------------------------------------------------
// mcsp_regs.sv
// APB3 slave, register bank and LUT RAM of the MCSP.
//
// Every architectural register is held in a full 32-bit signal named r_* (or
// ch_*[n] for per-channel registers) so that it can be reached by a UVM RAL
// backdoor path. Unused bits are constant zero.
// -----------------------------------------------------------------------------
module mcsp_regs
  import mcsp_pkg::*;
(
  input  logic                       clk,
  input  logic                       rst_n,

  // APB3 slave
  input  logic                       psel,
  input  logic                       penable,
  input  logic                       pwrite,
  input  logic [11:0]                paddr,
  input  logic [31:0]                pwdata,
  output logic [31:0]                prdata,
  output logic                       pready,
  output logic                       pslverr,

  // configuration to datapath
  output logic                       cfg_en,
  output logic                       soft_rst,
  output logic [NUM_CH-1:0]          cfg_ch_en,
  output logic [NUM_CH*3-1:0]        cfg_ch_mode,
  output logic [NUM_CH-1:0]          cfg_ch_csum_en,
  output logic [NUM_CH-1:0]          cfg_ch_par_en,
  output logic [NUM_CH*8-1:0]        cfg_ch_maxlen,
  output logic [NUM_CH*32-1:0]       cfg_ch_key,
  output logic [4:0]                 cfg_thresh,
  output logic [LUT_WORDS*32-1:0]    lut_flat,
  output logic                       inject_req,
  input  logic                       inject_ack,

  // status and events from datapath
  input  logic                       busy,
  input  logic                       in_empty,
  input  logic                       in_full,
  input  logic                       out_empty,
  input  logic                       out_full,
  input  logic [4:0]                 in_level,
  input  logic [4:0]                 out_level,
  input  logic                       ev_par,
  input  logic                       ev_len,
  input  logic                       ev_dis,
  input  logic                       ev_thresh,
  input  logic                       ev_in_beat,
  input  logic                       ev_out_beat,
  input  logic                       ev_pkt_done,
  input  logic [1:0]                 ev_done_chan,
  input  logic                       csum_wr,
  input  logic [1:0]                 csum_chan,
  input  logic [31:0]                csum_val,

  // interrupt
  output logic                       irq
);

  // ---------------------------------------------------------------------------
  // Register storage (backdoor-friendly 32-bit signals)
  // ---------------------------------------------------------------------------
  logic [31:0] r_ctrl;
  logic [31:0] r_irq_status;
  logic [31:0] r_irq_mask;
  logic [31:0] r_thresh;
  logic [31:0] r_dbg_ctrl;
  logic [31:0] r_scratch;
  logic [31:0] r_err_cnt;
  logic [31:0] r_pkt_cnt_total;
  logic [31:0] r_in_beats;
  logic [31:0] r_out_beats;

  logic [31:0] ch_ctrl      [NUM_CH];
  logic [31:0] ch_key       [NUM_CH];
  logic [31:0] ch_pkt_cnt   [NUM_CH];
  logic [31:0] ch_last_csum [NUM_CH];

  logic [31:0] lut_mem      [LUT_WORDS];

  wire  [31:0] r_id      = DEVICE_ID;
  wire  [31:0] r_version = DEVICE_VERSION;
  wire  [31:0] r_status  = {11'b0, out_level, 3'b0, in_level,
                            3'b0, out_full, out_empty, in_full, in_empty, busy};

  logic soft_rst_q;
  assign soft_rst = soft_rst_q;

  // Writable-bit masks
  localparam logic [31:0] MASK_CTRL    = 32'h0000_0F01;  // EN[0], APB_WS[11:8]
  localparam logic [31:0] MASK_IRQ     = 32'h0000_001F;
  localparam logic [31:0] MASK_THRESH  = 32'h0000_001F;
  localparam logic [31:0] MASK_CH_CTRL = 32'h0000_FF3F;

  // ---------------------------------------------------------------------------
  // APB access sequencing (with configurable wait states)
  // ---------------------------------------------------------------------------
  logic [3:0] ws_left_q;

  wire acc_setup = psel & ~penable;
  wire acc_phase = psel & penable;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                              ws_left_q <= 4'd0;
    else if (acc_setup)                      ws_left_q <= r_ctrl[11:8];
    else if (acc_phase && ws_left_q != 4'd0) ws_left_q <= ws_left_q - 4'd1;
  end

  // PREADY idles high; it only gates a transfer during the access phase.
  assign pready = ~acc_phase | (ws_left_q == 4'd0);

  wire xfer    = acc_phase & pready;
  wire wr_xfer = xfer &  pwrite;
  wire rd_xfer = xfer & ~pwrite;

  // ---------------------------------------------------------------------------
  // Address decode
  // ---------------------------------------------------------------------------
  wire       aligned    = (paddr[1:0] == 2'b00);
  wire       hit_global = aligned && (paddr[11:6] == 6'd0) && (paddr[5:2] <= 4'd13);
  wire       hit_ch     = aligned && (paddr[11:7] == 5'b00010) && (paddr[4:2] <= 3'd3);
  wire       hit_lut    = aligned && (paddr[11:8] == 4'h4);
  wire       addr_ok    = hit_global | hit_ch | hit_lut;
  wire [1:0] ch_idx     = paddr[6:5];
  wire [5:0] lut_idx    = paddr[7:2];

  assign pslverr = acc_phase & pready & ~addr_ok;

  // Read mux
  always_comb begin
    prdata = 32'h0;
    if (hit_global) begin
      case (paddr[5:2])
        4'd0:  prdata = r_id;
        4'd1:  prdata = r_version;
        4'd2:  prdata = r_ctrl;            // SOFT_RST bit reads as 0
        4'd3:  prdata = r_status;
        4'd4:  prdata = r_irq_status;
        4'd5:  prdata = r_irq_mask;
        4'd6:  prdata = 32'h0;             // IRQ_FORCE is write-only
        4'd7:  prdata = r_thresh;
        4'd8:  prdata = r_dbg_ctrl;
        4'd9:  prdata = r_scratch;
        4'd10: prdata = r_err_cnt;
        4'd11: prdata = r_pkt_cnt_total;
        4'd12: prdata = r_in_beats;
        4'd13: prdata = r_out_beats;
        default: prdata = 32'h0;
      endcase
    end else if (hit_ch) begin
      case (paddr[4:2])
        3'd0:    prdata = ch_ctrl[ch_idx];
        3'd1:    prdata = ch_key[ch_idx];
        3'd2:    prdata = ch_pkt_cnt[ch_idx];
        3'd3:    prdata = ch_last_csum[ch_idx];
        default: prdata = 32'h0;
      endcase
    end else if (hit_lut) begin
      prdata = lut_mem[lut_idx];
    end
  end

  // Write strobes for special registers
  wire wr_ctrl       = wr_xfer & hit_global & (paddr[5:2] == 4'd2);
  wire wr_irq_status = wr_xfer & hit_global & (paddr[5:2] == 4'd4);
  wire wr_irq_force  = wr_xfer & hit_global & (paddr[5:2] == 4'd6);
  wire wr_dbg_ctrl   = wr_xfer & hit_global & (paddr[5:2] == 4'd8);
  wire rd_err_cnt    = rd_xfer & hit_global & (paddr[5:2] == 4'd10);

  // ---------------------------------------------------------------------------
  // Configuration registers (RW; not affected by soft reset)
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_ctrl     <= 32'h0;
      r_irq_mask <= 32'h0;
      r_thresh   <= 32'h0;
      r_scratch  <= 32'hCAFE_F00D;
      for (int i = 0; i < NUM_CH; i++) begin
        ch_ctrl[i] <= 32'h0;
        ch_key[i]  <= 32'h0;
      end
    end else if (wr_xfer && hit_global) begin
      case (paddr[5:2])
        4'd2:    r_ctrl     <= pwdata & MASK_CTRL;
        4'd5:    r_irq_mask <= pwdata & MASK_IRQ;
        4'd7:    r_thresh   <= pwdata & MASK_THRESH;
        4'd9:    r_scratch  <= pwdata;
        default: ;
      endcase
    end else if (wr_xfer && hit_ch) begin
      case (paddr[4:2])
        3'd0:    ch_ctrl[ch_idx] <= pwdata & MASK_CH_CTRL;
        3'd1:    ch_key[ch_idx]  <= pwdata;
        default: ;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // LUT RAM (no reset; powers up as identity map, simulation initial block)
  // ---------------------------------------------------------------------------
  initial begin
    for (int w = 0; w < LUT_WORDS; w++)
      lut_mem[w] = {8'(4*w+3), 8'(4*w+2), 8'(4*w+1), 8'(4*w)};
  end

  always_ff @(posedge clk) begin
    if (wr_xfer && hit_lut) lut_mem[lut_idx] <= pwdata;
  end

  // ---------------------------------------------------------------------------
  // Status / counter registers (soft reset clears them)
  // ---------------------------------------------------------------------------
  logic [4:0]  irq_w1c, irq_force, irq_hw_set;
  logic [1:0]  err_inc;
  logic [32:0] err_sum;
  logic [31:0] err_base;

  assign irq_w1c    = wr_irq_status ? pwdata[4:0] : 5'b0;
  assign irq_force  = wr_irq_force  ? pwdata[4:0] : 5'b0;
  assign irq_hw_set = {ev_thresh, ev_dis, ev_len, ev_par, ev_pkt_done};

  assign err_inc  = {1'b0, ev_par} + {1'b0, ev_len} + {1'b0, ev_dis};
  assign err_base = rd_err_cnt ? 32'h0 : r_err_cnt;
  assign err_sum  = {1'b0, err_base} + {31'b0, err_inc};

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      soft_rst_q      <= 1'b0;
      r_irq_status    <= 32'h0;
      r_dbg_ctrl      <= 32'h0;
      r_err_cnt       <= 32'h0;
      r_pkt_cnt_total <= 32'h0;
      r_in_beats      <= 32'h0;
      r_out_beats     <= 32'h0;
      for (int i = 0; i < NUM_CH; i++) begin
        ch_pkt_cnt[i]   <= 32'h0;
        ch_last_csum[i] <= 32'h0;
      end
    end else begin
      soft_rst_q <= wr_ctrl & pwdata[1];

      if (soft_rst_q) begin
        r_irq_status    <= 32'h0;
        r_dbg_ctrl      <= 32'h0;
        r_err_cnt       <= 32'h0;
        r_pkt_cnt_total <= 32'h0;
        r_in_beats      <= 32'h0;
        r_out_beats     <= 32'h0;
        for (int i = 0; i < NUM_CH; i++) begin
          ch_pkt_cnt[i]   <= 32'h0;
          ch_last_csum[i] <= 32'h0;
        end
      end else begin
        // IRQ_STATUS: W1C, hardware/force set wins over clear
        r_irq_status[4:0] <= (r_irq_status[4:0] & ~irq_w1c) | irq_hw_set | irq_force;

        // DBG_CTRL.INJECT_ERR: W1S, cleared by hardware when consumed (set wins)
        if (wr_dbg_ctrl && pwdata[0]) r_dbg_ctrl[0] <= 1'b1;
        else if (inject_ack)          r_dbg_ctrl[0] <= 1'b0;

        // ERR_CNT: RC, saturating; new events in the read cycle are kept
        r_err_cnt <= err_sum[32] ? 32'hFFFF_FFFF : err_sum[31:0];

        if (ev_pkt_done) r_pkt_cnt_total <= r_pkt_cnt_total + 32'd1;
        if (ev_in_beat)  r_in_beats      <= r_in_beats  + 32'd1;
        if (ev_out_beat) r_out_beats     <= r_out_beats + 32'd1;

        for (int i = 0; i < NUM_CH; i++) begin
          if (ev_pkt_done && ev_done_chan == 2'(i))
            ch_pkt_cnt[i] <= ch_pkt_cnt[i] + 32'd1;
          if (csum_wr && csum_chan == 2'(i))
            ch_last_csum[i] <= csum_val;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Outputs to datapath
  // ---------------------------------------------------------------------------
  assign cfg_en     = r_ctrl[0];
  assign cfg_thresh = r_thresh[4:0];
  assign inject_req = r_dbg_ctrl[0];
  assign irq        = |(r_irq_status[4:0] & r_irq_mask[4:0]);

  always_comb begin
    for (int i = 0; i < NUM_CH; i++) begin
      cfg_ch_en[i]            = ch_ctrl[i][0];
      cfg_ch_mode[i*3 +: 3]   = ch_ctrl[i][3:1];
      cfg_ch_csum_en[i]       = ch_ctrl[i][4];
      cfg_ch_par_en[i]        = ch_ctrl[i][5];
      cfg_ch_maxlen[i*8 +: 8] = ch_ctrl[i][15:8];
      cfg_ch_key[i*32 +: 32]  = ch_key[i];
    end
    for (int w = 0; w < LUT_WORDS; w++)
      lut_flat[w*32 +: 32] = lut_mem[w];
  end

  // 'busy' is exposed through STATUS only; keep lint quiet about the port.
  wire unused_ok = &{1'b0, busy, 1'b0};

endmodule
