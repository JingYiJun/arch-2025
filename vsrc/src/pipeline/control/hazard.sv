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
    input  logic  jump, csr, exception, mret,
    input  decode_data_t dataD_nxt, dataD, // 检查到 load_use_hazard 时，必须在 decode 阶段就检测，并且插入气泡；否则 decode 阶段读取到错误值
    input  logic  validpc, validF, validD, validE, validM, // 是否此阶段的数据有效（不为 nop）
    output logic  stallF, stallD, stallE, stallM, stallW,
    output logic  flushF, flushD, flushE, flushM, flushW
);

    wire load_use_hazard = dataD.ctl.mem_read && ((dataD.dst == dataD_nxt.rs1 && dataD_nxt.rs1 != 0) || (dataD.dst == dataD_nxt.rs2 && dataD_nxt.rs2 != 0));
    wire exception_or_mret = exception || mret;

    always_comb begin

        {stallF, stallD, stallE, stallM, stallW, flushF, flushD, flushE, flushM, flushW} = 'b0;
        
        if (exception_or_mret) begin
            // flush fetch but not stall update pc
            flushF = 1;
        end else if (load_use_hazard) begin
            // load_use_hazard stall fetch and decode, add bubble to execute
            stallF = 1;
            stallD = 1;
            flushE = 1;
        end else if (jump) begin
            flushD = 1;
            flushE = 1;
        end else if (csr) begin
            stallF = 1;
            flushF = 1;
        end else begin
            // do nothing
        end
    end

endmodule


`endif