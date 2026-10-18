package apb_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // 
  `include "apb_seq_item.sv"     // transaction (used by everything below)
  `include "apb_sequencer.sv"    // needs apb_seq_item
  `include "apb_driver.sv"       // needs apb_seq_item
  `include "apb_monitor.sv"      // needs apb_seq_item
  `include "apb_agent.sv"        // needs sequencer, driver and monitor
  `include "apb_seqs.sv"

  // Future file
  // `include "apb_reg_adapter.sv"  

endpackage