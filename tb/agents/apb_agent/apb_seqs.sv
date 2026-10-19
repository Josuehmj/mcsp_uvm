// 1. base sequence
class apb_base_seq extends uvm_sequence #(apb_seq_item);
    `uvm_object_utils(apb_base_seq)

    function new(string name = "apb_base_seq");
        super.new(name);
    endfunction

    // single write
    task write(bit [11:0] addr, bit [31:0] data);
        apb_seq_item item = apb_seq_item::type_id::create("wr_item");
        start_item(item);
        if (!item.randomize() with {write == 1; addr == local::addr; wdata == local::data;})
            `uvm_fatal(get_type_name(), "randomize failed in write()")
        finish_item(item);
        `uvm_info(get_type_name(), item.convert2string(), UVM_HIGH)
        if (item.slverr)
            `uvm_error(get_type_name(),
                       $sformatf("Unexpected PSLVERR on write to 0x%03h", addr))
    endtask

    // single read
    task read (bit [11:0] addr, output bit [31:0] data);
        apb_seq_item item = apb_seq_item::type_id::create("rd_item");
        start_item(item);
        if (!item.randomize() with {write == 0; addr == local::addr})
            `uvm_fatal(get_type_name(), "randomize failed in read()")
        finish_item(item);
        `uvm_info(get_type_name(), item.convert2string(), UVM_HIGH)
        if (item.slverr)
            `uvm_error(get_type_name(),
                       $sformatf("Unexpected PSLVERR on read of 0x%03h", addr))
        data = item.rdata;
    endtask

endclass

// 2. One write
class apb_write_seq extends apb_base_seq;
    `uvm_object_utils(apb_write_seq)

    rand bit [11:0] addr;
    rand bit [31:0] data;

    function new(string name = "apb_write_seq");
        super.new(name);
    endfunction

    task body();
        write(addr, data);
    endtask
endclass

// 3. One read
class apb_read_seq extends apb_base_seq;
    `uvm_object_utils(apb_read_seq)

    rand bit [11:0] addr;
    rand bit [31:0] data;

    function new(string name = "apb_read_seq");
        super.new(name);
    endfunction

    task body();
        read(addr, data);
    endtask
endclass

// 4. Write the read back the same address and compare
class apb_write_read_seq extends apb_base_seq;
    `uvm_object_utils(apb_write_read_seq)

    rand bit [11:0] addr;
    rand bit [31:0] data;
         bit [31:0] mask = '1; 

         bit [31:0] readback;

    function new(string name = "apb_write_read_seq");
        super.new(name);
    endfunction

    task body();
        write(addr, data);
        read(addr, readback);
        if ((readback & mask) !== (data & mask))
            `uvm_error(get_type_name(),
                       $sformatf("Readback mismatch at 0x%03h: wrote 0x%08h, read 0x%08h (mask 0x%08h)",
                                 addr, data, readback, mask))
    endtask
endclass

// 5. Random traffic
class apb_random_seq extends apb_base_seq;
    `uvm_object_utils(apb_random_seq)

    rand int unsigned num_items;
    constraint c_num {num_items inside {[10:50]};}

    int unsigned wr_weight = 50;  // % of writes
    bit          safe      = 1;   // avoid register with side effects

    function new(string name = "apb_random_seq");
        super.new(name);
    endfunction

    task body();
        repeat (num_items) begin
            apb_seq_item item = apb_seq_item::type_id::create("rnd_item");
            start_item(item);
            if (!item.randomize() with {
                  write dist {1 := local::wr_weight, 0 := (100 - local::wr_weight)};

                  if (local::safe)
                    !(addr inside {12'h008, 12'h018, 12'h020, 12'h028});
               })
              `uvm_fatal(get_type_name(), "randomized failed in body()")
            finish_item(item);
            `uvm_info(get_type_name(), item.convert2string(), UVM_HIGH)
            if (item.slverr)
                `uvm_error(get_type_name(),
                           $sformatf("Unexpected PSLVERR: %s", item.convert2string()))
        end
    endtask
endclass

// 6 Error accesses
class apb_error_seq extends apb_base_seq;
    `uvm_object_utils(apb_error_seq)

    int unsigned repeats = 4;     // random accesses per case

    function new(string name = "apb_error_seq");
        super.new(name);
    endfunction

    task body();
        apb_seq_item item;

        for (int m = 0; m < 2; m++) begin
            for (int w = 0; w < 2; w++) begin
                repeat (repeats) begin
                    item = apb_seq_item::type_id::create(m ? "err_misaligned" : "err_unmapped");
                    start_item(item);
                    if (m == 0) begin
                        if (!item.randomize() with {
                            write == local::w;
                            addr[1:0] == 2'b00;
                            addr inside {[12'h038 : 12'h0FC],    // after the global register
                                         [12'h110 : 12'h11C],    // holes inside channel blocks
                                         [12'h130 : 12'h13C],
                                         [12'h150 : 12'h15C],
                                         [12'h170 : 12'h3FC],    // last hold and gap before LUT
                                         [12'h500 : 12'hFFC]};   // above LUT
                        })
                        `uvm_fatal(get_type_name(), "randomize failed (unmapped case)")
                    end else begin
                        if (!item.randomize() with {
                            write == local::w;
                            addr[1:0] !=  2'b00;
                        })
                       `uvm_fatal(get_type_name(), "randomize failed (misaligned case)")
                    end
                    finish_item(item);
                    `uvm_info(get_type_name(), item.convert2string(), UVM_HIGH)
                    if (item.slverr !== 1'b1)
                        `uvm_error(get_type_name(),
                                   $sformatf("Expected PSLVERR but gone none: %s", item.convert2string()))
                end
            end
        end
    endtask
endclass