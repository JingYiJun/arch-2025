`ifndef __MMU_SV
`define __MMU_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "include/csr.sv"
`endif

module mmu
    import common::*;
    import csr_pkg::*;
(
    input logic clk,
    input logic rst,

    input word_t satp,
    input logic [1:0] priviledge_mode,

    input cbus_req_t req_virt,
    output cbus_req_t req_phys,
    input cbus_resp_t resp_phys,
    output cbus_resp_t resp_virt,

    output logic skip
);
    typedef enum {
        CLEANUP,
        IDLE, // idle state
        PT1, PT2, PT3, // fetch page table x
        PHY // physical address
    } mmu_state;

    mmu_state state;

    logic resp_phys_last_ready;
    wire phy_ready = !resp_phys_last_ready && resp_phys.last && resp_phys.ready;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            skip <= 0;

            resp_virt <= 0;
            req_phys <= 0;
        end else begin
            resp_phys_last_ready <= resp_phys.ready;
            case (state)
                CLEANUP: begin
                    // clear the resp of last mmu translate
                    state <= IDLE;
                    resp_virt.last <= 0;
                    resp_virt.ready <= 0;
                    resp_virt.data <= 0;
                    skip <= 0;
                end

                IDLE: if (req_virt.valid) // the core send a request
                    if (priviledge_mode == PRIV_M || satp[63:60] == 0) begin
                        state <= PHY;
                        req_phys.valid <= req_virt.valid;
                        req_phys.is_write <= req_virt.is_write;
                        req_phys.size <= req_virt.size;
                        req_phys.addr <= req_virt.addr;
                        req_phys.strobe <= req_virt.strobe;
                        req_phys.data <= req_virt.data;
                        req_phys.len <= req_virt.len;
                        req_phys.burst <= req_virt.burst;
                    end else begin
                        state <= PT1;
                        req_phys.valid <= req_virt.valid;
                        req_phys.is_write <= 0;
                        req_phys.size <= MSIZE8;
                        req_phys.addr <= {8'b0, satp[43:0]/* PPN */, req_virt.addr[38:30], 3'b0};
                        req_phys.strobe <= 0; // read
                        req_phys.data <= req_virt.data;
                        req_phys.len <= req_virt.len;
                        req_phys.burst <= req_virt.burst;
                    end

                PT1: if (phy_ready) begin
                    state <= PT2;
                    req_phys.valid <= req_virt.valid;
                    req_phys.is_write <= 0;
                    req_phys.size <= MSIZE8;
                    req_phys.addr <= {8'b0, resp_phys.data[53:10], req_virt.addr[29:21], 3'b0};
                    req_phys.strobe <= 0; // read
                    req_phys.data <= req_virt.data;
                    req_phys.len <= req_virt.len;
                    req_phys.burst <= req_virt.burst;
                end else if (!req_virt.valid) begin
                    state <= CLEANUP;

                    req_phys.valid <= 0;
                end

                PT2: if (phy_ready) begin
                    state <= PT3;
                    req_phys.valid <= req_virt.valid;
                    req_phys.is_write <= 0;
                    req_phys.size <= MSIZE8;
                    req_phys.addr <= {8'b0, resp_phys.data[53:10], req_virt.addr[20:12], 3'b0};
                    req_phys.strobe <= 0; // read
                    req_phys.data <= req_virt.data;
                    req_phys.len <= req_virt.len;
                    req_phys.burst <= req_virt.burst;
                end else if (!req_virt.valid) begin
                    state <= CLEANUP;

                    req_phys.valid <= 0;
                end

                PT3: if (phy_ready) begin
                    state <= PHY;
                    req_phys.valid <= req_virt.valid;
                    req_phys.is_write <= req_virt.is_write;
                    req_phys.size <= req_virt.size;
                    req_phys.addr <= {8'b0, resp_phys.data[53:10], req_virt.addr[11:0]};
                    req_phys.strobe <= req_virt.strobe;
                    req_phys.data <= req_virt.data;
                    req_phys.len <= req_virt.len;
                    req_phys.burst <= req_virt.burst;

                    skip <= resp_phys.data[29] == 0; // for the stupid difftest
                end else if (!req_virt.valid) begin
                    state <= CLEANUP;

                    req_phys.valid <= 0;
                end

                PHY: if (phy_ready) begin
                    state <= CLEANUP;

                    // clear the request
                    req_phys.valid <= 0;

                    // copy the result to output
                    resp_virt.last <= resp_phys.last;
                    resp_virt.ready <= resp_phys.ready;
                    resp_virt.data <= resp_phys.data;
                end
            endcase
        end
    end

endmodule

`endif