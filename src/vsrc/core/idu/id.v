/*
这个Verilog代码定义了一个名为idu的硬件模块，它可能是处理器流水线中的一个阶段，这个模块主要负责处理来自上一个阶段的指令，并产生输出到下一阶段。这个模块的主要功能可以概括为以下几点：

与前后阶段的握手：这个模块通过一些信号(i_pre_valid, o_pre_ready, o_post_valid, i_post_ready)进行握手操作，以同步数据和控制流的传递。

数据和控制信号的输入：这个模块接收前阶段传递的一些信号，包括指令(i_ifu_ins)，程序计数器值(i_ifu_pc)，以及一些控制信号。

数据和控制信号的输出：这个模块生成并输出到下一阶段的一些信号，包括寄存器和CSR的读写控制信号，执行单元的控制信号，负载/存储单元的控制信号，分支跳转控制信号等。

指令解码：根据输入的指令(i_ifu_ins)，这个模块会对其进行解码，生成相应的控制信号。解码部分通过子模块idu_normal和idu_system完成，分别处理一般指令和系统指令的解码。

特殊指令的处理：对于一些特殊的指令（比如系统指令，空操作指令等），这个模块会进行特殊的处理，生成相应的控制信号。

总的来说，这个模块的作用是将前阶段的指令进行解码和处理，生成相应的控制信号，以控制后续阶段的执行流程。*/

