`ifndef __PIPEREG_SV
`define __PIPEREG_SV


`ifdef VERILATOR
`include "include/common.sv"
`endif

module pipereg
    import common::*; #(
    parameter type T = logic,
    parameter T INIT = '0
)(
    input logic clk, reset,
    input T data_nxt, 
    output T data,
    input logic flush, stall, all_ready
);
    always_ff @(posedge clk) begin
        if (reset) begin
            data <= INIT; 
        end else if (all_ready) begin
            // 如果同时有 flush 和 stall，则 stall 优先级更高
            // 例如当 load_use_hazard 和 csr 同时发生时，dataD 会先被 flush，然后被 stall，导致 dataD 的值为 0，少一个执行周期
            // 因此不能 stallD
            if (flush) begin
                data <= INIT;
            end else if (stall) begin
                data <= data;
            end else begin
                data <= data_nxt;
            end
        end
    end
    
endmodule



`endif