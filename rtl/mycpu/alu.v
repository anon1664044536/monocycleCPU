`timescale 1ns / 1ps

module alu(
  input  wire [11:0] alu_op,
  input  wire [31:0] alu_src1,
  input  wire [31:0] alu_src2,
  output wire [31:0] alu_result
);

wire op_add;   //add operation
wire op_sub;   //sub operation
wire op_slt;   //signed compared and set less than
wire op_sltu;  //unsigned compared and set less than
wire op_and;   //bitwise and
wire op_nor;   //bitwise nor
wire op_or;    //bitwise or
wire op_xor;   //bitwise xor
wire op_sll;   //logic left shift
wire op_srl;   //logic right shift
wire op_sra;   //arithmetic right shift
wire op_lui;   //Load Upper Immediate

// control code decomposition
assign op_add  = alu_op[ 0];  // 加法
assign op_sub  = alu_op[ 1];  // 减法
assign op_slt  = alu_op[ 2];  // 有符号小于比较
assign op_sltu = alu_op[ 3];  // 无符号小于比较
assign op_and  = alu_op[ 4];  // 位与操作
assign op_nor  = alu_op[ 5];  // 位或非操作
assign op_or   = alu_op[ 6];  // 位或操作
assign op_xor  = alu_op[ 7];  // 位异或操作
assign op_sll  = alu_op[ 8];  // 逻辑左移
assign op_srl  = alu_op[ 9];  // 逻辑右移
assign op_sra  = alu_op[10];  // 算术右移
assign op_lui  = alu_op[11];  // 上半字立即数加载

//结果
wire [31:0] add_sub_result;
wire [31:0] slt_result;
wire [31:0] sltu_result;
wire [31:0] and_result;
wire [31:0] nor_result;
wire [31:0] or_result;
wire [31:0] xor_result;
wire [31:0] lui_result;
wire [31:0] sll_result;
wire [63:0] sr64_result;
wire [31:0] sr_result;


// 32-bit adder
wire [31:0] adder_a;  // 操作数a
wire [31:0] adder_b;  // 操作数b
wire        adder_cin; // 进位输入
wire [31:0] adder_result; // 加法器的结果
wire        adder_cout; // 进位输出

assign adder_a   = alu_src1;
/*
如果当前的操作是减法 (op_sub)、有符号小于比较 (op_slt)、或无符号小于比较 (op_sltu)，则 adder_b 取 alu_src2 的反码（~alu_src2），否则直接取 alu_src2。
对于减法、slt 和 sltu 操作，实际上是要计算 src1 - src2。
根据二进制减法的规则，减法 rj - rk 等价于 rj + (~rk + 1)。因此这里通过取反（~alu_src2）和设置进位输入为1（在 adder_cin 中设置）来实现减法。
*/
assign adder_b   = (op_sub | op_slt | op_sltu) ? ~alu_src2 : alu_src2;  //src1 - src2 rj-rk
assign adder_cin = (op_sub | op_slt | op_sltu) ? 1'b1      : 1'b0;
assign {adder_cout, adder_result} = adder_a + adder_b + adder_cin;

// ADD, SUB result
assign add_sub_result = adder_result;

//有符号小于比较（SLT - Set Less Than）
//1表示小于,0表示大于
assign slt_result[31:1] = 31'b0;   //rj < rk 1
assign slt_result[0]    = (alu_src1[31] & ~alu_src2[31])    /*src1和src2异号*/
                        | ((alu_src1[31] ~^ alu_src2[31]) & adder_result[31]);  //~^同或表示两者符号相同,用符号位进行判断,1为负表示src1<src2

//无符号小于比较
//如果 ~adder_cout == 1，说明在 alu_src1 - alu_src2 的运算中没有借位，表示 alu_src1 小于 alu_src2。
assign sltu_result[31:1] = 31'b0;
assign sltu_result[0]    = ~adder_cout;

// bitwise operation
assign and_result = alu_src1 & alu_src2;  // 按位与
assign or_result  = alu_src1 | alu_src2;  // 按位或
assign nor_result = ~or_result;           // 按位或非
assign xor_result = alu_src1 ^ alu_src2;  // 按位异或
assign lui_result = alu_src2;             // 加载上半字

// SLL result
//alu_src1 的位序向左移动 alu_src2[4:0] 位，移出的高位丢弃，低位补零
assign sll_result = alu_src1 << alu_src2[4:0];   //rj << ui5

// SRL, SRA result
//逻辑右移和算数右移
//如果进行算数右移的话,op_sra为1,才会进行符号位的扩充,否则默认就是0
assign sr64_result = {{32{op_sra & alu_src1[31]}}, alu_src1[31:0]} >> alu_src2[4:0]; //rj >> i5

assign sr_result   = sr64_result[31:0];

// final result mux
assign alu_result = ({32{op_add|op_sub}} & add_sub_result)
                  | ({32{op_slt       }} & slt_result)
                  | ({32{op_sltu      }} & sltu_result)
                  | ({32{op_and       }} & and_result)
                  | ({32{op_nor       }} & nor_result)
                  | ({32{op_or        }} & or_result)
                  | ({32{op_xor       }} & xor_result)
                  | ({32{op_lui       }} & lui_result)
                  | ({32{op_sll       }} & sll_result)
                  | ({32{op_srl|op_sra}} & sr_result);

endmodule