`include "defines.v"

module idu (
  // 1. signal to pipe shake hands:
  input  logic                      i_clk         ,
  input  logic                      i_rst_n       ,
  input  logic                      i_flush       ,
  input  logic                      i_pre_nop     ,
  input  logic                      i_pre_stall   ,
  input  logic                      i_pre_valid   ,   // from pre-stage
  output logic                      o_pre_ready   ,   //  to  pre-stage
  output logic                      o_post_valid  ,   //  to  post-stage
  input  logic                      i_post_ready  ,   // from post-stage

  // 2. input comb signal from pre stage:
  input  logic [`INS_WIDTH-1:0]     i_ifu_ins     ,
  input  logic [`CPU_WIDTH-1:0]     i_ifu_pc      ,

  // 3. output comb signal to post stage:

  // 3.1 for bypass to get reg value.
  output logic [`REG_ADDRW-1:0]     o_idu_rs1id   ,
  output logic [`REG_ADDRW-1:0]     o_idu_rs2id   ,
  output logic [`CSR_ADDRW-1:0]     o_idu_csrsid  ,
  output logic                      o_idu_csrsren , // csr source read enable.
  // 3.2 for exu:
  output logic                      o_idu_sysins  ,
  output logic [`CPU_WIDTH-1:0]     o_idu_imm     ,
  output logic [`EXU_SEL_WIDTH-1:0] o_idu_exsrc   ,
  output logic [`EXU_OPT_WIDTH-1:0] o_idu_exopt   ,
  output logic                      o_idu_excsrsrc,
  output logic [`CSR_OPT_WIDTH-1:0] o_idu_excsropt,
  // 3.3 for exu, dealy to use for lsu:
  output logic [2:0]                o_idu_lsfunc3 ,
  output logic                      o_idu_lden    ,
  output logic                      o_idu_sten    ,
  output logic                      o_idu_fencei  ,
  // 3.4 for exu, dealy to use for wbu:
  output logic [`REG_ADDRW-1:0]     o_idu_rdid    ,
  output logic                      o_idu_rdwen   ,
  output logic [`CSR_ADDRW-1:0]     o_idu_csrdid  ,
  output logic                      o_idu_csrdwen , // csr dest write enable.
  // 3.5 for bru:
  output logic                      o_idu_jal     ,
  output logic                      o_idu_jalr    ,
  output logic                      o_idu_brch    ,
  output logic [2:0]                o_idu_bfun3   ,
  // 3.6 for next stage to pipe:
  output logic [`CPU_WIDTH-1:0]     o_idu_pc      ,
  output logic                      o_idu_ecall   ,
  output logic                      o_idu_mret    ,
  output logic                      o_idu_nop     ,
  output logic [`INS_WIDTH-1:0]     s_idu_ins
);

  // 1. shake hands to reg pre stage signals://///////////////////////////////////////////////////////////////

  // i_pre_valid --> ⌈‾‾‾‾⌉ --> o_post_valid
  //                 |REG|
  // o_pre_ready <-- ⌊____⌋ <-- i_post_ready

  wire pre_sh;
  assign o_pre_ready =  o_post_valid & i_post_ready & (!i_pre_stall) | !o_post_valid ;
  assign pre_sh = i_pre_valid & o_pre_ready;

  logic [`CPU_WIDTH-1:0] ifu_pc , ifu_pc_r;
  logic [`INS_WIDTH-1:0] ifu_ins, ifu_ins_r;
  logic                  ifu_nop_r;

  assign ifu_pc     = i_ifu_pc;
  assign ifu_ins    = i_pre_nop ? `INS_WIDTH'h13 : i_ifu_ins;  // 0x13 == ADDI x0,x0,0 == nop.

  stl_reg #(
    .WIDTH      (`CPU_WIDTH+`INS_WIDTH+1),
    .RESET_VAL  (0                    )
  ) prereg (
  	.i_clk      (i_clk                ),
    .i_rst_n    (i_rst_n              ),
    .i_wen      (i_flush | pre_sh     ),
    .i_din      (i_flush ? 0: {ifu_ins  , ifu_pc  , i_pre_nop}),
    .o_dout     (             {ifu_ins_r, ifu_pc_r, ifu_nop_r})
  );

  // 2. generate valid signals for post stage://////////////////////////////////////////////////////////////////

  stl_reg #(
    .WIDTH      (1            ), 
    .RESET_VAL  (0            )
  ) postvalid (
  	.i_clk      (i_clk        ), 
    .i_rst_n    (i_rst_n      ), 
    .i_wen      (i_flush | o_pre_ready       ), 
    .i_din      (i_flush ? 1'b0 : i_pre_valid), 
    .o_dout     (o_post_valid )
  );

  // 3. use pre stage signals to generate comb logic for post stage://////////////////////////////////////////

  //                        normal decode:  system decode:
  logic [`REG_ADDRW-1:0]     nom_rs1id    , sys_rs1id   ;
  logic [`REG_ADDRW-1:0]     nom_rs2id    ; 
  logic [`CSR_ADDRW-1:0]                    sys_csrsid  ; 
  logic                                     sys_csrsren ; 
  logic [`CPU_WIDTH-1:0]     nom_imm      , sys_imm     ;
  logic [`EXU_SEL_WIDTH-1:0] nom_exsrc    ;  
  logic [`EXU_OPT_WIDTH-1:0] nom_exopt    ;  
  logic                                     sys_excsrsel;
  logic [`CSR_OPT_WIDTH-1:0]                sys_excsropt;
  logic [2:0]                nom_lsu_func3;
  logic                      nom_lsu_lden ;
  logic                      nom_lsu_sten ;
  logic [`REG_ADDRW-1:0]     nom_rdid     , sys_rdid    ;
  logic                      nom_rdwen    , sys_rdwen   ;
  logic [`CSR_ADDRW-1:0]                    sys_csrdid  ;
  logic                                     sys_csrdwen ;
  logic                      nom_jal      ;
  logic                      nom_jalr     ;
  logic                      nom_brch     ;
  logic [2:0]                nom_bfun3    ;

  idu_normal u_idu_normal(
    .i_ins       (ifu_ins_r     ),
    .o_rs1id     (nom_rs1id     ),
    .o_rs2id     (nom_rs2id     ),
    .o_imm       (nom_imm       ),
    .o_src_sel   (nom_exsrc     ),
    .o_exopt     (nom_exopt     ),
    .o_lsu_func3 (nom_lsu_func3 ),
    .o_lsu_lden  (nom_lsu_lden  ),
    .o_lsu_sten  (nom_lsu_sten  ),
    .o_rdid      (nom_rdid      ),
    .o_rdwen     (nom_rdwen     ),
    .o_jal       (nom_jal       ),
    .o_jalr      (nom_jalr      ),
    .o_brch      (nom_brch      ),
    .o_bfun3     (nom_bfun3     )
  );

  idu_system u_idu_system(
  	.i_ins       (ifu_ins_r     ),
    .o_rs1id     (sys_rs1id     ),
    .o_csrsid    (sys_csrsid    ),
    .o_csrsren   (sys_csrsren   ),
    .o_imm       (sys_imm       ),
    .o_excsrsrc  (sys_excsrsel  ),
    .o_excsropt  (sys_excsropt  ),
    .o_rdid      (sys_rdid      ),
    .o_rdwen     (sys_rdwen     ),
    .o_csrdid    (sys_csrdid    ),
    .o_csrdwen   (sys_csrdwen   )
  );

  wire [2:0] func3  = ifu_ins_r[14:12];
  wire [6:0] opcode = ifu_ins_r[ 6: 0];

  assign o_idu_sysins = (opcode == `TYPE_SYS);

  assign o_idu_rs1id    = o_idu_sysins ? sys_rs1id      : nom_rs1id     ;
  assign o_idu_rs2id    = o_idu_sysins ? `REG_ADDRW'b0  : nom_rs2id     ;
  assign o_idu_csrsid   = o_idu_sysins ? sys_csrsid     : `CSR_ADDRW'b0 ;
  assign o_idu_csrsren  = o_idu_sysins ? sys_csrsren    : 1'b0          ;
  assign o_idu_imm      = o_idu_sysins ? sys_imm        : nom_imm       ;
  assign o_idu_exsrc    = o_idu_sysins ? `EXU_SEL_IMM   : nom_exsrc     ;
  assign o_idu_exopt    = o_idu_sysins ? `EXU_NOP       : nom_exopt     ;
  assign o_idu_excsropt = o_idu_sysins ? sys_excsropt   : `CSR_NOP      ;
  assign o_idu_excsrsrc = o_idu_sysins ? sys_excsrsel   : `CSR_SEL_IMM  ;
  assign o_idu_lsfunc3  = o_idu_sysins ? 3'b0           : nom_lsu_func3 ;
  assign o_idu_lden     = o_idu_sysins ? 1'b0           : nom_lsu_lden  ;
  assign o_idu_sten     = o_idu_sysins ? 1'b0           : nom_lsu_sten  ;
  assign o_idu_rdid     = o_idu_sysins ? sys_rdid       : nom_rdid      ;
  assign o_idu_rdwen    = o_idu_sysins ? sys_rdwen      : nom_rdwen     ;
  assign o_idu_csrdid   = o_idu_sysins ? sys_csrdid     : `CSR_ADDRW'b0 ;
  assign o_idu_csrdwen  = o_idu_sysins ? sys_csrdwen    : 1'b0          ;
  assign o_idu_jal      = o_idu_sysins ? 1'b0           : nom_jal       ;
  assign o_idu_jalr     = o_idu_sysins ? 1'b0           : nom_jalr      ;
  assign o_idu_brch     = o_idu_sysins ? 1'b0           : nom_brch      ;
  assign o_idu_bfun3    = o_idu_sysins ? 3'b0           : nom_bfun3     ;
  assign o_idu_pc       = ifu_pc_r     ;
  assign o_idu_nop      = ifu_nop_r    ;

  assign o_idu_fencei   = (opcode == `TYPE_FENCE) & (func3 == 3'b001);
  assign o_idu_ecall    = o_idu_sysins & !(|ifu_ins_r[31:7]);
  assign o_idu_mret     = o_idu_sysins & !(|ifu_ins_r[31:30]) & (&ifu_ins_r[29:28]) & !(|ifu_ins_r[27:22]) & ifu_ins_r[21] & !(|ifu_ins_r[20:7]);

  assign s_idu_ins      = ifu_ins_r    ;

endmodule
