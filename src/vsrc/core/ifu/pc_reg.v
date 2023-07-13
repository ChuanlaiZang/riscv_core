// PC register module

`include "defines.v"


module pc_reg (
    
input wire clk,
input wire rst,

input wire                  jump_flag_i,  //跳转标志
input wire[`InstAddrBus]    jump_addr_i,  //跳转标志
input wire[`Hold_Flag_Bus]  hold_flag_i,  //流水线暂停标志
input wire jtag_reset_flag_i,             // 复位标志

output reg[`InstAddrBus]    pc_o
);

always @(posedge clk or negedge rst) begin
    // 异步复位
    if (rst == `RstEnable || jtag_reset_flag_i == 1'b1) begin
      pc_o <= `CpuResetAddr;
    end
    //跳转指定地址
    else if(jump_flag_i == `JumpEnable) begin
      pc_o <= jump_add_i;
    end
    //流水线暂停PC寄存器
    else if (hold_flag_i > `Hold_Pc) begin
      pc_o <= pc_o;
    end
    // pc寄存器地址+4
    else begin
        pc_o <= pc_o + 4'h4;
    end
end


endmodule //pc_reg