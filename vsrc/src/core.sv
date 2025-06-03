`ifndef __CORE_SV
`define __CORE_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "include/pipeline.sv"
`include "include/csr.sv"
`include "src/pipeline/fetch/fetch.sv"
`include "src/pipeline/decode/decode.sv"
`include "src/pipeline/execute/execute.sv"
`include "src/pipeline/memory/memory.sv"
`include "src/pipeline/regfile/pipereg.sv"
`include "src/pipeline/regfile/regfile.sv"
`include "src/pipeline/regfile/csrfile.sv"
`include "src/pipeline/control/hazard.sv"
`include "src/pipeline/control/forward.sv"
`endif

module core 
	import common::*;
	import pipeline::*;
	import csr_pkg::*;
(
	input  logic       clk, reset,
	output ibus_req_t  ireq,
	input  ibus_resp_t iresp,
	output dbus_req_t  dreq,
	input  dbus_resp_t dresp,
	input  logic       trint, swint, exint,
	output  word_t satp,
	output  logic [1:0] priviledge_mode,
	input  logic skip
);
	logic stallF, stallD, stallE, stallM, stallW;
	logic flushF, flushD, flushE, flushM, flushW;
	logic readyF, readyD, readyE, readyM, readyW, ready_regfile, ready_csrfile;
	logic jump, exception, mret, interrupt_update_pc;

	wire all_ready = readyF && readyD && readyE && readyM && readyW;

	assign readyD = 1;
	assign readyE = 1;
	assign readyW = ready_regfile && ready_csrfile;

	word_t mtvec_out, mepc_out;

	addr_t pc, pc_nxt;
	fetch_data_t 	dataF, dataF_nxt;
	decode_data_t 	dataD, dataD_nxt;
	exec_data_t 	dataE, dataE_nxt;
	mem_data_t 		dataM, dataM_nxt;

	wire validpc = pc != 0;
	wire validF = dataF.valid;
	wire validD = dataD.valid;
	wire validE = dataE.valid;
	wire validM = dataM.valid;

	creg_addr_t ra1, ra2;
	word_t rd1, rd2;
	
	csr_addr_t csr_addr;
	word_t csr_data;

	word_t alusrca, alusrcb;

	wire commit_valid = all_ready && dataM.instr.raw_instr != 0;

	assign satp = csrfile.satp;

	pipereg #(.T(u64), .INIT(PCINIT)) pcupdate(
		.clk(clk),
		.reset(reset),
		.stall(stallF),
		.flush(0),
		.data_nxt(pc_nxt),
		.data(pc),
		.all_ready(all_ready)
	);

	pipereg #(.T(fetch_data_t)) if_id_reg(
		.clk	(clk),
		.reset  (reset),
		.data_nxt(dataF_nxt),
		.flush  (flushD),
		.stall  (stallD),
		.data  (dataF),
		.all_ready(all_ready)
	);

	pipereg #(.T(decode_data_t)) id_ex_reg(
		.clk	(clk),
		.reset  (reset),
		.data_nxt(dataD_nxt),
		.flush  (flushE),
		.stall  (stallE),
		.data  (dataD),
		.all_ready(all_ready)
	);

	pipereg #(.T(exec_data_t)) ex_mem_reg(
		.clk	(clk),
		.reset  (reset),
		.data_nxt(dataE_nxt),
		.flush  (flushM),
		.stall  (stallM),
		.data  (dataE),
		.all_ready(all_ready)
	);

	pipereg #(.T(mem_data_t)) mem_wb_reg(
		.clk	(clk),
		.reset  (reset),
		.data_nxt(dataM_nxt),
		.flush  (flushW),
		.stall  (stallW),
		.data  (dataM),
		.all_ready(all_ready)
	);

	fetch fetch(
		.pc			(pc),
		.flush		(flushF),
		.iresp 		(iresp),
		.ireq 		(ireq),
		.dataF     	(dataF_nxt),
		.readyF     (readyF)
	);

	pcselect pcselect(
		.pcplus4 	(pc + 4),
		.pcjump     (dataE_nxt.pcjump),
		.jump 		(jump),
		.mtvec      (mtvec_out),
		.mepc       (mepc_out),
		.exception  (exception || interrupt_update_pc),
		.mret       (mret),
		.pc_selected(pc_nxt)
	);

	decode decode(
		.dataF (dataF),
		.dataD (dataD_nxt),
		.ra1   (ra1),
		.ra2   (ra2),
		.rd1   (rd1),
		.rd2   (rd2),
		.csr_addr(csr_addr),
		.csr_data(csr_data)
	);

	execute execute(
		.alusrca (alusrca),
		.alusrcb (alusrcb),
		.dataD 	 (dataD),
		.dataE   (dataE_nxt)
	);

	memory memory(
		.clk    (clk),
		.reset  (reset),
		.all_ready(all_ready),
		.dataE  (dataE),
		.dresp  (dresp),
		.dreq   (dreq),
		.dataM  (dataM_nxt),
		.readyM (readyM)
	);

	// 一个周期一定会写入，确保 decode 阶段读取到正确的值
	regfile regfile(
		.clk    (clk),
		.reset  (reset),
		.ra1    (ra1),
		.ra2    (ra2),
		.rd1    (rd1),
		.rd2    (rd2),
		.wen    (dataM.ctl.reg_write),
		.wa     (dataM.dst),
		.wd     (dataM.writedata),
		.ready  (ready_regfile),
		.all_ready(all_ready)
	);

	hazard hazard(
		.jump(jump),
		.exception(exception),
		.mret(mret),
		.stallF(stallF),
		.stallD(stallD),
		.stallE(stallE),
		.stallM(stallM),
		.stallW(stallW),
		.flushF(flushF),
		.flushD(flushD),
		.flushE(flushE),
		.flushM(flushM),
		.flushW(flushW),
		.dataD_nxt(dataD_nxt),
		.dataD(dataD),
		.dataE_nxt(dataE_nxt),
		.dataE(dataE),
		.dataM_nxt(dataM_nxt),
		.dataM(dataM),
		.validpc(validpc),
		.validF(validF),
		.validD(validD),
		.validE(validE),
		.validM(validM),
		.interrupt_update_pc(interrupt_update_pc)
	);

	forward forward (
		.ex_fwd  	(fwd_data_t'({dataE.dst, dataE.aluout, dataE.ctl.reg_write && !dataE.ctl.mem_to_reg})),
		.mem_fwd  	(fwd_data_t'({dataM.dst, dataM.writedata, dataM.ctl.reg_write})),
		.decode 	(decode_t'({dataD.rs1, dataD.rs2, dataD.srca, dataD.srcb})),
		.alusrca 	(alusrca),
		.alusrcb 	(alusrcb)
	);

	csrfile csrfile(
		.clk(clk),
		.reset(reset),
		.raddr(csr_addr),
		.waddr(dataM.csr_addr),
		.wen(dataM.ctl.csr),
		.wdata(dataM.csr_data),
		.ren(dataD_nxt.ctl.csr),
		.rdata(csr_data),
		.ready(ready_csrfile),
		.all_ready(all_ready),
		.mtvec_out(mtvec_out),
		.mepc_out(mepc_out),
		.priviledge_mode_out(priviledge_mode),
		.interrupt_update_pc(interrupt_update_pc),
		.pc(pc),
		.dataF(dataF),
		.dataD(dataD),
		.dataE(dataE),
		.dataM(dataM),
		.trint(trint),
		.swint(swint),
		.exint(exint)
	);



`ifdef VERILATOR
	DifftestInstrCommit DifftestInstrCommit(
		.clock              (clk),
		.coreid             (csrfile.mhartid[7:0]),
		.index              (0),
		.valid              (commit_valid),
		.pc                 (dataM.instr.pc),
		.instr              (dataM.instr.raw_instr),
		.skip               ((dataM.ctl.mem_read | dataM.ctl.mem_write) & dataM.mem_addr[31] == 0),
		.isRVC              (0),
		.scFailed           (0),
		.wen                (dataM.ctl.reg_write),
		.wdest              ({3'b000, dataM.dst}),
		.wdata              (dataM.writedata)
	);

	DifftestArchIntRegState DifftestArchIntRegState (
		.clock              (clk),
		.coreid             (0),
		.gpr_0              (regfile.regs_nxt[0]),
		.gpr_1              (regfile.regs_nxt[1]),
		.gpr_2              (regfile.regs_nxt[2]),
		.gpr_3              (regfile.regs_nxt[3]),
		.gpr_4              (regfile.regs_nxt[4]),
		.gpr_5              (regfile.regs_nxt[5]),
		.gpr_6              (regfile.regs_nxt[6]),
		.gpr_7              (regfile.regs_nxt[7]),
		.gpr_8              (regfile.regs_nxt[8]),
		.gpr_9              (regfile.regs_nxt[9]),
		.gpr_10             (regfile.regs_nxt[10]),
		.gpr_11             (regfile.regs_nxt[11]),
		.gpr_12             (regfile.regs_nxt[12]),
		.gpr_13             (regfile.regs_nxt[13]),
		.gpr_14             (regfile.regs_nxt[14]),
		.gpr_15             (regfile.regs_nxt[15]),
		.gpr_16             (regfile.regs_nxt[16]),
		.gpr_17             (regfile.regs_nxt[17]),
		.gpr_18             (regfile.regs_nxt[18]),
		.gpr_19             (regfile.regs_nxt[19]),
		.gpr_20             (regfile.regs_nxt[20]),
		.gpr_21             (regfile.regs_nxt[21]),
		.gpr_22             (regfile.regs_nxt[22]),
		.gpr_23             (regfile.regs_nxt[23]),
		.gpr_24             (regfile.regs_nxt[24]),
		.gpr_25             (regfile.regs_nxt[25]),
		.gpr_26             (regfile.regs_nxt[26]),
		.gpr_27             (regfile.regs_nxt[27]),
		.gpr_28             (regfile.regs_nxt[28]),
		.gpr_29             (regfile.regs_nxt[29]),
		.gpr_30             (regfile.regs_nxt[30]),
		.gpr_31             (regfile.regs_nxt[31])
	);

    DifftestTrapEvent DifftestTrapEvent(
		.clock              (clk),
		.coreid             (csrfile.mhartid[7:0]),
		.valid              (0),
		.code               (0),
		.pc                 (0),
		.cycleCnt           (0),
		.instrCnt           (0)
	);

	DifftestCSRState DifftestCSRState(
		.clock              (clk),
		.coreid             (csrfile.mhartid[7:0]),
		.priviledgeMode     (csrfile.priviledge_mode),
		.mstatus            (csrfile.mstatus),
		.sstatus            (csrfile.mstatus & SSTATUS_MASK), /* mstatus & SSTATUS_MASK */
		.mepc               (csrfile.mepc),
		.sepc               (0),
		.mtval              (csrfile.mtval),
		.stval              (0),
		.mtvec              (csrfile.mtvec),
		.stvec              (0),
		.mcause             (csrfile.mcause),
		.scause             (0),
		.satp               (csrfile.satp),
		.mip                (csrfile.mip),
		.mie                (csrfile.mie),
		.mscratch           (csrfile.mscratch),
		.sscratch           (0),
		.mideleg            (0),
		.medeleg            (0)
	);
`endif
endmodule
`endif