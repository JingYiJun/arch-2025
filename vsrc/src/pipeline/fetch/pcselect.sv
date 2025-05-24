`ifndef __PCSELECT_SV
`define __PCSELECT_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "include/pipeline.sv"
`endif

module pcselect
	import common::*;
	import pipeline::*;
(
    input  u64 pcplus4,
    input  u64 pcjump,
    input  u1  jump,
    input  u64 mtvec,           // mtvec value for exception handling
    input  u64 mepc,            // mepc value for mret
    input  u1  exception,       // exception occurred
    input  u1  mret,            // mret instruction
    output u64 pc_selected
);

    always_comb begin
        // Priority: exception > mret > jump > pc+4
        // Exception and mret have higher priority than normal control flow
        if (exception) begin
            pc_selected = mtvec & ~64'h3;  // Align to 4-byte boundary and use direct mode
        end else if (mret) begin
            pc_selected = mepc & ~64'h3;   // Align to 4-byte boundary
        end else if (jump) begin
            pc_selected = pcjump;          // Normal jump/branch
        end else begin
            pc_selected = pcplus4;         // Sequential execution
        end
    end

endmodule

`endif