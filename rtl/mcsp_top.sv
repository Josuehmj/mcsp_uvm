// -----------------------------------------------------------------------------
// mcsp_top.sv
// Multi-Channel Stream Processor (MCSP) - top level
//
//   * APB3 slave        : registers + LUT RAM
//   * Stream input      : valid/ready, 32-bit data, 4 channels
//   * Stream output     : valid/ready, 32-bit data
//   * Sideband          : ext_pause (in), busy (out)
//   * Interrupt         : irq (level, active high)
// -----------------------------------------------------------------------------
module mcsp_top
  import mcsp_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,          // asynchronous assert, active low

  // APB3 slave
  input  logic        psel,
  input  logic        penable,
  input  logic        pwrite,
  input  logic [11:0] paddr,
  input  logic [31:0] pwdata,
  output logic [31:0] prdata,
  output logic        pready,
  output logic        pslverr,

  // Stream input
  input  logic        s_valid,
  output logic        s_ready,
  input  logic [31:0] s_data,
  input  logic [3:0]  s_keep,
  input  logic        s_last,
  input  logic [1:0]  s_chan,
  input  logic        s_par,

  // Stream output
  output logic        m_valid,
  input  logic        m_ready,
  output logic [31:0] m_data,
  output logic [3:0]  m_keep,
  output logic        m_last,
  output logic [1:0]  m_chan,
  output logic        m_err,

  // Sideband
  input  logic        ext_pause,
  output logic        busy,

  // Interrupt
  output logic        irq
);

  logic                    cfg_en, soft_rst;
  logic [NUM_CH-1:0]       cfg_ch_en, cfg_ch_csum_en, cfg_ch_par_en;
  logic [NUM_CH*3-1:0]     cfg_ch_mode;
  logic [NUM_CH*8-1:0]     cfg_ch_maxlen;
  logic [NUM_CH*32-1:0]    cfg_ch_key;
  logic [4:0]              cfg_thresh;
  logic [LUT_WORDS*32-1:0] lut_flat;
  logic                    inject_req, inject_ack;

  logic                    in_empty, in_full, out_empty, out_full;
  logic [4:0]              in_level, out_level;
  logic                    ev_par, ev_len, ev_dis, ev_thresh;
  logic                    ev_in_beat, ev_out_beat, ev_pkt_done;
  logic [1:0]              ev_done_chan;
  logic                    csum_wr;
  logic [1:0]              csum_chan;
  logic [31:0]             csum_val;

  mcsp_regs u_regs (
    .clk, .rst_n,
    .psel, .penable, .pwrite, .paddr, .pwdata, .prdata, .pready, .pslverr,
    .cfg_en, .soft_rst, .cfg_ch_en, .cfg_ch_mode, .cfg_ch_csum_en, .cfg_ch_par_en,
    .cfg_ch_maxlen, .cfg_ch_key, .cfg_thresh, .lut_flat, .inject_req, .inject_ack,
    .busy, .in_empty, .in_full, .out_empty, .out_full, .in_level, .out_level,
    .ev_par, .ev_len, .ev_dis, .ev_thresh, .ev_in_beat, .ev_out_beat,
    .ev_pkt_done, .ev_done_chan, .csum_wr, .csum_chan, .csum_val,
    .irq
  );

  mcsp_core u_core (
    .clk, .rst_n, .soft_rst,
    .cfg_en, .cfg_ch_en, .cfg_ch_mode, .cfg_ch_csum_en, .cfg_ch_par_en,
    .cfg_ch_maxlen, .cfg_ch_key, .cfg_thresh, .lut_flat, .inject_req, .inject_ack,
    .ext_pause,
    .s_valid, .s_ready, .s_data, .s_keep, .s_last, .s_chan, .s_par,
    .m_valid, .m_ready, .m_data, .m_keep, .m_last, .m_chan, .m_err,
    .busy, .in_empty, .in_full, .out_empty, .out_full, .in_level, .out_level,
    .ev_par, .ev_len, .ev_dis, .ev_thresh, .ev_in_beat, .ev_out_beat,
    .ev_pkt_done, .ev_done_chan, .csum_wr, .csum_chan, .csum_val
  );

endmodule
