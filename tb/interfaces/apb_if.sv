interface apb_if (input logic clk, input logic rst_n);
    logic            psel;
    logic            penable;
    logic            pwrite;
    logic [11:0]     paddr;
    logic [31:0]     pwdata;
    logic [31:0]     prdata;
    logic            pready;
    logic            pslverr;
endinterface