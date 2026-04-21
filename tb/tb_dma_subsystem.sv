import dma_pkg::*;

module tb_dma_subsystem;

  localparam int REGS_PER_CH = 4;
  localparam int MEM_DEPTH   = 256;
  localparam int TIMEOUT_CYCLES = 500;

  logic clk;
  logic rst_n;

  logic                              cfg_we;
  logic                              cfg_re;
  logic [$clog2(N_CH*REGS_PER_CH)-1:0] cfg_addr;
  logic [31:0]                       cfg_wdata;
  logic [31:0]                       cfg_rdata;

  logic [N_CH-1:0] start_clear;
  logic [N_CH-1:0] chan_active;
  logic [N_CH-1:0] chan_done;

  dma_cfg_t        cfg0_reg, cfg1_reg;
  dma_chan_state_t chan0_state, chan1_state;
  logic            sched_valid;
  logic [$clog2(N_CH)-1:0] sched_idx;
  logic            sched_advance;
  mem_req_t        mem_req;
  mem_rsp_t        mem_rsp;

  logic [7:0] mem [0:MEM_DEPTH-1];
  logic       mem_ready;
  logic       pending_read_enable;
  logic       mem_rsp_valid_reg;
  logic [7:0] pending_read_data;

  integer i;

  cfg_reg u_cfg_reg (
    .clk        (clk),
    .rst_n      (rst_n),
    .cfg_we     (cfg_we),
    .cfg_re     (cfg_re),
    .cfg_addr   (cfg_addr),
    .cfg_wdata  (cfg_wdata),
    .cfg_rdata  (cfg_rdata),
    .start_clear(start_clear),
    .chan_active(chan_active),
    .chan_done  (chan_done),
    .cfg0_out   (cfg0_reg),
    .cfg1_out   (cfg1_reg)
  );

  dma_scheduler u_dma_scheduler (
    .clk          (clk),
    .rst_n        (rst_n),
    .grant_advance(sched_advance),
    .cfg0_in      (cfg0_reg),
    .cfg1_in      (cfg1_reg),
    .ch0_active   (chan_active[0]),
    .ch1_active   (chan_active[1]),
    .grant_valid  (sched_valid),
    .grant_idx    (sched_idx)
  );

  dma_controller u_dma_controller (
    .clk           (clk),
    .rst_n         (rst_n),
    .sched_valid   (sched_valid),
    .sched_idx     (sched_idx),
    .sched_advance (sched_advance),
    .cfg0_in       (cfg0_reg),
    .cfg1_in       (cfg1_reg),
    .start_clear   (start_clear),
    .chan0_state_out(chan0_state),
    .chan1_state_out(chan1_state),
    .mem_req       (mem_req),
    .mem_rsp       (mem_rsp)
  );

  assign chan_active[0] = chan0_state.active;
  assign chan_active[1] = chan1_state.active;
  assign chan_done[0]   = chan0_state.done;
  assign chan_done[1]   = chan1_state.done;

  assign mem_rsp.ready = mem_ready;
  assign mem_rsp.valid = mem_rsp_valid_reg;
  assign mem_rsp.rdata = pending_read_data;

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_ready          <= 1'b1;
      pending_read_enable <= 1'b0;
      mem_rsp_valid_reg  <= 1'b0;
      pending_read_data  <= 8'h00;
    end else begin
      mem_rsp_valid_reg <= 1'b0;

      if (mem_ready && mem_req.valid) begin
        mem_ready <= 1'b0;
        if (mem_req.rw) begin
          mem[mem_req.addr[7:0]] <= mem_req.wdata;
          pending_read_enable    <= 1'b0;
        end else begin
          pending_read_enable    <= 1'b1;
          pending_read_data      <= mem[mem_req.addr[7:0]];
        end
      end else if (!mem_ready) begin
        mem_ready <= 1'b1;
        if (pending_read_enable) begin
          pending_read_enable <= 1'b0;
          mem_rsp_valid_reg  <= 1'b1;
        end
      end
    end
  end

  task automatic clear_memory;
    begin
      for (i = 0; i < MEM_DEPTH; i = i + 1) begin
        mem[i] = 8'h00;
      end
    end
  endtask

  task automatic cfg_write(
    input logic [$clog2(N_CH*REGS_PER_CH)-1:0] addr,
    input logic [31:0] wdata
  );
    begin
      @(posedge clk);
      cfg_addr  <= addr;
      cfg_wdata <= wdata;
      cfg_we    <= 1'b1;

      @(posedge clk);
      cfg_we    <= 1'b0;
      cfg_addr  <= '0;
      cfg_wdata <= '0;
    end
  endtask

  task automatic wait_done(input int channel);
    integer cycles;
    begin
      cycles = 0;
      while (((channel == 0) ? !chan_active[0] : !chan_active[1]) && (cycles < TIMEOUT_CYCLES)) begin
        @(posedge clk);
        cycles = cycles + 1;
      end

      while (((channel == 0) ? !chan_done[0] : !chan_done[1]) && (cycles < TIMEOUT_CYCLES)) begin
        @(posedge clk);
        cycles = cycles + 1;
      end

      if (cycles == TIMEOUT_CYCLES) begin
        $display("FAIL: channel %0d timed out", channel);
        $finish;
      end
    end
  endtask

  task automatic expect_byte(
    input logic [7:0] addr,
    input logic [7:0] expected
  );
    begin
      if (mem[addr] !== expected) begin
        $display("FAIL: mem[0x%02h] expected 0x%02h got 0x%02h", addr, expected, mem[addr]);
        $finish;
      end
    end
  endtask

  initial begin
    clk                = 1'b0;
    rst_n              = 1'b0;
    cfg_we             = 1'b0;
    cfg_re             = 1'b0;
    cfg_addr           = '0;
    cfg_wdata          = '0;
    clear_memory();

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    // Test 1: channel 0 increments source and destination.
    mem[8'h10] = 8'h11;
    mem[8'h11] = 8'h22;
    mem[8'h12] = 8'h33;
    mem[8'h13] = 8'h44;

    cfg_write(3'd0, 32'h0000_0010); // ch0 src
    cfg_write(3'd1, 32'h0000_0020); // ch0 dst
    cfg_write(3'd2, 32'h0000_0004); // ch0 len
    cfg_write(3'd3, 32'h0000_0007); // start + inc_src + inc_dst

    wait_done(0);
    expect_byte(8'h20, 8'h11);
    expect_byte(8'h21, 8'h22);
    expect_byte(8'h22, 8'h33);
    expect_byte(8'h23, 8'h44);

    // Test 2: channel 1 fixed source, increment destination.
    mem[8'h30] = 8'hA9;

    cfg_write(3'd4, 32'h0000_0030); // ch1 src
    cfg_write(3'd5, 32'h0000_0040); // ch1 dst
    cfg_write(3'd6, 32'h0000_0003); // ch1 len
    cfg_write(3'd7, 32'h0000_0005); // start + inc_dst

    wait_done(1);
    expect_byte(8'h40, 8'hA9);
    expect_byte(8'h41, 8'hA9);
    expect_byte(8'h42, 8'hA9);

    // Test 3: both channels armed together.
    mem[8'h50] = 8'h5A;
    mem[8'h60] = 8'hC3;

    cfg_write(3'd0, 32'h0000_0050); // ch0 src
    cfg_write(3'd1, 32'h0000_0070); // ch0 dst
    cfg_write(3'd2, 32'h0000_0001); // ch0 len
    cfg_write(3'd4, 32'h0000_0060); // ch1 src
    cfg_write(3'd5, 32'h0000_0080); // ch1 dst
    cfg_write(3'd6, 32'h0000_0001); // ch1 len
    cfg_write(3'd3, 32'h0000_0007); // ch0 start
    cfg_write(3'd7, 32'h0000_0007); // ch1 start

    wait_done(0);
    wait_done(1);
    expect_byte(8'h70, 8'h5A);
    expect_byte(8'h80, 8'hC3);

    $display("PASS");
    $finish;
  end

endmodule
