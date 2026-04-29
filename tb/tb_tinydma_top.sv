import dma_pkg::*;

module tb_tinydma_top;

  localparam int REGS_PER_CH = 4;
  localparam int TIMEOUT_CYCLES = 5000;

  logic clk;
  logic rst_n;

  logic                              cfg_we;
  logic                              cfg_re;
  logic [$clog2(N_CH*REGS_PER_CH)-1:0] cfg_addr;
  logic [31:0]                       cfg_wdata;
  logic [31:0]                       cfg_rdata;

  logic dma_busy;
  logic [N_CH-1:0] chan_active_o;
  logic [N_CH-1:0] chan_done_o;
  logic spi_clk;
  logic spi_cs_n;
  logic spi_mosi;
  logic spi_miso;

  tinydma_top #(
    .PSRAM_RESET_CYCLES(32),
    .PSRAM_RESET_RECOVERY_CYCLES(4)
  ) dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .cfg_we   (cfg_we),
    .cfg_re   (cfg_re),
    .cfg_addr (cfg_addr),
    .cfg_wdata(cfg_wdata),
    .cfg_rdata(cfg_rdata),
    .dma_busy (dma_busy),
    .chan_active_o(chan_active_o),
    .chan_done_o(chan_done_o),
    .spi_clk  (spi_clk),
    .spi_cs_n (spi_cs_n),
    .spi_mosi (spi_mosi),
    .spi_miso (spi_miso)
  );

  psram_model mem (
    .cs_n (spi_cs_n),
    .sclk (spi_clk),
    .mosi (spi_mosi),
    .miso (spi_miso)
  );

  always #5 clk = ~clk;

  task automatic cfg_write(
    input logic [$clog2(N_CH*REGS_PER_CH)-1:0] addr,
    input logic [31:0] wdata
  );
    begin
      @(posedge clk);
      cfg_addr  <= addr;
      cfg_wdata <= wdata;
      cfg_we    <= 1'b1;
      cfg_re    <= 1'b0;

      @(posedge clk);
      cfg_we    <= 1'b0;
      cfg_addr  <= '0;
      cfg_wdata <= '0;
    end
  endtask

  task automatic cfg_read(
    input  logic [$clog2(N_CH*REGS_PER_CH)-1:0] addr,
    output logic [31:0] rdata
  );
    begin
      @(posedge clk);
      cfg_addr <= addr;
      cfg_re   <= 1'b1;
      cfg_we   <= 1'b0;

      @(posedge clk);
      rdata = cfg_rdata;
      cfg_re   <= 1'b0;
      cfg_addr <= '0;
    end
  endtask

  task automatic wait_channel_done(input int channel);
    logic [31:0] ctrl_word;
    integer cycles;
    logic found_done;
    begin
      cycles = 0;
      ctrl_word = '0;
      found_done = 1'b0;

      while ((cycles < TIMEOUT_CYCLES) && !found_done) begin
        cfg_read(channel ? 3'd7 : 3'd3, ctrl_word);
        if (ctrl_word[9]) begin
          found_done = 1'b1;
        end
        cycles = cycles + 1;
      end

      if (!found_done) begin
        $display("FAIL: channel %0d did not complete", channel);
        $finish;
      end
    end
  endtask

  task automatic expect_mem_byte(
    input logic [7:0] addr,
    input logic [7:0] expected
  );
    begin
      if (mem.mem[addr] !== expected) begin
        $display("FAIL: PSRAM[0x%02h] expected 0x%02h got 0x%02h", addr, expected, mem.mem[addr]);
        $finish;
      end
      $display("    PSRAM[0x%02h] = 0x%02h", addr, mem.mem[addr]);
    end
  endtask

  task automatic expect_ctrl_bits(
    input logic [$clog2(N_CH*REGS_PER_CH)-1:0] addr,
    input logic expected_start,
    input logic expected_active,
    input logic expected_done
  );
    logic [31:0] ctrl_word;
    begin
      cfg_read(addr, ctrl_word);
      if (ctrl_word[0] !== expected_start ||
          ctrl_word[8] !== expected_active ||
          ctrl_word[9] !== expected_done) begin
        $display("FAIL: ctrl @%0d unexpected: 0x%08h", addr, ctrl_word);
        $finish;
      end
      $display("    ctrl[%0d] = 0x%08h (start=%0b active=%0b done=%0b)",
               addr, ctrl_word, ctrl_word[0], ctrl_word[8], ctrl_word[9]);
    end
  endtask

  logic [31:0] ctrl0;
  logic [31:0] ctrl1;

  initial begin
    clk      = 1'b0;
    rst_n    = 1'b0;
    cfg_we   = 1'b0;
    cfg_re   = 1'b0;
    cfg_addr = '0;
    cfg_wdata = '0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    $display("");
    $display("[tb_tinydma_top] Test 1: wait for PSRAM init/reset through top-level SPI pins");

    // Wait for PSRAM init/reset sequence to finish.
    repeat (100) @(posedge clk);
    $display("  observed reset commands: prev=0x%02h last=0x%02h", mem.prev_cmd, mem.last_cmd);
    $display("  command counts after init: reset_enable=%0d reset=%0d",
             mem.reset_enable_count, mem.reset_count);

    $display("[tb_tinydma_top] Test 2: channel 0 full top-level 4-byte copy");
    $display("  src=0x10 dst=0x20 len=4 ctrl=start/inc_src/inc_dst");

    // Preload source bytes directly into the PSRAM model.
    mem.mem[8'h10] = 8'h12;
    mem.mem[8'h11] = 8'h34;
    mem.mem[8'h12] = 8'h56;
    mem.mem[8'h13] = 8'h78;

    // Program channel 0 and start a 4-byte copy.
    cfg_write(3'd0, 32'h0000_0010);
    cfg_write(3'd1, 32'h0000_0020);
    cfg_write(3'd2, 32'h0000_0004);
    cfg_write(3'd3, 32'h0000_0007);

    wait_channel_done(0);

    expect_mem_byte(8'h20, 8'h12);
    expect_mem_byte(8'h21, 8'h34);
    expect_mem_byte(8'h22, 8'h56);
    expect_mem_byte(8'h23, 8'h78);

    cfg_read(3'd3, ctrl0);
    if (ctrl0[8] !== 1'b0 || ctrl0[9] !== 1'b1 || ctrl0[0] !== 1'b0) begin
      $display("FAIL: channel 0 ctrl unexpected: 0x%08h", ctrl0);
      $finish;
    end
    $display("    ch0 ctrl = 0x%08h (start=%0b active=%0b done=%0b)",
             ctrl0, ctrl0[0], ctrl0[8], ctrl0[9]);

    $display("[tb_tinydma_top] Test 3: channel 1 fixed-source fill");
    $display("  src=0x30 dst=0x40 len=3 ctrl=start/inc_dst");

    // Program channel 1 for a fixed-source fill.
    mem.mem[8'h30] = 8'hA5;
    cfg_write(3'd4, 32'h0000_0030);
    cfg_write(3'd5, 32'h0000_0040);
    cfg_write(3'd6, 32'h0000_0003);
    cfg_write(3'd7, 32'h0000_0005);

    wait_channel_done(1);

    expect_mem_byte(8'h40, 8'hA5);
    expect_mem_byte(8'h41, 8'hA5);
    expect_mem_byte(8'h42, 8'hA5);

    cfg_read(3'd7, ctrl1);
    if (ctrl1[8] !== 1'b0 || ctrl1[9] !== 1'b1 || ctrl1[0] !== 1'b0) begin
      $display("FAIL: channel 1 ctrl unexpected: 0x%08h", ctrl1);
      $finish;
    end
    $display("    ch1 ctrl = 0x%08h (start=%0b active=%0b done=%0b)",
             ctrl1, ctrl1[0], ctrl1[8], ctrl1[9]);

    $display("[tb_tinydma_top] Test 4: zero-length transfer");
    $display("  src=0x51 dst=0x50 len=0, destination should stay 0xE7");

    // Zero-length should set done without touching destination.
    mem.mem[8'h50] = 8'hE7;
    cfg_write(3'd4, 32'h0000_0051);
    cfg_write(3'd5, 32'h0000_0050);
    cfg_write(3'd6, 32'h0000_0000);
    cfg_write(3'd7, 32'h0000_0007);

    wait_channel_done(1);
    expect_mem_byte(8'h50, 8'hE7);
    expect_ctrl_bits(3'd7, 1'b0, 1'b0, 1'b1);

    $display("[tb_tinydma_top] PASS");
    $finish;
  end

endmodule
