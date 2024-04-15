module wrap_dram(
    //system signals
    input                   sclk        ,
    input                   rstn        ,
    //control signals
    input                   mem_wr      ,
    input                   mem_rd      ,
    input           [2:0]   mem_op      ,
    input           [31:0]  addr        ,
    input           [31:0]  wdata       ,
    output  reg     [31:0]  rdata       
);


//=================================================================================
// Parameter declaration
//=================================================================================
localparam  SB_TYPE = 3'b000    ;
localparam  SH_TYPE = 3'b001    ;
localparam  SW_TYPE = 3'b010    ;

localparam  LB_TYPE = 3'b000    ;
localparam  LH_TYPE = 3'b001    ;
localparam  LW_TYPE = 3'b010    ;
localparam  LBU_TYPE = 3'b100   ;
localparam  LHU_TYPE = 3'b101   ;

//=================================================================================
// Signal declaration
//=================================================================================
wire            ram_cs      ;
reg     [3:0]   ram_we      ;
wire    [3:0]   ram_wen     ;
wire    [12:0]  ram_addr    ;
reg     [31:0]  ram_wdata   ;
wire    [31:0]  ram_rdata   ;

wire            RAM_CLK     ;
wire            RAM_CEN     ;
wire            RAM_WEN     ;
wire    [31:0]  RAM_BWEN    ;
wire    [12:0]  RAM_ADDR    ;
wire    [31:0]  RAM_WDATA   ;
wire    [31:0]  RAM_RDATA   ;
//=================================================================================
// Body
//=================================================================================
assign  ram_cs = mem_wr || mem_rd;
assign  ram_addr = addr[14:2];

//gen ram write enable
always @(*)begin
    if(mem_wr)
        case(mem_op)
            SB_TYPE : ram_we = 4'b0001 << addr[1:0];
            SH_TYPE : ram_we = 4'b0011 << addr[1:0];
            SW_TYPE : ram_we = 4'b1111;
            default : ram_we = 4'b0000;
        endcase
    else
        ram_we = 4'b0000;
end


