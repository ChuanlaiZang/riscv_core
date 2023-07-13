/*
这段代码是一个处理器核心的顶层模块，涉及了一系列计算机架构的组成部分，如指令获取单元(IFU)，指令译码单元(IDU)，执行单元(EXU)，以及加载存储单元(LSU)。

一些主要特征和功能如下：

在输入和输出方面，该模块接收时钟信号、复位信号，并与统一接口（uni_if.Master）的iCache和dCache交互，它还产生了两个输出，即o_invalidIChe和o_cleanDChe。

在该模块中定义了一系列的控制信号，用于管理各个单元之间的交互和状态控制，例如，决定是否跳过某个单元的执行（_nop），是否触发了异常或中断（_excall, *_mret, *_excp, _intr），以及用于描述各个单元正在处理的程序计数器值（_pc）等。

定义了一些模拟信号，这些信号可能在仿真过程中使用，例如，s_a0zero，s_lsu_device，s_wbu_device等。

模块中包含了处理器的各个主要部分的实例，包括ifu、idu、exu和lsu。这些实例包含了输入和输出，涉及到一些信号的传递，例如，指令数据（_ins），寄存器数据（_rs1, _rs2），系统指令（_sysins）等。

这个模块的主要作用是协调这些处理器部分的工作，它通过分配一些逻辑信号和状态标志，实现各个处理器部分的正确交互，同时确保处理器核心的正常运行。

中断和异常处理单元（IRU）：负责处理中断和异常，当接收到中断或异常信号时，会将其传递给其它模块，比如WBU模块。

CLINT模块：实例化一个定时器和一个软件中断模块，这是RISC-V架构中常见的模块。它包括机器定时器中断（MTIP）和软件中断。

bypass模块：在处理器中，当数据准备就绪时，bypass模块可以直接将数据从一个流水线阶段传递到下一个阶段，而不用等待整个周期，这可以降低数据冒险（data hazard）带来的延迟。

CSR文件：CSR文件是一个模块，它存储了处理器的状态信息，例如程序计数器（PC），以及处理器的其他状态寄存器。

分支单元（BRU）：负责处理分支指令，例如jal（跳转并链接）和jalr（跳转并链接寄存器）等。

最后一部分代码是针对模拟测试的代码，这部分使用了DPI-C接口（Direct Programming Interface in C），在Verilog代码中调用了C语言的函数，用于在模拟器中模拟测试和验证CPU的功能。

这段代码通过实例化和连接各种模块来构建一个处理器的顶层设计。这是硬件设计语言（HDL）中常见的方法，通过模块化设计，可以更好地管理和组织复杂的硬件设计。
*/



