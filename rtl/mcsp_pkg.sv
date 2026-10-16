// -----------------------------------------------------------------------------
// mcsp_pkg.sv
// Multi-Channel Stream Processor (MCSP) - shared constants and address map
// -----------------------------------------------------------------------------
package mcsp_pkg;

  // ---- Design parameters ----------------------------------------------------
  localparam int unsigned NUM_CH     = 4;    // number of stream channels
  localparam int unsigned FIFO_DEPTH = 16;   // input and output FIFO depth (beats)
  localparam int unsigned LUT_WORDS  = 64;   // LUT RAM size in 32-bit words (256 bytes)

  // ---- Global register offsets (APB byte addresses) ------------------------
  localparam logic [11:0] ADDR_ID          = 12'h000;
  localparam logic [11:0] ADDR_VERSION     = 12'h004;
  localparam logic [11:0] ADDR_CTRL        = 12'h008;
  localparam logic [11:0] ADDR_STATUS      = 12'h00C;
  localparam logic [11:0] ADDR_IRQ_STATUS  = 12'h010;
  localparam logic [11:0] ADDR_IRQ_MASK    = 12'h014;
  localparam logic [11:0] ADDR_IRQ_FORCE   = 12'h018;
  localparam logic [11:0] ADDR_THRESH      = 12'h01C;
  localparam logic [11:0] ADDR_DBG_CTRL    = 12'h020;
  localparam logic [11:0] ADDR_SCRATCH     = 12'h024;
  localparam logic [11:0] ADDR_ERR_CNT     = 12'h028;
  localparam logic [11:0] ADDR_PKT_CNT_TOT = 12'h02C;
  localparam logic [11:0] ADDR_IN_BEATS    = 12'h030;
  localparam logic [11:0] ADDR_OUT_BEATS   = 12'h034;

  // ---- Per-channel register block -------------------------------------------
  // Channel n base = ADDR_CH_BASE + n * ADDR_CH_STRIDE
  localparam logic [11:0] ADDR_CH_BASE     = 12'h100;
  localparam logic [11:0] ADDR_CH_STRIDE   = 12'h020;
  localparam logic [11:0] CH_OFF_CTRL      = 12'h000;
  localparam logic [11:0] CH_OFF_KEY       = 12'h004;
  localparam logic [11:0] CH_OFF_PKT_CNT   = 12'h008;
  localparam logic [11:0] CH_OFF_LAST_CSUM = 12'h00C;

  // ---- LUT RAM --------------------------------------------------------------
  localparam logic [11:0] ADDR_LUT_BASE    = 12'h400;   // 64 words: 0x400 .. 0x4FC

  // ---- Constant register values ---------------------------------------------
  localparam logic [31:0] DEVICE_ID        = 32'h5645_5249;  // ASCII "VERI"
  localparam logic [31:0] DEVICE_VERSION   = 32'h0001_0000;  // 1.0

  // ---- Per-channel transform modes ------------------------------------------
  localparam logic [2:0] MODE_BYPASS   = 3'd0;
  localparam logic [2:0] MODE_XOR      = 3'd1;
  localparam logic [2:0] MODE_ADD      = 3'd2;
  localparam logic [2:0] MODE_BSWAP    = 3'd3;
  localparam logic [2:0] MODE_BREV     = 3'd4;
  localparam logic [2:0] MODE_LUT      = 3'd5;
  localparam logic [2:0] MODE_ROTL     = 3'd6;
  localparam logic [2:0] MODE_SCRAMBLE = 3'd7;

endpackage
