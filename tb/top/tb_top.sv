`timescale 1ns/1ps

module tb_top;
    import uvm_pkg::*;
    import test_pkg::*;

    `include "uvm_macros.svh"

    // clock and reset
    bit clk;
    logic rst_n;


    always #10 clk <= ~clk;

    initial begin
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
    end

    // Interfaces an DUT instances
    apb_if          apb_vif           (clk, rst_n);
    stream_if       stream_vifin      (clk, rst_n);
    stream_if       stream_vifout     (clk, rst_n);
    sideband_if     sideband_vif      (clk, rst_n);
    irq_if          irq_vif           (clk, rst_n);

    mcsp_top dut (
        .clk        (clk),
        .rst_n      (rst_n), 

        // APB3 slave
        .psel       (apb_vif.psel),
        .penable    (apb_vif.penable),
        .pwrite     (apb_vif.pwrite),
        .paddr      (apb_vif.paddr), 
        .pwdata     (apb_vif.pwdata),
        .prdata     (apb_vif.prdata),
        .pready     (apb_vif.pready),
        .pslverr    (apb_vif.pslverr),

        // Stream input
        .s_valid    (stream_vifin.valid),
        .s_ready    (stream_vifin.ready),
        .s_data     (stream_vifin.data),
        .s_keep     (stream_vifin.keep),
        .s_last     (stream_vifin.last),
        .s_chan     (stream_vifin.chan),
        .s_par      (stream_vifin.par_err),

        // Stream output
        .m_valid    (stream_vifout.valid),
        .m_ready    (stream_vifout.ready),
        .m_data     (stream_vifout.data),
        .m_keep     (stream_vifout.keep),
        .m_last     (stream_vifout.last),
        .m_chan     (stream_vifout.chan),
        .m_err      (stream_vifout.par_err),

        // Sideband
        .ext_pause  (sideband_vif.ext_pause),
        .busy       (sideband_vif.busy),

        // Interrupt
        .irq        (irq_vif.irq)
    );

    initial begin
        uvm_config_db #(virtual apb_if      )::set (null, "uvm_test_top.env.apb_agent*",        "vif", apb_vif);
        uvm_config_db #(virtual stream_if   )::set (null, "uvm_test_top.env.stream_in_agent*",  "vif", stream_vifin);
        uvm_config_db #(virtual stream_if   )::set (null, "uvm_test_top.env.stream_out_agent*", "vif", stream_vifout);
        uvm_config_db #(virtual sideband_if )::set (null, "uvm_test_top.env.sideband_agent*",   "vif", sideband_vif);
        uvm_config_db #(virtual irq_if      )::set (null, "uvm_test_top.env.irq_agent*",        "vif", irq_vif);

        run_test();
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end
endmodule