//gen new wdata
always @(*)begin
        case(mem_op)
            SB_TYPE : begin
                if(addr[1:0] == 2'b00)
                    ram_wdata = {24'd0, wdata[7:0]};
                else if(addr[1:0] == 2'b01)
                    ram_wdata = {16'd0, wdata[7:0],8'd0};
                else if(addr[1:0] == 2'b10)
                    ram_wdata = {8'd0, wdata[7:0],16'd0};
                else if(addr[1:0] == 2'b11)
                    ram_wdata = {wdata[7:0],24'd0};
                else 
                    ram_wdata = 32'd0;
            end
            SH_TYPE : begin
                if(addr[1:0] == 2'b00)
                    ram_wdata = {16'd0, wdata[15:0]};
                //else if(addr[1:0] == 2'b10)
                //    ram_wdata = {8'd0,wdata[15:0],8'd0};
                else if(addr[1:0] == 2'b10)
                    ram_wdata = {wdata[15:0],16'd0};
                else 
                    ram_wdata = 32'd0;
            end
            SW_TYPE : ram_wdata = wdata;
            default : ram_wdata = 32'd0;
        endcase
end

//gen new rdata
reg     [2:0]   mem_op_r    ;
reg     [1:0]   addr_low2_r ;
always @(posedge sclk or negedge rstn) begin
    if(!rstn) begin
        mem_op_r <= 3'd0;
        addr_low2_r <= 2'b0;
    end
    else begin
        mem_op_r <= mem_op;
        addr_low2_r <= addr[1:0];        
    end
end

always @(*)begin
    case(mem_op_r)
        LB_TYPE : begin
            if(addr_low2_r == 2'b00)
                rdata = {{24{ram_rdata[7]}},ram_rdata[7:0]};
            else if(addr_low2_r == 2'b01)
                rdata = {{24{ram_rdata[15]}},ram_rdata[15:8]};
            else if(addr_low2_r == 2'b10)
                rdata = {{24{ram_rdata[23]}},ram_rdata[23:16]};
            else if(addr_low2_r == 2'b11)
                rdata = {{24{ram_rdata[31]}},ram_rdata[31:24]};
            else
                rdata = 32'd0;
        end
        LH_TYPE : begin
            if(addr_low2_r == 2'b00)
                rdata = {{16{ram_rdata[15]}},ram_rdata[15:0]};
            else if(addr_low2_r == 2'b10)
                rdata = {{16{ram_rdata[31]}},ram_rdata[31:16]};
            else
                rdata = 32'd0;
        end
        LW_TYPE : rdata = ram_rdata;

        LBU_TYPE : begin
            if(addr_low2_r == 2'b00)
                rdata = {24'd0,ram_rdata[7:0]};
            else if(addr_low2_r == 2'b01)
                rdata = {24'd0,ram_rdata[15:8]};
            else if(addr_low2_r == 2'b10)
                rdata = {24'd0,ram_rdata[23:16]};
            else if(addr_low2_r == 2'b11)
                rdata = {24'd0,ram_rdata[31:24]};
            else
                rdata = 32'd0;
        end
        LHU_TYPE : begin
            if(addr_low2_r == 2'b00)
                rdata = {16'd0,ram_rdata[15:0]};
            else if(addr_low2_r == 2'b10)
                rdata = {16'd0,ram_rdata[31:16]};
            else
                rdata = 32'd0;
        end
        default : rdata = 32'd0;
    endcase
end

`ifdef FPGA_SYN

ram_bfm #(
        .DATA_WHITH     ( 32            ),
        .DATA_SIZE      ( 8             ),
        .ADDR_WHITH     ( 13            ),
        .RAM_DEPTH      ( 8192          )
    )
    u_ram_8192_32(
    //system signals
    .clk                        ( sclk              ),
    //RAM Control signals
    .cs                         ( ram_cs            ),
    .we                         ( ram_we            ),
    .addr                       ( ram_addr          ),
    .wdata                      ( ram_wdata         ),
    .rdata                      ( ram_rdata         )
);

`else

//SRAM_4096_32 u_ram_data(
//    .QA       ( ram_rdata       ),     //port-A data output
//    .CLKA     ( sclk            ),     //port-A clock
//    .CENA     ( ram_cs          ),     //port-A chip enable
//    .WENA     ( ram_we          ),     //port-A write enable
//    .AA       ( ram_addr        ),     //port-A address
//    .DA       ( ram_wdata       ),     //port-A data input
//
//    .QB       (                 ),     //port-B data output
//    .CLKB     ( 1'b0            ),     //port-B clock
//    .CENB     ( 1'b0            ),     //port-B chip enable
//    .WENB     ( 4'd0            ),     //port-B write enable
//    .AB       ( 12'd0           ),     //port-B address
//    .DB       (                 ),     //port-B data input
//    
//    .EMAA     (     ),     
//    .EMAB     (     )
//);

assign ram_wen   = ~ram_we      ;
assign RAM_CLK   = sclk         ;
assign #1 RAM_CEN   = !ram_cs      ;
assign #1 RAM_WEN   = &ram_wen     ;
assign #1 RAM_BWEN  = {{8{ram_wen[3]}}, {8{ram_wen[2]}}, {8{ram_wen[1]}}, {8{ram_wen[0]}}};
assign #1 RAM_ADDR  = ram_addr     ;
assign #1 RAM_WDATA = ram_wdata    ;
assign ram_rdata = RAM_RDATA    ;


S55NLLGSPH_X512Y16D32_BW    u_ram_8192_32(
			.CLK     ( RAM_CLK   ),
			.CEN     ( RAM_CEN   ),
			.WEN     ( RAM_WEN   ),
            .BWEN    ( RAM_BWEN  ),
			.A       ( RAM_ADDR  ),
			.D       ( RAM_WDATA ),
            .Q       ( RAM_RDATA )
    );

`endif




endmodule
