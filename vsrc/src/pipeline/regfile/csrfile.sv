`ifndef __CSRFILE_SV
`define __CSRFILE_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "include/pipeline.sv"
`include "include/csr.sv"
`endif

module csrfile 
    import common::*;
    import pipeline::*;
    import csr_pkg::*;(
    input  logic        clk, reset,
    input  csr_addr_t   raddr,
    input  csr_addr_t   waddr,
    input  u1           wen,        // CSR 写使能
    input  word_t       wdata,      // 写数据
    input  u1           ren,
    output word_t       rdata,      // 读数据
    
    // Exception handling interface
    input  mem_data_t   dataM,    // 从 memory 阶段传来的数据，用于判断是否有异常
    output word_t       mtvec_out,           // mtvec值输出
    output word_t       mepc_out,            // mepc值输出
    output logic [1:0]  priviledge_mode_out,     // 当前特权级

    // ready 信号
    output logic        ready,
    input  logic        all_ready
);

    // word_t mstatus;
    mstatus_t mstatus;
    word_t mtvec, mip, mie, mscratch, mhartid;
    word_t mcause, mtval, mepc, mcycle, satp;
    logic [1:0] priviledge_mode;
    word_t exception_pc;
    word_t exception_cause;

    wire exception = dataM.ctl.exception;
    wire mret = dataM.ctl.mret;

    assign exception_pc = dataM.instr.pc;

    always_comb begin
        if (dataM.ctl.exception) begin
            case (priviledge_mode)
                PRIV_U: exception_cause = MCAUSE_ECALL_U;
                PRIV_S: exception_cause = MCAUSE_ECALL_S;
                PRIV_M: exception_cause = MCAUSE_ECALL_M;
                default: exception_cause = MCAUSE_ECALL_M;
            endcase
        end else begin
            exception_cause = 0;
        end
    end

    assign mtvec_out = mtvec;
    assign mepc_out = mepc;

    always_comb begin
        unique case (raddr)
            CSR_MSTATUS: rdata = mstatus;
            CSR_MTVEC:   rdata = mtvec;
            CSR_MIP:     rdata = mip;
            CSR_MIE:     rdata = mie;
            CSR_MSCRATCH: rdata = mscratch;
            CSR_MEPC:    rdata = mepc;
            CSR_MCAUSE:  rdata = mcause;
            CSR_MTVAL:   rdata = mtval;
            CSR_MCYCLE:  rdata = mcycle;
            CSR_SATP:    rdata = satp;
            CSR_MHARTID: rdata = mhartid;
            default:     rdata = 0;
        endcase        
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            mstatus <= 0;
            mtvec <= 0;
            mip <= 0;
            mie <= 0;
            mscratch <= 0;
            mepc <= 0;
            mcause <= 0;
            mtval <= 0;
            mcycle <= 0;
            mhartid <= 0;
            satp <= 0;
            priviledge_mode <= PRIV_M;  // Reset to machine mode
            ready <= 0;
        end else if (all_ready) begin
            priviledge_mode_out <= priviledge_mode;
            ready <= 0;
        end else begin
            // Handle exceptions
            if (!ready) begin 
                // 仅在 ready 信号为 0 时（1周期的延迟），写入 csrfile，防止数据被重复写入
                if (exception) begin
                    // Save current status
                    mepc <= exception_pc;
                    mcause <= exception_cause;
                    mtval <= 0;
                    
                    // Update mstatus for exception entry
                    mstatus.mpie <= mstatus.mie;        // Save current MIE
                    mstatus.mie <= 1'b0;                // Disable interrupts
                    mstatus.mpp <= priviledge_mode;     // Save current privilege mode
                    priviledge_mode <= PRIV_M;          // Enter machine mode
                end 
                // Handle mret
                else if (mret) begin
                    // Restore status from mstatus
                    mstatus.mie <= mstatus.mpie;        // Restore MIE
                    mstatus.mpie <= 1'b1;               // Set MPIE to 1
                    priviledge_mode <= mstatus.mpp;     // Restore privilege mode
                    mstatus.mpp <= PRIV_U;              // Set MPP to least privilege
                end
                // Normal CSR writes
                else if (wen) begin
                    unique case (waddr)
                        CSR_MSTATUS: mstatus <= wdata & MSTATUS_MASK;
                        CSR_MTVEC:   mtvec <= wdata & MTVEC_MASK;
                        CSR_MIP:     mip <= wdata & MIP_MASK;
                        CSR_MIE:     mie <= wdata;
                        CSR_MSCRATCH: mscratch <= wdata;
                        CSR_MEPC:    mepc <= wdata;
                        CSR_MCAUSE:  mcause <= wdata;
                        CSR_MTVAL:   mtval <= wdata;
                        CSR_MCYCLE:  mcycle <= wdata;
                        CSR_SATP:    satp <= wdata;
                        default:     ;
                    endcase
                end
            end
            
            // Always increment cycle counter (unless being written)
            if (!wen || (wen && waddr != CSR_MCYCLE)) begin
                mcycle <= mcycle + 1;
            end
            ready <= 1; // 一周期后，csrfile 被赋值，ready 信号被拉高
        end
    end

endmodule

`endif
