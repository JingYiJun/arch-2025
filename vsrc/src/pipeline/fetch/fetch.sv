`ifndef __FETCH_SV
`define __FETCH_SV


`ifdef VERILATOR
`include "include/common.sv"
`include "include/pipeline.sv"
`include "src/pipeline/fetch/pcselect.sv"
`endif

module fetch 
	import common::*;
	import pipeline::*;
(
    input  word_t       pc,
    input  logic        flush,
    input  ibus_resp_t  iresp,
    output ibus_req_t   ireq,
    output fetch_data_t dataF,
    output logic        readyF
);

    assign ireq.addr  = pc;
    assign ireq.valid = 1'b1;
    assign dataF.instr.pc = flush ? 0 : pc;
    assign dataF.instr.raw_instr = flush ? 0 : iresp.data;
    assign readyF = iresp.data_ok;

	
endmodule


`endif 