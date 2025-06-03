`ifndef __HAZARD_SV
`define __HAZARD_SV


`ifdef VERILATOR
`include "include/common.sv"
`include "include/pipeline.sv"
`endif

module hazard 
    import common::*;
	import pipeline::*;
	(
    input  decode_data_t dataD_nxt, dataD, // 检查到 load_use_hazard 时，必须在 decode 阶段就检测，并且插入气泡；否则 decode 阶段读取到错误值
    input  exec_data_t dataE_nxt, dataE,
    input  mem_data_t dataM_nxt, dataM,
    input  logic  validpc, validF, validD, validE, validM, // 是否此阶段的数据有效（不为 nop）

    output logic  stallF, stallD, stallE, stallM, stallW,
    output logic  flushF, flushD, flushE, flushM, flushW,
    output logic  jump, csr, exception, mret,
    input  logic  interrupt_update_pc
);

    wire load_use_hazard = dataD.ctl.mem_read && ((dataD.dst == dataD_nxt.rs1 && dataD_nxt.rs1 != 0) || (dataD.dst == dataD_nxt.rs2 && dataD_nxt.rs2 != 0));
    wire exception_or_mret_W_stage = dataM.ctl.exception || dataM.ctl.mret;
    wire exception_or_mret_D_stage = dataD_nxt.ctl.exception || dataD_nxt.ctl.mret;
    wire exception_or_mret_E_stage = dataE_nxt.ctl.exception || dataE_nxt.ctl.mret;
    wire exception_or_mret_M_stage = dataM_nxt.ctl.exception || dataM_nxt.ctl.mret;

    assign jump = dataE_nxt.ctl.jump | dataE_nxt.ctl.branch; // 跳转信号在 execute 阶段产生
	assign exception = dataM.ctl.exception; // exception 信号在 writeback 阶段产生
	assign mret = dataM.ctl.mret; // mret 信号在 writeback 阶段产生

    always_comb begin

        {stallF, stallD, stallE, stallM, stallW, flushF, flushD, flushE, flushM, flushW} = 'b0;
        
        if (exception_or_mret_W_stage || interrupt_update_pc) begin
            // flush fetch but not stall update pc
            flushF = 1;
            flushD = 1;
            flushE = 1;
            flushM = 1;
            flushW = 1;
        end else if (load_use_hazard) begin
            // load_use_hazard stall fetch and decode, add bubble to execute
            stallF = 1;
            stallD = 1;
            flushE = 1;
        end else if (jump) begin
            flushD = 1;
            flushE = 1;
        end else if (exception_or_mret_M_stage) begin
            stallF = 1;
            flushF = 1;
            flushD = 1;
            flushE = 1;
            flushM = 1;
        end else if (exception_or_mret_E_stage) begin
            stallF = 1;
            flushF = 1;
            flushD = 1;
            flushE = 1;
        end else if (exception_or_mret_D_stage) begin
            stallF = 1;
            flushF = 1;
            flushD = 1;
        end else if (csr) begin
            stallF = 1;
            flushF = 1;
        end else begin
            // do nothing
        end
    end

endmodule


`endif