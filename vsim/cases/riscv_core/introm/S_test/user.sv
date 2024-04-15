wire ram_clk = tbtop.U_CHIP_TOP.u_riscv_core.u_wrap_dram.sclk;
wire ram_cs = tbtop.U_CHIP_TOP.u_riscv_core.u_wrap_dram.ram_cs;
reg ram_cs_dly1 ;
always @(posedge ram_clk) begin
    ram_cs_dly1 <= ram_cs;
end


initial begin
    #1ns;
    @(posedge ram_cs_dly1 );
    #5ns;
    //while(1)begin
        #1ns;

            DRAM_DATA_CHECK(10'd0,32'h00ff_f014);
            DRAM_DATA_CHECK(10'd1,32'h00ff_f014);
            DRAM_DATA_CHECK(10'd2,32'h00ff_f014);
            DRAM_DATA_CHECK(10'd3,32'h00ff_f014);
            DRAM_DATA_CHECK(10'd4,32'h00ff_f014);

            DRAM_DATA_CHECK(10'd0,32'h00ff_1414);
            DRAM_DATA_CHECK(10'd1,32'h0014_f014);
            DRAM_DATA_CHECK(10'd2,32'h14FF_f014);
            DRAM_DATA_CHECK(10'd3,32'h00ff_f014);
            DRAM_DATA_CHECK(10'd4,32'hf014_f014);
    TEST_PASS;
end

task DRAM_DATA_CHECK;
    input   [9:0]   addr    ;
    input   [31:0]  edata   ;

    logic   [31:0]  ram_data;


    @(posedge ram_clk );
    if(ram_cs_dly1) begin
        ram_data = `TB_DRAM.mem_array[addr];
        if(ram_data !== edata) begin
            $display("* RAM_DATA[%x]: %x | EXP_DATA: %x => Error!!!",addr,ram_data, edata);
            #1us;
            TEST_FAIL;
        end
        $display("* RAM_DATA[%x]: %x | EXP_DATA: %x => OK!!!",addr, ram_data, edata);

    end
    else begin
            $display("* DRAM CS is High => Error!!!");
            TEST_FAIL;
    end
endtask
initial begin
    #100us;
    $display("\n----------------------------------------\n");
    $display("\t Timeout Error !!!!\n");
    TEST_FAIL;
end

