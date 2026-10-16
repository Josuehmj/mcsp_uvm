// -----------------------------------------------------------------------------
// mcsp_core.sv
// Stream datapath: input FIFO -> per-packet processing FSM -> output FIFO.
// See the MCSP functional specification for the exact behavioral contract.
// -----------------------------------------------------------------------------
module mcsp_core
  import mcsp_pkg::*;
(
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic                       soft_rst,

  // configuration (from register block)
  input  logic                       cfg_en,
  input  logic [NUM_CH-1:0]          cfg_ch_en,
  input  logic [NUM_CH*3-1:0]        cfg_ch_mode,
  input  logic [NUM_CH-1:0]          cfg_ch_csum_en,
  input  logic [NUM_CH-1:0]          cfg_ch_par_en,
  input  logic [NUM_CH*8-1:0]        cfg_ch_maxlen,
  input  logic [NUM_CH*32-1:0]       cfg_ch_key,
  input  logic [4:0]                 cfg_thresh,
  input  logic [LUT_WORDS*32-1:0]    lut_flat,
  input  logic                       inject_req,
  output logic                       inject_ack,

  // sideband
  input  logic                       ext_pause,

  // input stream
  input  logic                       s_valid,
  output logic                       s_ready,
  input  logic [31:0]                s_data,
  input  logic [3:0]                 s_keep,
  input  logic                       s_last,
  input  logic [1:0]                 s_chan,
  input  logic                       s_par,

  // output stream
  output logic                       m_valid,
  input  logic                       m_ready,
  output logic [31:0]                m_data,
  output logic [3:0]                 m_keep,
  output logic                       m_last,
  output logic [1:0]                 m_chan,
  output logic                       m_err,

  // status to register block
  output logic                       busy,
  output logic                       in_empty,
  output logic                       in_full,
  output logic                       out_empty,
  output logic                       out_full,
  output logic [4:0]                 in_level,
  output logic [4:0]                 out_level,

  // events to register block (single-cycle strobes)
  output logic                       ev_par,
  output logic                       ev_len,
  output logic                       ev_dis,
  output logic                       ev_thresh,
  output logic                       ev_in_beat,
  output logic                       ev_out_beat,
  output logic                       ev_pkt_done,
  output logic [1:0]                 ev_done_chan,
  output logic                       csum_wr,
  output logic [1:0]                 csum_chan,
  output logic [31:0]                csum_val
);

  // ---------------------------------------------------------------------------
  // Helper functions
  // ---------------------------------------------------------------------------
  function automatic logic [31:0] f_bit_rev(input logic [31:0] d);
    logic [31:0] r;
    for (int i = 0; i < 32; i++) r[i] = d[31-i];
    return r;
  endfunction

  function automatic logic [31:0] f_bswap(input logic [31:0] d);
    return {d[7:0], d[15:8], d[23:16], d[31:24]};
  endfunction

  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic [31:0] f_rotl(input logic [31:0] d, input logic [4:0] n);
    logic [63:0] t;
    t = {d, d} << n;
    return t[63:32];
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */


  // 32-bit Fibonacci-style LFSR step (taps 31, 21, 1, 0), shifting left
  function automatic logic [31:0] f_lfsr_step(input logic [31:0] s);
    return {s[30:0], s[31] ^ s[21] ^ s[1] ^ s[0]};
  endfunction

  function automatic logic [31:0] f_keep_mask(input logic [3:0] k);
    return {{8{k[3]}}, {8{k[2]}}, {8{k[1]}}, {8{k[0]}}};
  endfunction

  // ---------------------------------------------------------------------------
  // Unpack configuration vectors into arrays
  // ---------------------------------------------------------------------------
  logic [2:0]  ch_mode   [NUM_CH];
  logic [7:0]  ch_maxlen [NUM_CH];
  logic [31:0] ch_key    [NUM_CH];

  always_comb begin
    for (int i = 0; i < NUM_CH; i++) begin
      ch_mode[i]   = cfg_ch_mode[i*3 +: 3];
      ch_maxlen[i] = cfg_ch_maxlen[i*8 +: 8];
      ch_key[i]    = cfg_ch_key[i*32 +: 32];
    end
  end

  // ---------------------------------------------------------------------------
  // FIFOs
  // ---------------------------------------------------------------------------
  localparam int unsigned FW = 40;

  logic          in_push, in_pop, out_push, out_pop;
  logic [FW-1:0] in_din, in_dout, out_din, out_dout;

  // input entry : {par[39], chan[38:37], last[36], keep[35:32], data[31:0]}
  // output entry: {err[39], chan[38:37], last[36], keep[35:32], data[31:0]}
  assign in_din  = {s_par, s_chan, s_last, s_keep, s_data};
  assign s_ready = cfg_en & ~in_full & ~soft_rst;
  assign in_push = s_valid & s_ready;

  mcsp_fifo #(.WIDTH(FW), .DEPTH(FIFO_DEPTH)) u_in_fifo (
    .clk(clk), .rst_n(rst_n), .flush(soft_rst),
    .push(in_push), .din(in_din), .pop(in_pop), .dout(in_dout),
    .empty(in_empty), .full(in_full), .level(in_level)
  );

  mcsp_fifo #(.WIDTH(FW), .DEPTH(FIFO_DEPTH)) u_out_fifo (
    .clk(clk), .rst_n(rst_n), .flush(soft_rst),
    .push(out_push), .din(out_din), .pop(out_pop), .dout(out_dout),
    .empty(out_empty), .full(out_full), .level(out_level)
  );

  // Input FIFO head
  wire        h_par  = in_dout[39];
  wire [1:0]  h_chan = in_dout[38:37];
  wire        h_last = in_dout[36];
  wire [3:0]  h_keep = in_dout[35:32];
  wire [31:0] h_data = in_dout[31:0];

  // ---------------------------------------------------------------------------
  // Processing FSM
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {S_IDLE = 2'd0, S_BODY = 2'd1, S_DROP = 2'd2, S_CSUM = 2'd3} state_e;

  state_e      state_q;
  logic [1:0]  cur_chan_q;
  logic [7:0]  beat_idx_q;
  logic        pkt_err_q;
  logic [31:0] csum_acc_q;
  logic [31:0] lfsr_q;
  logic        trunc_q;
  logic [31:0] csum_fin_q;
  logic        err_fin_q;
  logic        pause_q;
  logic        hold_q;

  wire first = (state_q == S_IDLE);

  wire [1:0]  chan_sel     = first ? h_chan : cur_chan_q;
  wire        ch_en_sel    = cfg_ch_en[chan_sel];
  wire [2:0]  mode_sel     = ch_mode[chan_sel];
  wire        csum_en_sel  = cfg_ch_csum_en[chan_sel];
  wire        par_en_sel   = cfg_ch_par_en[chan_sel];
  wire [7:0]  maxlen_sel   = ch_maxlen[chan_sel];
  wire [31:0] key_sel      = ch_key[chan_sel];

  wire [7:0]  idx_eff      = first ? 8'd0 : beat_idx_q;
  wire [31:0] lfsr_cur     = first ? key_sel : lfsr_q;

  // beat strobes
  wire dis_beat  = first && !in_empty && !ch_en_sel;
  wire drop_beat = (state_q == S_DROP) && !in_empty;
  wire beat      = ((first && ch_en_sel) || (state_q == S_BODY)) && !in_empty && !out_full;
  wire csum_beat = (state_q == S_CSUM) && !out_full;

  assign in_pop = dis_beat | drop_beat | beat;

  // transform
  logic [31:0] t_data;
  always_comb begin
    case (mode_sel)
      MODE_BYPASS:   t_data = h_data;
      MODE_XOR:      t_data = h_data ^ key_sel;
      MODE_ADD:      t_data = h_data + key_sel;
      MODE_BSWAP:    t_data = f_bswap(h_data);
      MODE_BREV:     t_data = f_bit_rev(h_data);
      MODE_LUT:      t_data = {lut_flat[{h_data[31:24], 3'b000} +: 8],
                               lut_flat[{h_data[23:16], 3'b000} +: 8],
                               lut_flat[{h_data[15:8],  3'b000} +: 8],
                               lut_flat[{h_data[7:0],   3'b000} +: 8]};
      MODE_ROTL:     t_data = f_rotl(h_data, key_sel[4:0]);
      MODE_SCRAMBLE: t_data = h_data ^ lfsr_cur;
      default:       t_data = h_data;
    endcase
  end

  wire        par_err     = par_en_sel & ((^h_data) ^ h_par);
  wire        at_limit    = (maxlen_sel != 8'd0) && (idx_eff == (maxlen_sel - 8'd1));
  wire        force_last  = at_limit & ~h_last;
  wire        last_out    = h_last | force_last;
  wire [3:0]  keep_out    = (h_last && !force_last) ? h_keep : 4'hF;
  wire [31:0] d_masked    = t_data & f_keep_mask(keep_out);
  wire [31:0] csum_base   = first ? 32'd0 : csum_acc_q;
  wire [31:0] csum_next   = csum_base + d_masked;
  wire        err_acc     = (first ? 1'b0 : pkt_err_q) | par_err;
  wire [31:0] d_out       = d_masked ^ (inject_req ? 32'h0000_0001 : 32'h0);
  wire        out_last_b  = last_out & ~csum_en_sel;

  assign inject_ack = beat & inject_req;

  // output FIFO push mux
  always_comb begin
    out_push = 1'b0;
    out_din  = '0;
    if (beat) begin
      out_push = 1'b1;
      out_din  = {par_err, chan_sel, out_last_b, keep_out, d_out};
    end else if (csum_beat) begin
      out_push = 1'b1;
      out_din  = {err_fin_q, cur_chan_q, 1'b1, 4'hF, csum_fin_q};
    end
  end

  // events
  assign ev_dis     = dis_beat;
  assign ev_par     = beat & par_err;
  assign ev_len     = beat & force_last;
  assign ev_in_beat = in_push;

  assign csum_wr    = beat & last_out;
  assign csum_chan  = chan_sel;
  assign csum_val   = csum_next;

  wire [5:0] out_lvl_next = {1'b0, out_level} + {5'b0, out_push} - {5'b0, out_pop};
  assign ev_thresh  = out_push && (cfg_thresh != 5'd0) && (out_lvl_next >= {1'b0, cfg_thresh});

  // sequential state
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q    <= S_IDLE;
      cur_chan_q <= '0;
      beat_idx_q <= '0;
      pkt_err_q  <= 1'b0;
      csum_acc_q <= '0;
      lfsr_q     <= '0;
      trunc_q    <= 1'b0;
      csum_fin_q <= '0;
      err_fin_q  <= 1'b0;
      pause_q    <= 1'b0;
      hold_q     <= 1'b0;
    end else if (soft_rst) begin
      state_q    <= S_IDLE;
      cur_chan_q <= '0;
      beat_idx_q <= '0;
      pkt_err_q  <= 1'b0;
      csum_acc_q <= '0;
      lfsr_q     <= '0;
      trunc_q    <= 1'b0;
      csum_fin_q <= '0;
      err_fin_q  <= 1'b0;
      pause_q    <= ext_pause;
      hold_q     <= 1'b0;
    end else begin
      pause_q <= ext_pause;
      hold_q  <= m_valid & ~m_ready;

      if (dis_beat) begin
        if (!h_last) state_q <= S_DROP;
      end else if (drop_beat) begin
        if (h_last) state_q <= S_IDLE;
      end else if (beat) begin
        if (first) cur_chan_q <= h_chan;
        csum_acc_q <= csum_next;
        pkt_err_q  <= err_acc;
        lfsr_q     <= f_lfsr_step(lfsr_cur);
        if (last_out) begin
          if (csum_en_sel) begin
            state_q    <= S_CSUM;
            csum_fin_q <= csum_next;
            err_fin_q  <= err_acc;
            trunc_q    <= force_last;
          end else begin
            state_q <= force_last ? S_DROP : S_IDLE;
          end
        end else begin
          state_q    <= S_BODY;
          beat_idx_q <= (idx_eff == 8'hFF) ? idx_eff : idx_eff + 8'd1;
        end
      end else if (csum_beat) begin
        state_q <= trunc_q ? S_DROP : S_IDLE;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Output stage (AXI-Stream-like valid/ready, with external pause)
  // m_valid never drops once asserted until a handshake occurs; ext_pause only
  // takes effect between beats.
  // ---------------------------------------------------------------------------
  assign m_valid = ~out_empty & (~pause_q | hold_q) & ~soft_rst;
  assign out_pop = m_valid & m_ready;

  assign m_data = m_valid ? out_dout[31:0]  : 32'h0;
  assign m_keep = m_valid ? out_dout[35:32] : 4'h0;
  assign m_last = m_valid ? out_dout[36]    : 1'b0;
  assign m_chan = m_valid ? out_dout[38:37] : 2'b00;
  assign m_err  = m_valid ? out_dout[39]    : 1'b0;

  assign ev_out_beat   = out_pop;
  assign ev_pkt_done   = out_pop & out_dout[36];
  assign ev_done_chan  = out_dout[38:37];

  assign busy = ~in_empty | ~out_empty | (state_q != S_IDLE);

endmodule
