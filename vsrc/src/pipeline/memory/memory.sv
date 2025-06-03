`ifndef MEMORY_SV
`define MEMORY_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "include/pipeline.sv"
`include "include/csr.sv"
`endif

module memory
    import common::*;
    import pipeline::*;
    import csr_pkg::*;
(
    input  logic        clk, reset,
    input  exec_data_t  dataE,
    input  dbus_resp_t  dresp,
    output dbus_req_t   dreq,
    output mem_data_t   dataM,
    output logic        readyM,
    input  logic        all_ready
);
    u6 offset_bit;
    u3 offset_byte;
    word_t memout;

    typedef enum {
	   WAITING, RECEIVED
    } mem_access_state_t;

	mem_access_state_t mem_access_state;

    assign offset_byte = dataE.aluout[2:0];
    assign offset_bit = {dataE.aluout[2:0], 3'b0};
 
    assign dreq.addr  = dataE.aluout;
    assign dataM.mem_addr = dataE.aluout;
    assign dataM.csr_addr = dataE.csr_addr;
    assign dataM.csr_data = dataE.csr_data;

    wire mem_access = dataE.ctl.mem_read | dataE.ctl.mem_write;
    assign dreq.data  = dataE.rd << offset_bit;
	assign dreq.valid = mem_access && (mem_access_state == WAITING);
    assign readyM = mem_access ? mem_access_state == RECEIVED : 1;

    always_comb begin
        dataM.valid = dataE.valid;
        dataM.ctl = dataE.valid ? dataE.ctl : '0;
        dataM.dst = dataE.dst;
        dataM.instr = dataE.instr;

        dreq.strobe = 0;
        dataM.ctl.store_address_misaligned = 0;
        dataM.ctl.load_address_misaligned = 0;
        dreq.size = MSIZE1;

        case (dataE.ctl.op)
            SD, LD: dreq.size = MSIZE8;
            SW, LW, LWU: dreq.size = MSIZE4;
            SH, LH, LHU: dreq.size = MSIZE2;
            SB, LB, LBU: dreq.size = MSIZE1;
            default: ;
        endcase

        case (dataE.ctl.op)
            SD: begin
                dreq.strobe = 8'hff;
                dataM.ctl.store_address_misaligned = dataE.aluout[2:0] != 3'b000;
            end
            SW: begin
                dreq.strobe = 8'hf << offset_byte;
                dataM.ctl.store_address_misaligned = dataE.aluout[1:0] != 2'b00;
            end
            SH: begin
                dreq.strobe = 8'h3 << offset_byte;
                dataM.ctl.store_address_misaligned = dataE.aluout[0] != 1'b0;
            end
            SB: begin
                dreq.strobe = 8'h1 << offset_byte;
                dataM.ctl.store_address_misaligned = 0;
            end
            default: ;
        endcase

        dataM.ctl.load_address_misaligned = 0;
        case (dataE.ctl.op)
            LD: dataM.ctl.load_address_misaligned = dataE.aluout[2:0] != 3'b000;
            LW, LWU: dataM.ctl.load_address_misaligned = dataE.aluout[1:0] != 2'b00;
            LH, LHU: dataM.ctl.load_address_misaligned = dataE.aluout[0] != 1'b0;
            LB, LBU: dataM.ctl.load_address_misaligned = 0;
            default: ;
        endcase

        if (dataM.ctl.load_address_misaligned || dataM.ctl.store_address_misaligned) begin
            dataM.ctl.exception = 1;
        end

        case(dataE.ctl.op)
            LD: begin
                dataM.writedata = memout;
            end
            LW: begin
                dataM.writedata = {{32{memout[31]}}, memout[31:0]};
            end
            LH: begin
                dataM.writedata = {{48{memout[15]}}, memout[15:0]};
            end
            LB: begin
                dataM.writedata = {{56{memout[7]}}, memout[7:0]};
            end
            LWU: begin
                dataM.writedata = {{32{1'b0}}, memout[31:0]};
            end
            LHU: begin
                dataM.writedata = {{48{1'b0}}, memout[15:0]};
            end
            LBU: begin
                dataM.writedata = {{56{1'b0}}, memout[7:0]};
            end
            default: begin
                dataM.writedata = dataE.aluout;
            end
        endcase
        
    end

	always_ff @(posedge clk ) begin
		if (reset) begin
			mem_access_state <= WAITING;
			memout <= 0;
		end else if (all_ready) begin
            mem_access_state <= WAITING;
        end else begin
			case (mem_access_state)
				WAITING: begin
					if (dresp.data_ok) begin
						mem_access_state <= RECEIVED;
						memout <= dresp.data >> offset_bit;
					end
				end
                RECEIVED: begin
                    if (!mem_access) begin
                        mem_access_state <= WAITING;
                    end
                end
			endcase
		end
		
	end
endmodule

`endif
