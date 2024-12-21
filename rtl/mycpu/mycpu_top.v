module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
    // inst sram interface
    output wire       inst_sram_wen,
    output wire[31:0] inst_sram_addr,
    output wire[31:0] inst_sram_wdata,
    input  wire[31:0] inst_sram_rdata,
    // data sram interface
    output wire       data_sram_wen,
    output wire[31:0] data_sram_addr,
    output wire[31:0] data_sram_wdata,
    input  wire[31:0] data_sram_rdata,
    // trace debug interface
    output wire[31:0] debug_wb_pc,
    output wire[3:0] debug_wb_rf_wen,
    output wire[4:0] debug_wb_rf_wnum,
    output wire[31:0] debug_wb_rf_wdata
);
//时钟信号
reg         reset;
always @(posedge clk) reset <= ~resetn;

reg         valid;
always @(posedge clk) begin
    if (reset) begin
        valid <= 1'b0;
    end
    else begin
        valid <= 1'b1;
    end
end

reg[31:0] pc;           //可储存的指令地址信息
wire[31:0] nextpc;      //32位下一个PC值
wire[31:0] inst;        //当前指令信息
wire       br_taken;    //跳转控制信号
wire[31:0] br_target;   //目标PC值

//操作码的各个段  操作码一共16位
wire[5:0] op_31_26;   //高6位
wire[3:0] op_25_22;   //中4位
wire[1:0] op_21_20;   //中2位
wire[4:0] op_19_15;   //后5位
//控制信号译码   转换成10进制更方便看
wire[63:0] op_31_26_d;
wire[15:0] op_25_22_d;
wire[3:0] op_21_20_d;
wire[31:0] op_19_15_d;
//三个寄存器地址    还有个偏移量立即数
wire[4:0] rd;
wire[4:0] rj;
wire[4:0] rk;
//12 16 20 26位立即数
wire[11:0] i12;
wire[19:0] i20;
wire[15:0] i16;
wire[25:0] i26;

//add mew alu_inst
wire        inst_add_w;
wire        inst_addi_w;
wire        inst_sub_w;
wire        inst_slt;
wire        inst_sltu;
wire        inst_slli_w; 
wire        inst_srli_w;
wire        inst_srai_w;
wire        inst_and;
wire        inst_or;
wire        inst_nor;
wire        inst_xor;
wire        inst_lu12i; 
wire        inst_ld_w;
wire        inst_st_w;
wire        inst_bne;
wire        inst_beq;
wire        inst_bl;
wire        inst_jirl;

//控制信号定义
wire[11:0]  alu_op;     //给到ALU的12位控制信号
wire        src1_is_pc; //一个操作数1是PC
wire        src2_is_imm;//一个操作数2是立即数
wire        res_from_mem;//操作数来自于内存
wire        gr_we;      //是否写回寄存器   写回使能信号
wire        mem_we;     //内存写信号
wire        src_reg_is_rd;    //rd是否作为源操作数
wire        rg_waddr_is_1;  //判断写寄存器地址是否为1
wire        br_target_is_pc_add_offs;   //是PC的值加上偏移量还是RG[rj]


wire[31:0]  rj_value;  //rj的value
wire[31:0]  rkd_value; //rkd的value
wire[31:0] imm;       //32位立即数
wire[31:0] br_offs;   //PC偏移量
wire[31:0] jirl_offs; //其他偏移量

//立即数判断条件声明
wire        need_ui5;
wire        need_si12;
wire        need_si16;
wire        need_si20;
wire        need_si26;
wire        src2_is_4;

//所有ALU计算的立即数的声明
wire[31:0]  ui5_32;
wire[31:0]  si12_32;
wire[31:0]  si20_32;
wire[31:0]  si4_32;	

//所有位数的PC偏移值的声明
wire[31:0]  si16_32;
wire[31:0]  si26_32;  

wire[4:0]  rf_raddr1;   //读1  5位地址
wire[4:0]  rf_raddr2;   //读2  5位地址
wire[4:0]  rf_wadd;    //写   5位地址
wire[31:0] rf_wdata;   //写   32位数据

wire       rj_eq_rd;

//ALU模块两个输入32位数   一个输出32位数
wire[31:0] alu_src1;   
wire[31:0] alu_src2;
wire[31:0] alu_result;

//重置时恢复nextpc
always @(posedge clk) begin
    if (reset) begin
        pc <= 32'h1bfffffc;     //trick: to make nextpc be 0x1c000000 during reset 
    end
    else begin
        pc <= nextpc;
    end
end

//储存器模块信号配置
assign inst_sram_we    = 1'b0;
assign inst_sram_addr  = pc;
assign inst_sram_wdata = 32'b0;
assign inst            = inst_sram_rdata;

assign op_31_26 = inst[31:26];
assign op_25_22 = inst[25:22];
assign op_21_20 = inst[21:20];
assign op_19_15 = inst[19:15];
assign rd       = inst[ 4: 0];
assign rj       = inst[ 9: 5];
assign rk       = inst[14:10];

assign i12      = inst[21:10];
assign i16      = inst[25:10];
assign i20      = inst[24:5];
assign i26      = { inst[9:0], inst[25:10] };

//译码
decoder_6_64 u_dec0(.in(op_31_26 ), .co(op_31_26_d ));
decoder_4_16 u_dec1(.in(op_25_22 ), .co(op_25_22_d ));
decoder_2_4  u_dec2(.in(op_21_20 ), .co(op_21_20_d ));
decoder_5_32 u_dec3(.in(op_19_15 ), .co(op_19_15_d ));

