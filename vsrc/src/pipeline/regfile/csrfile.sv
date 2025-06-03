`ifndef __CSRFILE_SV
`define __CSRFILE_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "include/pipeline.sv"
`include "include/csr.sv"
`endif

/* verilator lint_off PINMISSING */
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
    input  word_t       pc,
    input  fetch_data_t dataF,
    input  decode_data_t dataD,
    input  exec_data_t  dataE,
    input  mem_data_t   dataM,
    output word_t       mtvec_out,           // mtvec值输出
    output word_t       mepc_out,            // mepc值输出
    output logic [1:0]  priviledge_mode_out,     // 当前特权级

    // ready 信号
    output logic        ready,
    input  logic        all_ready,

    // interrupt 信号
    input  logic        trint, swint, exint,
    output logic        interrupt_update_pc
);

    // word_t mstatus;
    mstatus_t mstatus;
    word_t mtvec, mip, mie, mscratch, mhartid;
    word_t mcause, mtval, mepc, mcycle, satp;
    logic [1:0] priviledge_mode;
    word_t exception_pc;
    word_t interrupt_pc;
    word_t exception_cause;
    word_t interrupt_cause;
    logic interrupt_pending;

    typedef enum {
	   EXCEPTION_CHECK, INTERRUPT_CHECK, DONE
    } csr_check_state_t;

    csr_check_state_t csr_check_state;

    wire exception = dataM.ctl.exception;
    wire mret = dataM.ctl.mret;
    assign ready = csr_check_state == DONE;

    always_comb begin
        exception_pc = 0;
        exception_cause = 0;
        if (exception) begin
            exception_pc = dataM.instr.pc;
            if (dataM.ctl.instruction_address_misaligned) begin
                exception_cause = MCAUSE_INSTRUCTION_ADDRESS_MISALIGNED;
            end else if (dataM.ctl.invalid_instruction) begin
                exception_cause = MCAUSE_ILLEGAL_INSTRUCTION;
            end else if (dataM.ctl.load_address_misaligned) begin
                exception_cause = MCAUSE_LOAD_ADDRESS_MISALIGNED;
            end else if (dataM.ctl.store_address_misaligned) begin
                exception_cause = MCAUSE_STORE_AMO_ADDRESS_MISALIGNED;
            end else if (dataM.ctl.ecall) begin
                case (priviledge_mode)
                    PRIV_U: exception_cause = MCAUSE_ECALL_U;
                    PRIV_S: exception_cause = MCAUSE_ECALL_S;
                    PRIV_M: exception_cause = MCAUSE_ECALL_M;
                    default: exception_cause = MCAUSE_ECALL_M;
                endcase
            end
        end

        interrupt_pc = dataM.valid ? dataM.instr.pc + 4 : dataE.valid ? dataE.instr.pc : dataD.valid ? dataD.instr.pc : dataF.valid ? dataF.instr.pc : pc;
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
            mie <= 0;
            mscratch <= 0;
            mepc <= 0;
            mcause <= 0;
            mtval <= 0;
            mcycle <= 0;
            mhartid <= 0;
            satp <= 0;
            priviledge_mode <= PRIV_M;  // Reset to machine mode
            csr_check_state <= EXCEPTION_CHECK;
            interrupt_update_pc <= 0;
        end else if (all_ready) begin
            priviledge_mode_out <= priviledge_mode;
            csr_check_state <= EXCEPTION_CHECK;
            interrupt_update_pc <= 0;
        end else begin
            case (csr_check_state)
                // Handle exceptions 
                EXCEPTION_CHECK: begin
                    csr_check_state <= INTERRUPT_CHECK;

                    // 仅在 state 信号为 EXCEPTION_CHECK 时（1周期的延迟），写入 csrfile，防止数据被重复写入
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
                INTERRUPT_CHECK: begin
                    csr_check_state <= DONE;

                    // 仅在 state 信号为 INTERRUPT_CHECK 时（1周期的延迟），写入 csrfile，防止数据被重复写入
                    if (interrupt_pending) begin
                        // Save current status
                        mepc <= interrupt_pc;
                        mcause <= interrupt_cause | MCAUSE_INTERRUPT_MASK;
                        mtval <= 0;

                        // Update mstatus for exception entry
                        mstatus.mpie <= mstatus.mie;        // Save current MIE
                        mstatus.mie <= 1'b0;                // Disable interrupts
                        mstatus.mpp <= priviledge_mode;     // Save current privilege mode
                        priviledge_mode <= PRIV_M;          // Enter machine mode

                        // interrupt signal for flush pipeline and update pc
                        interrupt_update_pc <= 1;
                    end
                end
                DONE: begin
                    ;
                end
            endcase
            
            // Always increment cycle counter (unless being written)
            if (!wen || (wen && waddr != CSR_MCYCLE)) begin
                mcycle <= mcycle + 1;
            end
        end
    end

    // interrupt

    assign mip = {52'b0, exint, 3'b0, trint, 3'b0, swint, 3'b0};

    wire interrupt_valid = (priviledge_mode == PRIV_U) || mstatus.mie;

    always_comb begin
        interrupt_pending = 0;
        interrupt_cause = 0;
        if (interrupt_valid) begin
            if (mip[3] && mie[3]) begin
                interrupt_pending = 1;
                interrupt_cause = MCAUSE_SOFTWARE_INTERRUPT;
            end else if (mip[7] && mie[7]) begin
                interrupt_pending = 1;
                interrupt_cause = MCAUSE_TIMER_INTERRUPT;
            end else if (mip[11] && mie[11]) begin
                interrupt_pending = 1;
                interrupt_cause = MCAUSE_EXTERNAL_INTERRUPT;
            end
        end
    end



endmodule

`endif
