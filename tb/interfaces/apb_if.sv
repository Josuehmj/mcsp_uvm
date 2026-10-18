`timescale 1ns/1ps

interface apb_if (input logic clk, input logic rst_n);
    logic            psel;
    logic            penable;
    logic            pwrite;
    logic [11:0]     paddr;
    logic [31:0]     pwdata;
    logic [31:0]     prdata;
    logic            pready;
    logic            pslverr;

    // Driver clocking block
    clocking driver_cb @(posedge clk);
        default output #1; // setup time window

        output psel;
        output penable;
        output pwrite;
        output paddr;
        output pwdata;

        input  prdata;
        input  pready;
        input  pslverr;
    endclocking

    // Monitor clocking block
    clocking monitor_cb @(posedge clk);
        default input #1; // hold time window

        input psel;
        input penable;
        input pwrite;
        input paddr;
        input pwdata;
        input prdata;
        input pready;
        input pslverr;
    endclocking

    // Modports
    modport driver_mp  (clocking driver_cb, input clk, input rst_n);
    modport monitor_mp (clocking monitor_cb, input clk, input rst_n);

endinterface