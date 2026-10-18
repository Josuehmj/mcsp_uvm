class apb_monitor extends uvm_monitor;
    `uvm_component_utils(apb_monitor)

    virtual apb_if v_apb_interface;

    uvm_analysis_port #(apb_seq_item) apb_mon_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // build_phase 
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        apb_mon_ap = new("apb_mon_ap", this);
        if(!uvm_config_db #(virtual apb_if)::get(this, "", "vif", v_apb_interface)) begin
            `uvm_fatal(get_type_name(), "Didn't get the handle to apb_if")
        end
    endfunction

    // run_phase
    task run_phase(uvm_phase phase);
        // wait for the reset to finish before starting monitoring
        @(posedge v_apb_interface.clk iff v_apb_interface.rst_n === 1'b1);

        forever begin
            collect_transaction();
        end
    endtask

    // collec_transaction() - captures a complete APB transaction
    task collect_transaction();
        apb_seq_item item;
        item = apb_seq_item::type_id::create("apb_mon_item");

        // wait setup phase
        @(v_apb_interface.monitor_cb iff (v_apb_interface.monitor_cb.psel === 1'b1 &&
                                         v_apb_interface.monitor_cb.penable === 1'b0));

        // capture the setup fields
        item.addr  = v_apb_interface.monitor_cb.paddr;
        item.write = v_apb_interface.monitor_cb.pwrite;
        item.wdata = v_apb_interface.monitor_cb.pwdata;

        // wait for the access phase to finish
        @(v_apb_interface.monitor_cb iff (v_apb_interface.monitor_cb.psel    === 1'b1 &&
                                          v_apb_interface.monitor_cb.penable === 1'b1 &&
                                          v_apb_interface.monitor_cb.pready  === 1'b1));

        // capture the response
        item.rdata  = v_apb_interface.monitor_cb.prdata;
        item.slverr = v_apb_interface.monitor_cb.pslverr;

        // log and publication
        `uvm_info("APB_MON", item.convert2string(), UVM_HIGH)
        apb_mon_ap.write(item);
    endtask
endclass