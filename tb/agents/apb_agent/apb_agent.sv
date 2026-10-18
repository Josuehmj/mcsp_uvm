class apb_agent extends uvm_agent;
    `uvm_component_utils(apb_agent)

    // Components
    apb_sequencer   sequencer;
    apb_driver      driver;
    apb_monitor     monitor;

    // Analysis port - exposed for connections to the scoreboard and coverage collector
    uvm_analysis_port #(apb_seq_item) apb_mon_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // build_phase
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        apb_mon_ap = new("apb_mon_ap", this);
        
        if (get_is_active()) begin
            sequencer  = apb_sequencer::type_id::create("sequencer", this);
            driver     = apb_driver::type_id::create("driver", this);
        end

        monitor = apb_monitor::type_id::create("monitor", this);
    endfunction

    // connect_phase - connect the driver to the sequencer and expose the monitor's apb
    function void connect_phase(uvm_phase phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
        monitor.apb_mon_ap.connect(apb_mon_ap);
    endfunction
endclass