class apb_seq_item extends uvm_sequence_item;
    // stimulus fields
    rand bit        write;      // 1 = write, 0 = read
    rand bit [11:0] addr;
    rand bit [31:0] wdata;     // only meaningful when write == 1

    // response fields - never randomized
    bit [31:0]      rdata;  // only meaningful when write == 0
    bit             slverr;

    `uvm_object_utils(apb_seq_item)

    function new(string name = "apb_seq_item");
        super.new(name);
    endfunction

    // constraints
    constraint c_aligned {soft addr[1:0] == 2'b00;}

    constraint c_mapped {
        addr inside {
            [12'h000 : 12'h034],  // global registers
            [12'h100 : 12'h10C],  // channel 0
            [12'h120 : 12'h12C],  // channel 1
            [12'h140 : 12'h14C],  // channel 2
            [12'h160 : 12'h16C],  // channel 3
            [12'h400 : 12'h4FC]   // LUT RAM
        };
    }

    // without weight, the LUT RAM would dominate because it holds the most addresses
    constraint c_region_weight {
        soft addr dist {
            [12'h000 : 12'h034] :/ 40,
            [12'h100 : 12'h16C] :/ 40,
            [12'h400 : 12'h4FC] :/ 20
        };     
    }

    constraint c_wdata_on_read {soft (write == 0) -> wdata == 32'h0;}


    // utility methods
    virtual function string convert2string();
        return $sformatf(
            "APB %s addr=0x%08h wdata=0x%08h rdata=0x%08h slverr=%0b",
            write ? "WR" : "RD",
            addr, wdata, rdata, slverr
        );
    endfunction

    virtual function void do_copy(uvm_object rhs);
        apb_seq_item rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal(get_type_name(), "do_copy: cast failed")
        super.do_copy(rhs);
        addr   = rhs_.addr;
        write  = rhs_.write;
        wdata  = rhs_.wdata;
        rdata  = rhs_.rdata;
        slverr = rhs_.slverr;
    endfunction

    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        apb_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (super.do_compare(rhs, comparer) &&
                addr   === rhs_.addr            &&
                write  === rhs_.write           &&
                wdata  === rhs_.wdata           &&
                rdata  === rhs_.rdata           &&
                slverr === rhs_.slverr);
    endfunction
endclass