//判断操作码信号
assign inst_add_w   =   op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_addi_w  =   op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_ld_w    =   op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_st_w    =   op_31_26_d[6'h0a] & op_25_22_d[4'h6];
assign inst_bne     =   op_31_26_d[6'h17] ;
assign inst_sub_w   =   op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt     =   op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu    =   op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_slli_w  =   op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01]; 
assign inst_srli_w  =   op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w  =   op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
assign inst_and     =   op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or      =   op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_nor     =   op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_xor     =   op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_lu12i   =   op_31_26_d[6'h05] & (inst[25]==1'b0) ; 
assign inst_beq     =   op_31_26_d[6'h16] ;
assign inst_b       =   op_31_26_d[6'h14] ;
assign inst_bl      =   op_31_26_d[6'h15] ;
assign inst_jirl    =   op_31_26_d[6'h13] ;  

//ALU信号配置
assign alu_op = {
                    inst_lu12i, inst_srai_w, inst_srli_w, inst_slli_w,
                    inst_xor,   inst_or,     inst_nor,    inst_and,
                    inst_sltu,  inst_slt,    inst_sub_w,
                    inst_add_w | inst_addi_w | inst_ld_w | inst_st_w | inst_jirl | inst_bl
                };

//操作数1为pc
assign src1_is_pc    =  inst_bl     | inst_jirl;

//操作数2为立即数
assign src2_is_imm   =  inst_st_w   | inst_ld_w     | inst_addi_w   | inst_slli_w |
                        inst_srli_w | inst_srai_w   | inst_bl       | inst_lu12i  |
                        inst_jirl;

//来着内存的数
assign res_from_mem  = inst_ld_w;

//通用寄存器写
assign gr_we         = ~inst_bne & ~inst_beq & ~inst_b & ~inst_st_w;

//内存写
assign mem_we        = inst_st_w;

//rd是否作为源操作数
assign src_reg_is_rd = inst_beq | inst_bne | inst_st_w;

//判断写寄存器地址是否为1
assign rg_waddr_is_1 = inst_bl;

//引入寄存器模块
assign rf_raddr1 = rj;
assign rf_raddr2 = src_reg_is_rd ? rd : rk;
assign rf_wadd = rg_waddr_is_1 ? 1 : rd;//控制gr地址
regfile u_regfile(
    .clk    (   clk   ),
    .raddr1 (rf_raddr1),
    .rdata1 (rj_value),
    .raddr2 (rf_raddr2),
    .rdata2 (rkd_value),
    .we     (   gr_we ),
    .waddr  ( rf_wadd  ),
    .wdata  (rf_wdata )
    );

assign debug_wb_pc = pc;
assign debug_wb_rf_wen = {4{gr_we}};
assign debug_wb_rf_wnum = rf_wadd;
assign debug_wb_rf_wdata = rf_wdata;

//立即数判断条件定义
assign       need_ui5   =   inst_slli_w | inst_srli_w | inst_srai_w;
assign       need_si12  =   inst_addi_w | inst_ld_w   | inst_st_w;
assign       need_si16  =   inst_beq    | inst_bne ;
assign       need_si20  =   inst_lu12i;
assign       need_si26  =   inst_b | inst_bl;
assign       src2_is_4  =   src1_is_pc;

//br_offs计算
assign br_offs = (
    (si16_32 & {32{need_si16}}) |
    (si26_32 & {32{need_si26}})
);

assign si16_32 = {{14{i16[15]}},i16,2'b00};
assign si26_32 = {{4{i26[25]}},i26,2'b00};

//是pc+offs还是RG[rj]+offs
assign br_target_is_pc_add_offs = inst_beq || inst_bne || inst_bl || inst_b;
assign br_target = (br_target_is_pc_add_offs) ? (pc + br_offs) :
    /*inst_jirl*/ (rj_value + br_offs);                   
 
//是否使用br_offs
assign rj_eq_rd  = (rj_value == rkd_value);
assign br_taken  = valid && 
                  (inst_beq && rj_eq_rd || 
                  inst_bne  && ~rj_eq_rd || 
                  inst_b || 
                  inst_bl || 
                  inst_jirl);
                  
assign nextpc    = br_taken ? br_target : (pc+4) ;

assign ui5_32 = rk;
assign si12_32 = {{20{i12[11]}},i12[11:0]};
assign si20_32 = {i20[19:0],12'b0};
assign si4_32  = 32'h04;			//把十进制的4扩展到32位

assign imm = (
    (ui5_32  & {32{need_ui5}})  |
    (si12_32 & {32{need_si12}}) |
    (si20_32 & {32{need_si20}}) |
    (si4_32  & {32{src2_is_4}})
); 

assign alu_src1 = src1_is_pc ? pc : rj_value;
assign alu_src2 = src2_is_imm ? imm : rkd_value;

alu u_alu(
    .alu_op(alu_op),
    .alu_src1(alu_src1),
    .alu_src2(alu_src2),
    .alu_result(alu_result)
    );

assign data_sram_wen    = mem_we;
assign data_sram_addr  = alu_result;
assign data_sram_wdata = rkd_value;

assign rf_wdata = res_from_mem ? data_sram_rdata : alu_result;

endmodule      