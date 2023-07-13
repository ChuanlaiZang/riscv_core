// register file module
// 寄存器堆的读操作不受时钟控制
// 写操作在时钟上升沿且使能信号有效时写入

`include "defines.v"

module regfile(
    input wire clk,
    input wire rst,

    // ex执行模块写寄存器
    input wire we_i,
    input wire[`RegAddrBus] waddr_i,
    input wire[`RegBus] wdata_i,

    // id指令译码模块读寄存器
    input wire[`RegAddrBus] raddr1_i,
    input wire[`RegAddrBus] raddr2_i,

    // 输出寄存器的值 to ex
    output reg[`RegBus] rdata1_o;
    output reg[`RegBus] rdata2_o;
);

    // 32个32位的通用寄存器
    reg [`RegBus] regfile [0 : `RegNum - 1];

    // 写寄存器堆
    always @(posedge clk or negedge rst) begin
        if(rst == `RstEnable) begin
            for (int i=0; i<`RegNum; i++) regfile[i] <= `ZeroWord;
        end
        else begin
            if((we_i == `WriteEnable) && (waddr_i != `ZeroReg)) begin
              regs[waddr_i] <= wdata_i;
            end
        end
    end

    //读寄存器1
    always @(*) begin
        if(rst == `RstEnable) begin
          rdata1_o = `ZeroWord;
        end
        else if(raddr1_i == `ZeroReg) begin
            rdata1_o = `ZeroWord;
        end
        // 如果读地址等于写地址，并且正在写操作，则直接返回写数据
        // 冒险的处理？
        else if((raddr1_i == waddr_i) && (we_i == `WriteEnable)) begin
            rdata1_o = wdata_i;
        end
        else begin
           rdata1_o = regfile[raddr1_i]; 
        end
    end

    //读寄存器2
    always @(*) begin
        if(rst == `RstEnable) begin
          rdata2_o = `ZeroWord;
        end
        else if(raddr2_i == `ZeroReg) begin
            rdata2_o = `ZeroWord;
        end
        // 如果读地址等于写地址，并且正在写操作，则直接返回写数据
        // 冒险的处理？
        else if((raddr2_i == waddr_i) && (we_i == `WriteEnable)) begin
            rdata2_o = wdata_i;
        end
        else begin
           rdata2_o = regfile[raddr2_i]; 
        end
    end
endmodule