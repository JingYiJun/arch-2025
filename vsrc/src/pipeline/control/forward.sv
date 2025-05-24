`ifndef __FORWARD_SV
`define __FORWARD_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "include/pipeline.sv"
`endif

module forward
    import common::*;
    import pipeline::*; (
    input  fwd_data_t   ex_fwd,
    input  fwd_data_t   mem_fwd,
    input  decode_t     decode,
    output word_t       alusrca,
    output word_t       alusrcb
);
    wire ex_fwd_valid_alusrca = ex_fwd.valid && ex_fwd.dst != 0 && ex_fwd.dst == decode.rs1;
    wire ex_fwd_valid_alusrcb = ex_fwd.valid && ex_fwd.dst != 0 && ex_fwd.dst == decode.rs2;
    wire mem_fwd_valid_alusrca = mem_fwd.valid && mem_fwd.dst != 0 && mem_fwd.dst == decode.rs1;
    wire mem_fwd_valid_alusrcb = mem_fwd.valid && mem_fwd.dst != 0 && mem_fwd.dst == decode.rs2;

    always_comb begin
        if (ex_fwd_valid_alusrca) begin
            alusrca = ex_fwd.data;
        end else if (mem_fwd_valid_alusrca) begin
            alusrca = mem_fwd.data;
        end else begin
            alusrca = decode.srca;
        end
    
        if (ex_fwd_valid_alusrcb) begin
            alusrcb = ex_fwd.data;
        end else if (mem_fwd_valid_alusrcb) begin
            alusrcb = mem_fwd.data;
        end else begin
            alusrcb = decode.srcb;
        end
    end

endmodule


`endif