`include "defines.v"
module core_top(
  input                 i_clk         ,
  input                 i_rst_n       ,
  uni_if.Master         iCacheIf_M    ,
  uni_if.Master         dCacheIf_M    ,
  output                o_invalidIChe ,
  output                o_cleanDChe
);

  // control signals:
  logic [`CPU_WIDTH-1:0]  pre_pc, ifu_pc, idu_pc, exu_pc, lsu_pc, wbu_pc, iru_pc;
  logic [`INS_WIDTH-1:0]  ifu_ins;
  logic                   idu_nop,   exu_nop,   lsu_nop,   wbu_nop  ;
  logic                   idu_ecall, exu_ecall, lsu_ecall, wbu_ecall;
  logic                   idu_mret,  exu_mret,  lsu_mret,  wbu_mret ;
  
  logic                   clint_ren  , clint_wen  , clint_mtip;
  logic [`ADR_WIDTH-1:0]  clint_raddr, clint_waddr;
  logic [`CPU_WIDTH-1:0]  clint_rdata, clint_wdata;

  logic                   ifid_nop;               // for branch adventure
  logic                   ifid_stall, idex_nop;   // for data adventure
  logic                   ifu_valid , ifu_ready;  // pipeline shakehands: pc/if -> if/id
  logic                   idu_valid , idu_ready;  // pipeline shakehands: if/id -> id/ex
  logic                   exu_valid , exu_ready;  // pipeline shakehands: id/ex -> ex/ls
  logic                   lsu_valid , lsu_ready;  // pipeline shakehands: ex/ls -> ls/wb
  logic                   wbu_valid , wbu_ready;  // pipeline shakehands: ls/wb -> wb/reg.
  logic                   iru_excp  , iru_intr;
  logic                   wbu_commit;             // wbu_valid & wbu_ready & !iru_intr.
  logic                   unif_trans_done, iru_flush, fence_flush, lsu_fencei;
  logic                   ifu_flush, idu_flush, exu_flush, lsu_flush, wbu_flush;

  assign unif_trans_done = (iCacheIf_M.valid & iCacheIf_M.ready | !iCacheIf_M.valid);
  assign wbu_ready = (iru_excp | iru_intr) ? unif_trans_done: 1'b1;         // if excp/intr, waiting for unif done.
  assign iru_flush = (iru_excp | iru_intr) & (wbu_valid & wbu_ready);       // iru_intr not commit.

  assign fence_flush = dCacheIf_M.valid & dCacheIf_M.ready & lsu_fencei;
  assign ifu_flush = fence_flush | iru_flush;
  assign idu_flush = fence_flush | iru_flush;
  assign exu_flush = fence_flush | iru_flush;
  assign lsu_flush = fence_flush | iru_flush;
  assign wbu_flush = iru_flush;

  assign o_cleanDChe = lsu_fencei;
  assign o_invalidIChe = fence_flush;

  // simulation signals:
  logic                   s_a0zero ;
  logic                   s_lsu_device, s_wbu_device;
  logic [`INS_WIDTH-1:0]  s_idu_ins, s_exu_ins, s_lsu_ins, s_wbu_ins;
  logic [`CPU_WIDTH-1:0]  s_regs [`REG_COUNT-1:0];
  logic [`CPU_WIDTH-1:0]  s_mcause;
  logic                   s_lsu_lsclint, s_wbu_lsclint;

  // 2.1 ifu ////////////////////////////////////////////////////////

  ifu u_ifu(
    .i_clk        (i_clk      ),
    .i_rst_n      (i_rst_n    ),
    .iCacheIf_M   (iCacheIf_M ),
    .i_flush      (ifu_flush  ),
    .o_post_valid (ifu_valid  ),
    .i_post_ready (ifu_ready  ),
    .i_next_pc    (pre_pc     ),
    .o_ifu_pc     (ifu_pc     ),
    .o_ifu_ins    (ifu_ins    )
  );

  // 2.2 idu ////////////////////////////////////////////////////////

  // for bypass to get reg value.
  logic [`REG_ADDRW-1:0]      idu_rs1id, idu_rs2id;
  logic [`CSR_ADDRW-1:0]      idu_csrsid  ;
  logic                       idu_csrsren ;
  // get rs value from bypass: 
  logic [`CPU_WIDTH-1:0]      idu_rs1, idu_rs2;
  logic [`CPU_WIDTH-1:0]      idu_csrs    ;
  // for exu:
  logic                       idu_sysins  ;
  logic [`CPU_WIDTH-1:0]      idu_imm     ;
  logic [`EXU_SEL_WIDTH-1:0]  idu_exsrc   ;
  logic [`EXU_OPT_WIDTH-1:0]  idu_exopt   ;
  logic                       idu_excsrsrc;
  logic [`CSR_OPT_WIDTH-1:0]  idu_excsropt;
  // for lsu:
  logic [2:0]                 idu_lsfunc3 ;
  logic                       idu_lden    ;
  logic                       idu_sten    ;
  logic                       idu_fencei  ;
  // for wbu:
  logic [`REG_ADDRW-1:0]      idu_rdid    ;
  logic                       idu_rdwen   ;
  logic [`CSR_ADDRW-1:0]      idu_csrdid  ;
  logic                       idu_csrdwen ; 

  // for bru:
  logic                       idu_jal,idu_jalr,idu_brch;
  logic [2:0]                 idu_bfun3;

  idu u_idu(
    .i_clk          (i_clk        ),
    .i_rst_n        (i_rst_n      ),
    .i_flush        (idu_flush    ),
    .i_pre_nop      (ifid_nop     ),
    .i_pre_stall    (ifid_stall   ),
    .i_pre_valid    (ifu_valid    ),
    .o_pre_ready    (ifu_ready    ),
    .o_post_valid   (idu_valid    ),
    .i_post_ready   (idu_ready    ),
    .i_ifu_ins      (ifu_ins      ),
    .i_ifu_pc       (ifu_pc       ),
    .o_idu_rs1id    (idu_rs1id    ),
    .o_idu_rs2id    (idu_rs2id    ),
    .o_idu_csrsid   (idu_csrsid   ),
    .o_idu_csrsren  (idu_csrsren  ),
    .o_idu_sysins   (idu_sysins   ),
    .o_idu_imm      (idu_imm      ),
    .o_idu_exsrc    (idu_exsrc    ),
    .o_idu_exopt    (idu_exopt    ),
    .o_idu_excsrsrc (idu_excsrsrc ),
    .o_idu_excsropt (idu_excsropt ),
    .o_idu_lsfunc3  (idu_lsfunc3  ),
    .o_idu_lden     (idu_lden     ),
    .o_idu_sten     (idu_sten     ),
    .o_idu_fencei   (idu_fencei   ),
    .o_idu_rdid     (idu_rdid     ),
    .o_idu_rdwen    (idu_rdwen    ),
    .o_idu_csrdid   (idu_csrdid   ),
    .o_idu_csrdwen  (idu_csrdwen  ),
    .o_idu_jal      (idu_jal      ),
    .o_idu_jalr     (idu_jalr     ),
    .o_idu_brch     (idu_brch     ),
    .o_idu_bfun3    (idu_bfun3    ),
    .o_idu_pc       (idu_pc       ),
    .o_idu_ecall    (idu_ecall    ),
    .o_idu_mret     (idu_mret     ),
    .o_idu_nop      (idu_nop      ),
    .s_idu_ins      (s_idu_ins    )
  );

  // 2.3 exu ///////////////////////////////////////////////

  // generate exu output value:
  logic [`CPU_WIDTH-1:0]      exu_exres   ; // for lsu addr, or for wbu rd.
  // for lsu:
  logic                       exu_lden    ; // for lsu load en.
  logic                       exu_sten    ; // for lsu store en.
  logic                       exu_fencei  ; // for lsu fence.i.
  logic [`CPU_WIDTH-1:0]      exu_rs2     ; // for lsu data.
  logic [2:0]                 exu_lsfunc3 ; // for lsu func3
  // for wbu:
  logic [`REG_ADDRW-1:0]      exu_rdid    ;
  logic                       exu_rdwen   ;
  logic [`CSR_ADDRW-1:0]      exu_csrdid  ;
  logic                       exu_csrdwen ;
  logic [`CPU_WIDTH-1:0]      exu_csrd    ;

  exu u_exu(
    .i_clk          (i_clk          ),
    .i_rst_n        (i_rst_n        ),
    .i_flush        (exu_flush      ),
    .i_pre_nop      (idex_nop       ),
    .i_pre_valid    (idu_valid      ),
    .o_pre_ready    (idu_ready      ),
    .o_post_valid   (exu_valid      ),
    .i_post_ready   (exu_ready      ),
    .i_idu_sysins   (idu_sysins     ),
    .i_idu_imm      (idu_imm        ),
    .i_idu_csrs     (idu_csrs       ),
    .i_idu_rs1      (idu_rs1        ),
    .i_idu_rs2      (idu_rs2        ),
    .i_idu_exsrc    (idu_exsrc      ),
    .i_idu_exopt    (idu_exopt      ),
    .i_idu_excsrsrc (idu_excsrsrc   ),
    .i_idu_excsropt (idu_excsropt   ),
    .i_idu_lsfunc3  (idu_lsfunc3    ),
    .i_idu_lden     (idu_lden       ),
    .i_idu_sten     (idu_sten       ),
    .i_idu_fencei   (idu_fencei     ),
    .i_idu_rdid     (idu_rdid       ),
    .i_idu_rdwen    (idu_rdwen      ),
    .i_idu_csrdid   (idu_csrdid     ),
    .i_idu_csrdwen  (idu_csrdwen    ),
    .i_idu_pc       (idu_pc         ),
    .i_idu_ecall    (idu_ecall      ),
    .i_idu_mret     (idu_mret       ),
    .i_idu_nop      (idu_nop        ),
    .s_idu_ins      (s_idu_ins      ),
    .o_exu_rs2      (exu_rs2        ),
    .o_exu_lsfunc3  (exu_lsfunc3    ),
    .o_exu_lden     (exu_lden       ),
    .o_exu_sten     (exu_sten       ),
    .o_exu_fencei   (exu_fencei     ),
    .o_exu_rdid     (exu_rdid       ),
    .o_exu_rdwen    (exu_rdwen      ),
    .o_exu_res      (exu_exres      ),
    .o_exu_csrdid   (exu_csrdid     ),
    .o_exu_csrdwen  (exu_csrdwen    ),
    .o_exu_csrd     (exu_csrd       ),
    .o_exu_pc       (exu_pc         ),
    .o_exu_ecall    (exu_ecall      ),
    .o_exu_mret     (exu_mret       ),
    .o_exu_nop      (exu_nop        ),
    .s_exu_ins      (s_exu_ins      )
  );

  // 2.4 lsu ///////////////////////////////////////////////

  logic [`CPU_WIDTH-1:0]      lsu_exres  ;
  logic [`CPU_WIDTH-1:0]      lsu_lsres  ;
  logic                       lsu_lden   ;
  logic [`REG_ADDRW-1:0]      lsu_rdid   ;
  logic                       lsu_rdwen  ;
  logic [`CSR_ADDRW-1:0]      lsu_csrdid ;
  logic                       lsu_csrdwen;
  logic [`CPU_WIDTH-1:0]      lsu_csrd   ;

  lsu u_lsu(
    .i_clk         (i_clk         ),
    .i_rst_n       (i_rst_n       ),
    .i_flush       (lsu_flush     ),
    .dCacheIf_M    (dCacheIf_M    ),
    .i_pre_valid   (exu_valid     ),
    .o_pre_ready   (exu_ready     ),
    .o_post_valid  (lsu_valid     ),
    .i_post_ready  (lsu_ready     ),
    .i_exu_exres   (exu_exres     ),
    .i_exu_rs2     (exu_rs2       ),
    .i_exu_lsfunc3 (exu_lsfunc3   ),
    .i_exu_lden    (exu_lden      ),
    .i_exu_sten    (exu_sten      ),
    .i_exu_fencei  (exu_fencei    ),
    .i_exu_rdid    (exu_rdid      ),
    .i_exu_rdwen   (exu_rdwen     ),
    .i_exu_csrdid  (exu_csrdid    ),
    .i_exu_csrdwen (exu_csrdwen   ),
    .i_exu_csrd    (exu_csrd      ),
    .i_exu_pc      (exu_pc        ),
    .i_exu_ecall   (exu_ecall     ),
    .i_exu_mret    (exu_mret      ),
    .i_exu_nop     (exu_nop       ),
    .s_exu_ins     (s_exu_ins     ),
    .i_iru_excp    (iru_excp      ),
    .i_iru_intr    (iru_intr      ),
    .o_clint_ren   (clint_ren     ),
    .o_clint_raddr (clint_raddr   ),
    .i_clint_rdata (clint_rdata   ),
    .o_clint_wen   (clint_wen     ),
    .o_clint_waddr (clint_waddr   ),
    .o_clint_wdata (clint_wdata   ),
    .o_lsu_lsres   (lsu_lsres     ),
    .o_lsu_exres   (lsu_exres     ),
    .o_lsu_lden    (lsu_lden      ),
    .o_lsu_fencei  (lsu_fencei    ),
    .o_lsu_rdid    (lsu_rdid      ),
    .o_lsu_rdwen   (lsu_rdwen     ),
    .o_lsu_csrdid  (lsu_csrdid    ),
    .o_lsu_csrdwen (lsu_csrdwen   ),
    .o_lsu_csrd    (lsu_csrd      ),
    .o_lsu_pc      (lsu_pc        ),
    .o_lsu_ecall   (lsu_ecall     ),
    .o_lsu_mret    (lsu_mret      ),
    .o_lsu_nop     (lsu_nop       ),
    .s_lsu_ins     (s_lsu_ins     ),
    .s_lsu_lsclint (s_lsu_lsclint ),
    .s_lsu_device  (s_lsu_device  )
  );

  // 2.5 wbu ///////////////////////////////////////////////

  logic [`REG_ADDRW-1:0]      wbu_rdid   ;
  logic                       wbu_rdwen  ;
  logic [`CPU_WIDTH-1:0]      wbu_rd     ;
  logic [`CSR_ADDRW-1:0]      wbu_csrdid ;
  logic                       wbu_csrdwen;
  logic [`CPU_WIDTH-1:0]      wbu_csrd   ;

  wbu u_wbu(
    .i_clk         (i_clk        ),
    .i_rst_n       (i_rst_n      ),
    .i_flush       (wbu_flush    ),
    .i_pre_valid   (lsu_valid    ),
    .o_pre_ready   (lsu_ready    ),
    .o_post_valid  (wbu_valid    ),
    .i_post_ready  (wbu_ready    ),
    .i_lsu_exres   (lsu_exres    ),
    .i_lsu_lsres   (lsu_lsres    ),
    .i_lsu_lden    (lsu_lden     ),
    .i_lsu_rdid    (lsu_rdid     ),
    .i_lsu_rdwen   (lsu_rdwen    ),
    .i_lsu_csrdid  (lsu_csrdid   ),
    .i_lsu_csrdwen (lsu_csrdwen  ),
    .i_lsu_csrd    (lsu_csrd     ),
    .i_lsu_pc      (lsu_pc       ),
    .i_lsu_ecall   (lsu_ecall    ),
    .i_lsu_mret    (lsu_mret     ),
    .i_lsu_nop     (lsu_nop      ),
    .i_iru_intr    (iru_intr     ),
    .s_lsu_ins     (s_lsu_ins    ),
    .s_lsu_lsclint (s_lsu_lsclint),
    .s_lsu_device  (s_lsu_device ),
    .o_wbu_rdid    (wbu_rdid     ),
    .o_wbu_rdwen   (wbu_rdwen    ),
    .o_wbu_rd      (wbu_rd       ),
    .o_wbu_csrdid  (wbu_csrdid   ),
    .o_wbu_csrdwen (wbu_csrdwen  ),
    .o_wbu_csrd    (wbu_csrd     ),
    .o_wbu_commit  (wbu_commit   ),
    .o_wbu_pc      (wbu_pc       ),
    .o_wbu_ecall   (wbu_ecall    ),
    .o_wbu_mret    (wbu_mret     ),
    .o_wbu_nop     (wbu_nop      ),
    .s_wbu_ins     (s_wbu_ins    ),
    .s_wbu_lsclint (s_wbu_lsclint),
    .s_wbu_device  (s_wbu_device )
  );

  logic [`CPU_WIDTH-1:0]  mie           ;
  logic [`CPU_WIDTH-1:0]  mip           ;
  logic [`CPU_WIDTH-1:0]  mtvec         ;
  logic [`CPU_WIDTH-1:0]  mepc          ;
  logic [`CPU_WIDTH-1:0]  mstatus       ;
  logic                   mepc_wen      ;
  logic [`CPU_WIDTH-1:0]  mepc_wdata    ;
  logic                   mcause_wen    ;
  logic [`CPU_WIDTH-1:0]  mcause_wdata  ;
  logic                   mstatus_wen   ;
  logic [`CPU_WIDTH-1:0]  mstatus_wdata ;

  iru u_iru(
    .i_wbu_valid     (wbu_valid       ),
    .i_wbu_ready     (wbu_ready       ),
    .i_wbu_pc        (wbu_pc          ),
    .i_wbu_ecall     (wbu_ecall       ),
    .i_wbu_mret      (wbu_mret        ),
    .i_wbu_nop       (wbu_nop         ),
    .o_iru_excp      (iru_excp        ),
    .o_iru_intr      (iru_intr        ),
    .o_iru_pc        (iru_pc          ),
    .i_mie           (mie             ),
    .i_mip           (mip             ),
    .i_mtvec         (mtvec           ),
    .i_mepc          (mepc            ),
    .i_mstatus       (mstatus         ),
    .o_mepc_wen      (mepc_wen        ),
    .o_mepc_wdata    (mepc_wdata      ),
    .o_mcause_wen    (mcause_wen      ),
    .o_mcause_wdata  (mcause_wdata    ),
    .o_mstatus_wen   (mstatus_wen     ),
    .o_mstatus_wdata (mstatus_wdata   )
  );

  clint u_clint(
    .i_clk         (i_clk         ),
    .i_rst_n       (i_rst_n       ),
    .i_clint_ren   (clint_ren     ),
    .i_clint_raddr (clint_raddr   ),
    .o_clint_rdata (clint_rdata   ),
    .i_clint_wen   (clint_wen     ),
    .i_clint_waddr (clint_waddr   ),
    .i_clint_wdata (clint_wdata   ),
    .o_clint_mtip  (clint_mtip    )
  );

  // 2.6 bypass, regfile read/write. ///////////////////////
  bypass u_bypass(
    .i_clk        (i_clk        ),
    .i_rst_n      (i_rst_n      ),
    .i_idu_rs1id  (idu_rs1id    ),
    .i_idu_rs2id  (idu_rs2id    ),
    .i_exu_lden   (exu_lden     ),
    .i_exu_rdwen  (exu_rdwen    ),
    .i_exu_rdid   (exu_rdid     ),
    .i_exu_exres  (exu_exres    ),
    .i_lsu_lden   (lsu_lden     ),
    .i_lsu_rdwen  (lsu_rdwen    ),
    .i_lsu_rdid   (lsu_rdid     ),
    .i_lsu_exres  (lsu_exres    ),
    .i_lsu_lsres  (lsu_lsres    ),
    .i_wbu_rdwen  (wbu_rdwen    ),
    .i_wbu_rdid   (wbu_rdid     ),
    .i_wbu_rd     (wbu_rd       ),
    .o_idu_rs1    (idu_rs1      ),
    .o_idu_rs2    (idu_rs2      ),
    .o_idex_nop   (idex_nop     ),
    .o_ifid_stall (ifid_stall   ),
    .s_a0zero     (s_a0zero     ),
    .s_regs       (s_regs       )
  );

  csrfile u_csrfile(
  	.i_clk           (i_clk          ),
    .i_rst_n         (i_rst_n        ),
    .i_ren           (idu_csrsren    ),
    .i_raddr         (idu_csrsid     ),
    .o_rdata         (idu_csrs       ),
    .i_wen           (wbu_csrdwen    ),
    .i_waddr         (wbu_csrdid     ),
    .i_wdata         (wbu_csrd       ),
    .i_mepc_wen      (mepc_wen       ),
    .i_mepc_wdata    (mepc_wdata     ),
    .i_mcause_wen    (mcause_wen     ),
    .i_mcause_wdata  (mcause_wdata   ),
    .i_mstatus_wen   (mstatus_wen    ),
    .i_mstatus_wdata (mstatus_wdata  ),
    .o_mtvec         (mtvec          ),
    .o_mstatus       (mstatus        ),
    .o_mepc          (mepc           ),
    .o_mip           (mip            ),
    .o_mie           (mie            ),
    .i_clint_mtip    (clint_mtip     ),
    .s_mcause        (s_mcause       )
  );

  // 2.7 bru ///////////////////////////////////////////////

  bru u_bru(
    .i_clk        (i_clk        ),
    .i_rst_n      (i_rst_n      ),
    .i_idu_valid  (idu_valid    ),
    .i_idu_rs1id  (idu_rs1id    ),
    .i_exu_rdid   (exu_rdid     ),
    .i_jal        (idu_jal      ),
    .i_jalr       (idu_jalr     ),
    .i_brch       (idu_brch     ),
    .i_bfun3      (idu_bfun3    ),
    .i_rs1        (idu_rs1      ),
    .i_rs2        (idu_rs2      ),
    .i_imm        (idu_imm      ),
    .i_ifupc      (ifu_pc       ),
    .i_idupc      (idu_pc       ),
    .i_iru_jump   (iru_excp | iru_intr ),
    .i_iru_pc     (iru_pc       ),
    .i_fence_jump (lsu_fencei   ),
    .i_fence_pc   (lsu_pc+4     ),
    .o_next_pc    (pre_pc       ),
    .o_ifid_nop   (ifid_nop     )
  );

  // 3.sim:  ////////////////////////////////////////////////////////
  // 3.1 update rst state, wb stage pc, skip, commit, finish to sim.
  /*.sim:之后的代码是用于模拟CPU的行为和性能的。它包括以下几个部分：

3.1 更新CPU的复位状态、写回阶段的PC值、跳过、提交和完成的信号，并将它们传递给外部的C函数，用于与参考模型进行比较和检查。
3.2 获取CPU的寄存器文件的值，并将它们传递给外部的C函数，用于与参考模型进行比较和检查。
3.3 获取CPU的内存访问的地址、数据和类型，并将它们传递给外部的C函数，用于与参考模型进行比较和检查。
3.4 获取CPU的异常和中断的信息，并将它们传递给外部的C函数，用于与参考模型进行比较和检查。
3.5 获取CPU的性能计数器的值，并将它们传递给外部的C函数，用于统计和分析CPU的性能。
  */
  import "DPI-C" function void check_rst(input bit rst_flag);
  import "DPI-C" function void get_diff_skip(input bit skip);
  import "DPI-C" function void get_diff_commit(input bit commit);
  import "DPI-C" function void check_finsih(input int ins,input bit a0zero);
  wire real_commit = wbu_commit & !wbu_nop;
  always @(*) begin
    check_rst(i_rst_n);
    get_diff_skip(s_wbu_device | iru_intr | s_wbu_lsclint);
    get_diff_commit(real_commit);
    check_finsih(s_wbu_ins,s_a0zero);
  end

  // 3.2 regfile.
  import "DPI-C" function void get_dut_regs(input longint dut_pc, input longint dut_x0, input longint dut_x1, input longint dut_x2, input longint dut_x3, input longint dut_x4, input longint dut_x5,
    input longint dut_x6, input longint dut_x7, input longint dut_x8, input longint dut_x9, input longint dut_x10, input longint dut_x11, input longint dut_x12,input longint dut_x13, input longint dut_x14, 
    input longint dut_x15, input longint dut_x16, input longint dut_x17, input longint dut_x18, input longint dut_x19, input longint dut_x20, input longint dut_x21, input longint dut_x22, input longint dut_x23,
    input longint dut_x24, input longint dut_x25, input longint dut_x26, input longint dut_x27, input longint dut_x28, input longint dut_x29, input longint dut_x30, input longint dut_x31, 
    input longint dut_mstatus, input longint dut_mtvec, input longint dut_mepc, input longint dut_mcause);
  always @(*) begin
    get_dut_regs(wbu_pc, s_regs[0], s_regs[1], s_regs[2], s_regs[3], s_regs[4], s_regs[5], s_regs[6], s_regs[7], s_regs[8], s_regs[9], s_regs[10], s_regs[11], s_regs[12],s_regs[13], s_regs[14], s_regs[15],
          s_regs[16], s_regs[17], s_regs[18], s_regs[19], s_regs[20], s_regs[21], s_regs[22], s_regs[23], s_regs[24], s_regs[25], s_regs[26], s_regs[27], s_regs[28], s_regs[29], s_regs[30], s_regs[31],
          mstatus, mtvec, mepc, s_mcause);
  end

endmodule