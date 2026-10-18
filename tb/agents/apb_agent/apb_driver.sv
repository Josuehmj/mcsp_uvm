class apb_driver extends uvm_driver #(apb_seq_item);
    `uvm_component_utils(apb_driver)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual apb_if v_apb_interface;

    // build_phase
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db #(virtual apb_if)::get(this, "", "vif", v_apb_interface)) begin
            `uvm_fatal(get_type_name(), "Didn't get the handle to apb_if")
        end
    endfunction

    // run_phase
    task run_phase(uvm_phase phase);
        // Initialize signals in IDLE before the reset is triggered
        drive_idle();
        @(posedge v_apb_interface.clk iff v_apb_interface.rst_n === 1'b1);
        @(v_apb_interface.driver_cb); // wait an extra cycle for the DUT to stabilize 

        forever begin
            apb_seq_item item;
            seq_item_port.get_next_item(item);
            drive_transaction(item);
            seq_item_port.item_done();
        end
    endtask

    // drive_idle() - set the bus in IDLE 
    task drive_idle();
        v_apb_interface.driver_cb.psel      <= 1'b0;
        v_apb_interface.driver_cb.penable   <= 1'b0;
        v_apb_interface.driver_cb.pwrite    <= 1'b0;
        v_apb_interface.driver_cb.addr      <= '0;
        v_apb_interface.driver_cb.pwdata    <= '0;
    endtask

    // drive_transaction - drives a complete APB transaction
    task drive_transaction(apb_seq_item item);
        //setup phase 
        @(v_apb_interface.driver_cb);
        v_apb_interface.driver_cb.psel    <= 1'b1;
        v_apb_interface.driver_cb.penable <= 1'b0;
        v_apb_interface.driver_cb.pwrite  <= item.write;
        v_apb_interface.driver_cb.paddr   <= item.addr;
        v_apb_interface.driver_cb.pwdata  <= item.wdata;

        // access phase
        @(v_apb_interface.driver_cb);
        v_apb_interface.driver_cb.penable <= 1'b1;
        @(v_apb_interface.driver_cb);  // wait for pready. It is sampled just before each edge

        while (!v_apb_interface.driver_cb.pready) @(v_apb_interface.driver_cb);

        item.rdata  = v_apb_interface.driver_cb.prdata;
        item.slverr = v_apb_interface.driver_cb.pslverr;

        // end of transfer
        v_apb_interface.driver_cb.psel    <= 1'b0;
        v_apb_interface.driver_cb.penable <= 1'b0;        
    endtask
endclass