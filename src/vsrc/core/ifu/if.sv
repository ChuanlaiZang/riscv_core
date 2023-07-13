/*
这是一个硬件描述语言（HDL）的模块，用于处理指令取取（Instruction Fetch Unit, IFU）部分的操作。以下是对代码的总结：

该模块的输入包括时钟信号i_clk，复位信号i_rst_n，下一PC值i_next_pc，flush信号以及来自后续阶段的就绪信号i_post_ready。它的输出包括向后续阶段发送的o_post_valid，以及 IFU 的 PC 和指令输出o_ifu_pc 和o_ifu_ins。

模块内部，prereg存储器用于存储下一个PC值。如果来自后续阶段的就绪信号或flush信号为真，那么它将更新PC值。

接下来的代码段是从统一接口（UNI IF）读取指令。当后续阶段未准备就绪(wait_post_ready)时，它会发出读取请求。接口的请求类型被设置为读取（REQ_READ），请求大小为32位。

unidatareg存储器被用来存储从 UNI IF 接口读取的数据。当接口有效且准备就绪时，该数据被写入存储器。

unireadyreg寄存器用于控制wait_post_ready的状态，其根据flush，post_sh以及UniIf_Sh信号变化。

模块最后部分，通过组合逻辑产生向后续阶段发送的信号o_post_valid，o_ifu_pc，和o_ifu_ins。

这个模块大概描述了一个取指单元的操作：从缓存/DDR中读取指令，保存指令和对应的PC，以及与前后阶段握手的逻辑。
*/

`include "defines.v"
module ifu (
  input                           i_clk       ,
  input                           i_rst_n     ,

  // 1. cache interface to get data from cache/ddr:
  uni_if.Master                   iCacheIf_M  ,

  // 2. signal to pipe shake hands:
  input                           i_flush     ,
  output                          o_post_valid,   //  to  post-stage
  input                           i_post_ready,   // from post-stage

  // 3. input signal from pre stage:
  input         [`CPU_WIDTH-1:0]  i_next_pc   ,

  // 4. output signal to post stage:
  output logic  [`CPU_WIDTH-1:0]  o_ifu_pc    ,
  output logic  [`INS_WIDTH-1:0]  o_ifu_ins
);

  // 1. shake hands to reg pre stage signals://///////////////////////////////////////////////////////////////
  // remind: there is no shake hands signals from pre stage for ifu, so just use post stage signals to shank hands.

  logic  [`CPU_WIDTH-1:0]  next_pc_r;

  wire post_sh = o_post_valid & i_post_ready;

  stl_reg #(
    .WIDTH     (`CPU_WIDTH          ),
    .RESET_VAL (`CPU_WIDTH'h80000000)
  ) prereg (
    .i_clk   (i_clk       ),
    .i_rst_n (i_rst_n     ),
    .i_wen   (post_sh | i_flush    ),
    .i_din   (i_next_pc   ),
    .o_dout  (next_pc_r   )
  );

  // 2. use interface to read ins ://////////////////////////////////////////

  // ⌈‾‾‾‾⌉              ⌈‾‾‾‾⌉ ready --> | --> o_post_valid
  // |REG|              |UNIF|          | 
  // ⌊____⌋    --> valid ⌊____⌋           | <-- i_post_ready

  logic wait_post_ready;
  logic [`INS_WIDTH-1:0] unif_rdata, unif_rdata_r;
  assign iCacheIf_M.valid  = !wait_post_ready ;
  assign iCacheIf_M.size   = 2'b10        ; // 32 bit.
  assign iCacheIf_M.reqtyp = `REQ_READ    ;
  assign iCacheIf_M.wdata  = `INS_WIDTH'b0; // no use.
  assign iCacheIf_M.addr   = next_pc_r[`ADR_WIDTH-1:0];
  assign unif_rdata = iCacheIf_M.rdata[`INS_WIDTH-1:0];

  // 3. use one register to save data/valid for post stage :///////////////////

  wire UniIf_Sh = iCacheIf_M.valid & iCacheIf_M.ready;

  stl_reg #(
    .WIDTH      (`INS_WIDTH   ),
    .RESET_VAL  (`INS_WIDTH'b0)
  ) unidatareg (
  	.i_clk      (i_clk        ),
    .i_rst_n    (i_rst_n      ),
    .i_wen      (UniIf_Sh     ),
    .i_din      (unif_rdata   ),
    .o_dout     (unif_rdata_r )
  );

  stl_reg #(
    .WIDTH      (1   ),                                       //  always_ff @(posedge i_clk or negedge i_rst_n) begin
    .RESET_VAL  (1'b0)                                        //    if(!i_rst_n)begin
  ) unireadyreg (                                             //      wait_post_ready <= 1'b0;
  	.i_clk      (i_clk                ),            // <==>   //    end else if(i_flush | post_sh)begin
    .i_rst_n    (i_rst_n              ),                      //      wait_post_ready <= 1'b0;
    .i_wen      (i_flush | post_sh | UniIf_Sh),               //    end else if(UniIf_Sh)begin
    .i_din      (!(i_flush | post_sh) ),                      //      wait_post_ready <= 1'b1;
    .o_dout     (wait_post_ready      )                       //    end
  );                                                          //  end

  // 4. use pre stage signals to generate comb logic for post stage://////////////////////////////////////////

  assign o_post_valid = UniIf_Sh | wait_post_ready; 
  assign o_ifu_pc     = next_pc_r;
  assign o_ifu_ins    = UniIf_Sh ? unif_rdata : unif_rdata_r;

endmodule
