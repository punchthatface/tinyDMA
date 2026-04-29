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

  logic            sched_valid;
  logic [$clog2(N_CH)-1:0] sched_idx;
  logic            sched_advance;

  logic [ADDR_W-1:0] cfg0_src_base, cfg0_dst_base;
  logic [LEN_W-1:0]  cfg0_len;
  logic              cfg0_inc_src, cfg0_inc_dst, cfg0_start_en;
  logic [ADDR_W-1:0] cfg1_src_base, cfg1_dst_base;
  logic [LEN_W-1:0]  cfg1_len;
  logic              cfg1_inc_src, cfg1_inc_dst, cfg1_start_en;

  logic [ADDR_W-1:0] chan0_src_cur, chan0_dst_cur;
  logic [LEN_W-1:0]  chan0_len_rem;
  logic              chan0_inc_src, chan0_inc_dst, chan0_active_s, chan0_done_s;
  logic [ADDR_W-1:0] chan1_src_cur, chan1_dst_cur;
  logic [LEN_W-1:0]  chan1_len_rem;
  logic              chan1_inc_src, chan1_inc_dst, chan1_active_s, chan1_done_s;

  logic              mem_req_valid, mem_req_rw;
  logic [ADDR_W-1:0] mem_req_addr;
  logic [DATA_W-1:0] mem_req_wdata;
  logic              mem_rsp_ready, mem_rsp_valid;
  logic [DATA_W-1:0] mem_rsp_rdata;

  logic [7:0] mem [0:MEM_DEPTH-1];
  logic       mem_ready;
  logic       pending_read_enable;
  logic       mem_rsp_valid_reg;
  logic [7:0] pending_read_data;
  logic       stall_mode;
  logic [1:0] stall_countdown;

  integer i;
  integer j;

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
    .cfg0_src_base(cfg0_src_base),
    .cfg0_dst_base(cfg0_dst_base),
    .cfg0_len    (cfg0_len),
    .cfg0_inc_src(cfg0_inc_src),
    .cfg0_inc_dst(cfg0_inc_dst),
    .cfg0_start_en(cfg0_start_en),
    .cfg1_src_base(cfg1_src_base),
    .cfg1_dst_base(cfg1_dst_base),
    .cfg1_len    (cfg1_len),
    .cfg1_inc_src(cfg1_inc_src),
    .cfg1_inc_dst(cfg1_inc_dst),
    .cfg1_start_en(cfg1_start_en)
  );

  dma_scheduler u_dma_scheduler (
    .clk          (clk),
    .rst_n        (rst_n),
    .grant_advance(sched_advance),
    .cfg0_start_en(cfg0_start_en),
    .cfg1_start_en(cfg1_start_en),
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
    .cfg0_src_base (cfg0_src_base),
    .cfg0_dst_base (cfg0_dst_base),
    .cfg0_len      (cfg0_len),
    .cfg0_inc_src  (cfg0_inc_src),
    .cfg0_inc_dst  (cfg0_inc_dst),
    .cfg1_src_base (cfg1_src_base),
    .cfg1_dst_base (cfg1_dst_base),
    .cfg1_len      (cfg1_len),
    .cfg1_inc_src  (cfg1_inc_src),
    .cfg1_inc_dst  (cfg1_inc_dst),
    .start_clear   (start_clear),
    .chan0_src_cur (chan0_src_cur),
    .chan0_dst_cur (chan0_dst_cur),
    .chan0_len_rem (chan0_len_rem),
    .chan0_inc_src (chan0_inc_src),
    .chan0_inc_dst (chan0_inc_dst),
    .chan0_active  (chan0_active_s),
    .chan0_done    (chan0_done_s),
    .chan1_src_cur (chan1_src_cur),
    .chan1_dst_cur (chan1_dst_cur),
    .chan1_len_rem (chan1_len_rem),
    .chan1_inc_src (chan1_inc_src),
    .chan1_inc_dst (chan1_inc_dst),
    .chan1_active  (chan1_active_s),
    .chan1_done    (chan1_done_s),
    .mem_req_valid (mem_req_valid),
    .mem_req_rw    (mem_req_rw),
    .mem_req_addr  (mem_req_addr),
    .mem_req_wdata (mem_req_wdata),
    .mem_rsp_ready (mem_rsp_ready),
    .mem_rsp_valid (mem_rsp_valid),
    .mem_rsp_rdata (mem_rsp_rdata)
  );

  assign chan_active[0] = chan0_active_s;
  assign chan_active[1] = chan1_active_s;
  assign chan_done[0]   = chan0_done_s;
  assign chan_done[1]   = chan1_done_s;

  assign mem_rsp_ready = mem_ready;
  assign mem_rsp_valid = mem_rsp_valid_reg;
  assign mem_rsp_rdata = pending_read_data;

  always #5 clk = ~clk;

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      mem_ready          <= 1'b1;
      pending_read_enable <= 1'b0;
      mem_rsp_valid_reg  <= 1'b0;
      pending_read_data  <= 8'h00;
      stall_countdown    <= 2'd0;
    end else begin
      mem_rsp_valid_reg <= 1'b0;

      if (mem_ready && mem_req_valid) begin
        mem_ready <= 1'b0;
        if (stall_mode) begin
          stall_countdown <= 2'd2;
        end
        if (mem_req_rw) begin
          mem[mem_req_addr[7:0]] <= mem_req_wdata;
          pending_read_enable    <= 1'b0;
        end else begin
          pending_read_enable    <= 1'b1;
          pending_read_data      <= mem[mem_req_addr[7:0]];
        end
      end else if (!mem_ready) begin
        if (stall_countdown != 2'd0) begin
          stall_countdown <= stall_countdown - 1'b1;
        end else begin
          mem_ready <= 1'b1;
          if (pending_read_enable) begin
            pending_read_enable <= 1'b0;
            mem_rsp_valid_reg  <= 1'b1;
          end
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
    logic seen_new_activity;
    begin
      cycles = 0;
      seen_new_activity = 1'b0;

      while ((cycles < TIMEOUT_CYCLES) && !seen_new_activity) begin
        if (channel == 0) begin
          if (chan_active[0] || !chan_done[0]) begin
            seen_new_activity = 1'b1;
          end
        end else begin
          if (chan_active[1] || !chan_done[1]) begin
            seen_new_activity = 1'b1;
          end
        end
        if (!seen_new_activity) begin
          @(posedge clk);
          cycles = cycles + 1;
        end
      end

      while (((channel == 0) ? !chan_active[0] && !chan_done[0] : !chan_active[1] && !chan_done[1]) &&
             (cycles < TIMEOUT_CYCLES)) begin
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
      $display("    mem[0x%02h] = 0x%02h", addr, mem[addr]);
    end
  endtask

  task automatic expect_ctrl_status(
    input int channel,
    input logic expected_start,
    input logic expected_active,
    input logic expected_done
  );
    begin
      cfg_re   <= 1'b0;
      cfg_addr <= channel ? 3'd7 : 3'd3;
      @(posedge clk);
      cfg_re   <= 1'b1;
      @(posedge clk);
      if (cfg_rdata[0] !== expected_start ||
          cfg_rdata[8] !== expected_active ||
          cfg_rdata[9] !== expected_done) begin
        $display("FAIL: channel %0d ctrl unexpected: 0x%08h", channel, cfg_rdata);
        $finish;
      end
      $display("    ch%0d ctrl = 0x%08h (start=%0b active=%0b done=%0b)",
               channel, cfg_rdata, cfg_rdata[0], cfg_rdata[8], cfg_rdata[9]);
      cfg_re   <= 1'b0;
      cfg_addr <= '0;
    end
  endtask

  initial begin
    clk                = 1'b0;
    rst_n              = 1'b0;
    cfg_we             = 1'b0;
    cfg_re             = 1'b0;
    cfg_addr           = '0;
    cfg_wdata          = '0;
    stall_mode         = 1'b0;
    clear_memory();

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    $display("");
    $display("[tb_dma_subsystem] Test 1: channel 0 copy, increment source and destination");
    $display("  src=0x10 dst=0x20 len=4 ctrl=start/inc_src/inc_dst");

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
    expect_ctrl_status(0, 1'b0, 1'b0, 1'b1);

    $display("[tb_dma_subsystem] Test 2: channel 1 fixed-source fill");
    $display("  src=0x30 dst=0x40 len=3 ctrl=start/inc_dst");

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
    expect_ctrl_status(1, 1'b0, 1'b0, 1'b1);

    $display("[tb_dma_subsystem] Test 3: fixed destination, increment source");
    $display("  src=0x90 dst=0xA0 len=3 ctrl=start/inc_src");

    // Test 3: fixed destination, increment source.
    mem[8'h90] = 8'h10;
    mem[8'h91] = 8'h20;
    mem[8'h92] = 8'h30;

    cfg_write(3'd0, 32'h0000_0090); // ch0 src
    cfg_write(3'd1, 32'h0000_00A0); // ch0 dst
    cfg_write(3'd2, 32'h0000_0003); // ch0 len
    cfg_write(3'd3, 32'h0000_0003); // start + inc_src

    wait_done(0);
    expect_byte(8'hA0, 8'h30);
    expect_ctrl_status(0, 1'b0, 1'b0, 1'b1);

    $display("[tb_dma_subsystem] Test 4: zero-length transfer");
    $display("  src=0xB1 dst=0xB0 len=0, destination should stay 0xEE");

    // Test 4: zero-length transfer should complete immediately and not touch memory.
    mem[8'hB0] = 8'hEE;
    cfg_write(3'd4, 32'h0000_00B1); // ch1 src
    cfg_write(3'd5, 32'h0000_00B0); // ch1 dst
    cfg_write(3'd6, 32'h0000_0000); // ch1 len
    cfg_write(3'd7, 32'h0000_0007); // start + inc both

    repeat (10) @(posedge clk);
    expect_byte(8'hB0, 8'hEE);
    expect_ctrl_status(1, 1'b0, 1'b0, 1'b1);

    $display("[tb_dma_subsystem] Test 5: both channels armed together");
    $display("  ch0: src=0x50 dst=0x70 len=2, ch1: src=0x60 dst=0x80 len=2");

    // Test 5: both channels armed together with multi-byte copies.
    mem[8'h50] = 8'h5A;
    mem[8'h51] = 8'hA5;
    mem[8'h60] = 8'hC3;
    mem[8'h61] = 8'h3C;

    cfg_write(3'd0, 32'h0000_0050); // ch0 src
    cfg_write(3'd1, 32'h0000_0070); // ch0 dst
    cfg_write(3'd2, 32'h0000_0002); // ch0 len
    cfg_write(3'd4, 32'h0000_0060); // ch1 src
    cfg_write(3'd5, 32'h0000_0080); // ch1 dst
    cfg_write(3'd6, 32'h0000_0002); // ch1 len
    cfg_write(3'd3, 32'h0000_0007); // ch0 start
    cfg_write(3'd7, 32'h0000_0007); // ch1 start

    wait_done(0);
    wait_done(1);
    expect_byte(8'h70, 8'h5A);
    expect_byte(8'h71, 8'hA5);
    expect_byte(8'h80, 8'hC3);
    expect_byte(8'h81, 8'h3C);
    expect_ctrl_status(0, 1'b0, 1'b0, 1'b1);
    expect_ctrl_status(1, 1'b0, 1'b0, 1'b1);

    $display("[tb_dma_subsystem] Test 6: stalled ready/valid memory behavior");
    $display("  src=0xC0 dst=0xD0 len=4 with stall_mode=1");

    // Test 6: same DMA path under slower ready/valid behavior.
    stall_mode = 1'b1;
    mem[8'hC0] = 8'hDE;
    mem[8'hC1] = 8'hAD;
    mem[8'hC2] = 8'hBE;
    mem[8'hC3] = 8'hEF;

    cfg_write(3'd0, 32'h0000_00C0); // ch0 src
    cfg_write(3'd1, 32'h0000_00D0); // ch0 dst
    cfg_write(3'd2, 32'h0000_0004); // ch0 len
    cfg_write(3'd3, 32'h0000_0007); // ch0 start + inc both

    wait_done(0);
    expect_byte(8'hD0, 8'hDE);
    expect_byte(8'hD1, 8'hAD);
    expect_byte(8'hD2, 8'hBE);
    expect_byte(8'hD3, 8'hEF);
    expect_ctrl_status(0, 1'b0, 1'b0, 1'b1);

    $display("[tb_dma_subsystem] Test 7: longer transfer through LEN_W counter path");
    $display("  src=0xE0 dst=0x10 len=16 ctrl=start/inc_src/inc_dst");

    // Test 7: longer transfer near the LEN_W boundary used by the TT build.
    // This catches counter width mistakes without making the sim unnecessarily
    // slow. Addresses stay away from 0xFF so the simple 256-byte model does not
    // wrap during this test.
    stall_mode = 1'b0;
    for (j = 0; j < 16; j = j + 1) begin
      mem[8'hE0 + j[7:0]] = 8'h80 + j[7:0];
      mem[8'h10 + j[7:0]] = 8'h00;
    end

    cfg_write(3'd0, 32'h0000_00E0); // ch0 src
    cfg_write(3'd1, 32'h0000_0010); // ch0 dst
    cfg_write(3'd2, 32'h0000_0010); // ch0 len = 16
    cfg_write(3'd3, 32'h0000_0007); // ch0 start + inc both

    wait_done(0);
    for (j = 0; j < 16; j = j + 1) begin
      expect_byte(8'h10 + j[7:0], 8'h80 + j[7:0]);
    end
    expect_ctrl_status(0, 1'b0, 1'b0, 1'b1);

    $display("[tb_dma_subsystem] PASS");
    $finish;
  end

endmodule
