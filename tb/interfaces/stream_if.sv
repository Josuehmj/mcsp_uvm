// Generic interface for stream input and output

interface stream_if (input logic clk, input logic rst_n);
    logic        valid;
    logic        ready;
    logic [31:0] data;
    logic [3:0]  keep;
    logic        last;
    logic [1:0]  chan;
    logic        par_err; // s_par on the input, m_error on the output
endinterface