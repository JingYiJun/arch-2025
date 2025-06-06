`ifndef DECODE_SV
`define DECODE_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "include/pipeline.sv"
`include "src/pipeline/decode/decoder.sv"
`endif

// decode stage, always comb input and output
module decode
  import common::*;
  import pipeline::*;
(
    input  fetch_data_t  dataF,
    output decode_data_t dataD,

    output creg_addr_t  ra1, 
    output creg_addr_t  ra2,
    input  word_t       rd1, 
    input  word_t       rd2,

    output csr_addr_t   csr_addr,
    input  word_t       csr_data
);

    control_t ctl;

    decoder decoder(
        .pc(dataF.instr.pc),
        .raw_instr(dataF.instr.raw_instr),
        .imm(dataD.imm),
        .ctl(ctl)
    );

    assign dataD.valid = dataF.valid;
    assign dataD.ctl = dataF.valid ? ctl : '0;
    assign dataD.dst = dataF.instr.raw_instr[11:7];
    assign dataD.instr = dataF.instr;
    assign ra1 = dataF.instr.raw_instr[19:15];
    assign ra2 = dataF.instr.raw_instr[24:20];
    assign dataD.rs1 = dataF.instr.raw_instr[19:15];
    assign dataD.rs2 = dataF.instr.raw_instr[24:20];
    assign dataD.srca = rd1;
    assign dataD.srcb = rd2;
    assign csr_addr = dataF.instr.raw_instr[31:20];
    assign dataD.csr_addr = dataF.instr.raw_instr[31:20];
    assign dataD.csr_data = csr_data;
    
  
endmodule

`endif
