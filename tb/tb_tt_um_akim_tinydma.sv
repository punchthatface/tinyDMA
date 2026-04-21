import dma_pkg::*;

module tb_tt_um_akim_tinydma;

  logic clk;
  logic rst_n;
  logic ena;
  logic [7:0] ui_in;
  logic [7:0] uio_in_drv;
  wire  [7:0] uio_in;
  logic [7:0] uo_out;
  logic [7:0] uio_out;
  logic [7:0] uio_oe;

  logic spi_miso;

  tt_um_akim_tinydma #(
    .PSRAM_RESET_CYCLES(32),
    .PSRAM_RESET_RECOVERY_CYCLES(4)
  ) dut (
    .ui_in  (ui_in),
    .uo_out (uo_out),
    .uio_in (uio_in),
    .uio_out(uio_out),
    .uio_oe (uio_oe),
    .ena    (ena),
    .clk    (clk),
    .rst_n  (rst_n)
  );

  psram_model mem (
    .cs_n (uio_out[1]),
    .sclk (uio_out[0]),
    .mosi (uio_out[2]),
    .miso (spi_miso)
  );

  assign uio_in = {uio_in_drv[7:3], spi_miso, uio_in_drv[1:0]};

  always #5 clk = ~clk;

  task automatic pulse_cfg(input logic [7:0] data);
    begin
      @(posedge clk);
      ui_in     <= data;
      uio_in_drv[0] <= 1'b1;
      @(posedge clk);
      uio_in_drv[0] <= 1'b0;
      ui_in     <= 8'h00;
    end
  endtask

  task automatic write_cfg_byte(
    input logic channel,
    input logic [1:0] field,
    input logic [1:0] byte_idx,
    input logic [7:0] data
  );
    logic [7:0] cmd;
    begin
      cmd = 8'h80 | {channel, field, byte_idx, 2'b00};
      pulse_cfg(cmd);
      pulse_cfg(data);
    end
  endtask

  task automatic pulse_start;
    begin
      @(posedge clk);
      uio_in_drv[1] <= 1'b1;
      @(posedge clk);
      uio_in_drv[1] <= 1'b0;
    end
  endtask

  task automatic wait_done_pulse;
    integer cycles;
    begin
      cycles = 0;
      while ((uo_out[1] !== 1'b1) && (cycles < 5000)) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      if (cycles == 5000) begin
        $display("FAIL: timeout waiting for done pulse");
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
    end
  endtask

  initial begin
    clk    = 1'b0;
    rst_n  = 1'b0;
    ena    = 1'b1;
    ui_in  = 8'h00;
    uio_in_drv = 8'h00;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    repeat (100) @(posedge clk);

    mem.mem[8'h10] = 8'hCA;
    mem.mem[8'h11] = 8'hFE;
    mem.mem[8'h12] = 8'hBA;
    mem.mem[8'h13] = 8'hBE;

    write_cfg_byte(1'b0, 2'd0, 2'd0, 8'h10);
    write_cfg_byte(1'b0, 2'd0, 2'd1, 8'h00);
    write_cfg_byte(1'b0, 2'd0, 2'd2, 8'h00);

    write_cfg_byte(1'b0, 2'd1, 2'd0, 8'h20);
    write_cfg_byte(1'b0, 2'd1, 2'd1, 8'h00);
    write_cfg_byte(1'b0, 2'd1, 2'd2, 8'h00);

    write_cfg_byte(1'b0, 2'd2, 2'd0, 8'h04);
    write_cfg_byte(1'b0, 2'd2, 2'd1, 8'h00);

    // ctrl byte: bit0 arm_on_start, bit1 inc_src, bit2 inc_dst
    write_cfg_byte(1'b0, 2'd3, 2'd0, 8'h07);

    pulse_start();
    wait_done_pulse();

    expect_mem_byte(8'h20, 8'hCA);
    expect_mem_byte(8'h21, 8'hFE);
    expect_mem_byte(8'h22, 8'hBA);
    expect_mem_byte(8'h23, 8'hBE);

    if (uo_out[7] !== 1'b0) begin
      $display("FAIL: wrapper error flag asserted");
      $finish;
    end

    $display("PASS");
    $finish;
  end

endmodule
