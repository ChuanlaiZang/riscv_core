// IF取指模块，所有信号打一拍之后，并向ID译码模块发送指令
`include "defines.v"

module if_id (
    input      clk,
    input      rst,

    input wire[`InstBus] inst_i,                //输入指令内容
    input wire[`InstAddrBus] inst_addr_i,       //输入指令地址

    input wire[`Hold_Flag_Bus] hold_flag_i,     //流水线暂停标志

    input wire[`INT_BUS] int_flag_i,            //外设中断输入信号
    
    output wire[`InstBus] inst_o;
    output wire[`InstAddrBus] inst_addr_o,

    output wire[`INT_BUS] int_flag_o
);
    // 判断是否暂停流水线
    wire hold_en
    assign hold_en = (hold_flag_i >= `Hold_If);

    // 对各信号打拍输出
    wire[`InsBus] inst;
    gen_pipe_dff #(32) inst_ff(             //多参数实例化 #(.a(2), .b(2))
    .clk            (clk),
    .rst            (rst),
    .hold_en        (hold_en),
    .def_val        (`INST_NOP),
    .din            (inst_i),
    .qout           (inst_o)
    );

    wire[`INT_BUS] int_addr;
    gen_pipe_dff #(32) int_addr_ff(
    .clk            (clk),
    .rst            (rst),
    .hold_en        (hold_en),
    .def_val        (`ZeroWord),
    .din            (inst_addr_i),
    .qout           (inst_addr_o)
    );

    wire[`InsBus] int_flag;
    gen_pipe_dff #(8) inst_ff(
    .clk            (clk),
    .rst            (rst),
    .hold_en        (hold_en),
    .def_val        (`INT_NONE),
    .din            (int_flag_i),
    .qout           (int_flag_o)
    );
endmodule //if
