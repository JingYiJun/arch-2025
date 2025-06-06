`ifndef __REGFILE_SV
`define __REGFILE_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "include/pipeline.sv"
`endif

module regfile
    import common::*;
    import pipeline::*;(
    input  logic        clk, reset,
    input  creg_addr_t  ra1, ra2,
    output word_t       rd1, rd2,
    input  logic        wen,
    input  creg_addr_t  wa,
    input  word_t       wd,
    output logic        ready,
    input  logic        all_ready
);

    word_t regs [31:0];
    word_t regs_nxt [31:0];

    always_comb begin
        for (int i = 0; i < 32; i++) begin
            if (wen && (i[4:0] == wa) && (wa != 0)) begin
                regs_nxt[i[4:0]] = wd;
            end else begin
                regs_nxt[i[4:0]] = regs[i[4:0]];
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            for (int i = 0; i < 32; i++) begin
                regs[i[4:0]] <= 64'h0;
            end
            ready <= 0;
        end else if (all_ready) begin
            ready <= 0; // 重置 ready 信号
        end else begin
            for (int i = 0; i < 32; i++) begin
                regs[i[4:0]] <= regs_nxt[i[4:0]];
            end
            ready <= 1; // 一周期后，regs 被赋值，ready 信号被拉高
        end
    end

    assign rd1 = (ra1 == 5'd0) ? 64'b0 : regs_nxt[ra1];
    assign rd2 = (ra2 == 5'd0) ? 64'b0 : regs_nxt[ra2];

endmodule
`endif