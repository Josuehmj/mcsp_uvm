// -----------------------------------------------------------------------------
// mcsp_fifo.sv
// Synchronous first-word-fall-through FIFO. DEPTH must be a power of two.
// - flush has priority over push/pop and empties the FIFO.
// - push while full and pop while empty are ignored.
// - dout is forced to zero while the FIFO is empty (no X on the read bus).
// -----------------------------------------------------------------------------
module mcsp_fifo #(
  parameter int unsigned WIDTH = 40,
  parameter int unsigned DEPTH = 16
) (
  input  logic                        clk,
  input  logic                        rst_n,
  input  logic                        flush,
  input  logic                        push,
  input  logic [WIDTH-1:0]            din,
  input  logic                        pop,
  output logic [WIDTH-1:0]            dout,
  output logic                        empty,
  output logic                        full,
  output logic [$clog2(DEPTH):0]      level
);

  localparam int unsigned AW = $clog2(DEPTH);

  logic [WIDTH-1:0] mem [DEPTH];
  logic [AW-1:0]    wr_ptr, rd_ptr;

  assign empty = (level == '0);
  assign full  = (level == DEPTH[AW:0]);
  assign dout  = empty ? '0 : mem[rd_ptr];

  wire do_push = push && !full;
  wire do_pop  = pop  && !empty;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      level  <= '0;
    end else if (flush) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      level  <= '0;
    end else begin
      if (do_push) begin
        mem[wr_ptr] <= din;
        wr_ptr      <= wr_ptr + 1'b1;
      end
      if (do_pop) rd_ptr <= rd_ptr + 1'b1;
      case ({do_push, do_pop})
        2'b10:   level <= level + 1'b1;
        2'b01:   level <= level - 1'b1;
        default: level <= level;
      endcase
    end
  end

endmodule
