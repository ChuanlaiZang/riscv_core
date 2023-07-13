// 控制模块流水线的跳转（jump）和暂停（NOP）
// 发出跳转、暂停流水线信号

`include "defines.v"

module ctrl(

    input wire rst,

    // from ex
    input wire jump_flag_i,                     // 跳转标志
    input wire[`InstAddrBus] jump_addr_i,       // 跳转地址
    input wire hold_flag_ex_i,                  // 来自执行模块的暂停标志

    // from rib
    input wire hold_flag_rib_i,                 // 来自总线的暂停标志

    // from jtag
    input wire jtag_halt_flag_i,                // 来自jtag的暂停标志

    // from clint
    input wire hold_flag_clint_i,               // 来自中断模块的暂停标志

    output reg[`Hold_Flag_Bus] hold_flag_o,     // 输出暂停标志

    // to pc_reg
    output reg jump_flag_o,                     // 输出跳转标志，输出给pc_reg, if_id和id_ex模块
    output reg[`InstAddrBus] jump_addr_o

    );


    always @ (*) begin
        jump_addr_o = jump_addr_i;
        jump_flag_o = jump_flag_i;
        // 默认不暂停
        hold_flag_o = `Hold_None;
        // 按优先级处理不同模块的请求
        if (jump_flag_i == `JumpEnable || hold_flag_ex_i == `HoldEnable || hold_flag_clint_i == `HoldEnable) begin
            // 暂停整条流水线
            hold_flag_o = `Hold_Id;
        end else if (hold_flag_rib_i == `HoldEnable) begin
            // 暂停PC，即取指地址不变
            hold_flag_o = `Hold_Pc;
        end else if (jtag_halt_flag_i == `HoldEnable) begin
            // 暂停整条流水线
            hold_flag_o = `Hold_Id;
        end else begin
            hold_flag_o = `Hold_None;
        end
    end

    // output result

    
endmodule