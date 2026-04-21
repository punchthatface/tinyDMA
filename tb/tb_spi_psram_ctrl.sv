import dma_pkg::*;

module psram_model (
  input  logic cs_n,
  input  logic sclk,
  input  logic mosi,
  output logic miso
);

  typedef enum logic [2:0] {
    PM_IDLE,
    PM_CMD,
    PM_ADDR,
    PM_WRITE_DATA,
    PM_READ_DATA
  } pm_state_t;

  pm_state_t state;

  logic [7:0] mem [0:255];

  logic [7:0]  cmd_shift_reg;
  logic [23:0] addr_shift_reg;
  logic [7:0]  data_shift_reg;
  logic [5:0]  bit_count;

  logic reset_enable_seen;

  logic [7:0] last_cmd;
  logic [7:0] prev_cmd;
  logic [23:0] last_addr;
  int reset_enable_count;
  int reset_count;
  int write_count;
  int read_count;
  int cs_rise_count;

  initial begin
    integer i;
    for (i = 0; i < 256; i = i + 1) begin
      mem[i] = 8'h00;
    end

    state             = PM_IDLE;
    cmd_shift_reg     = '0;
    addr_shift_reg    = '0;
    data_shift_reg    = '0;
    bit_count         = '0;
    miso              = 1'b0;
    reset_enable_seen = 1'b0;
    last_cmd          = '0;
    prev_cmd          = '0;
    last_addr         = '0;
    reset_enable_count = 0;
    reset_count        = 0;
    write_count        = 0;
    read_count         = 0;
    cs_rise_count      = 0;
  end

  always @(posedge cs_n or posedge sclk or negedge sclk) begin
    if (cs_n) begin
      // Transaction end / standby
      cs_rise_count   <= cs_rise_count + 1;
      state          <= PM_IDLE;
      cmd_shift_reg  <= '0;
      addr_shift_reg <= '0;
      data_shift_reg <= '0;
      bit_count      <= '0;
      miso           <= 1'b0;
    end else if (sclk) begin
      // Input latching on rising edge. The first rising edge after CS# goes low
      // also starts the command phase.
      case (state)
        PM_IDLE,
        PM_CMD: begin
          cmd_shift_reg <= {cmd_shift_reg[6:0], mosi};
          bit_count     <= bit_count + 1'b1;

          if (bit_count == 6'd7) begin
            bit_count <= '0;

            case ({cmd_shift_reg[6:0], mosi})
              8'h66: begin
                prev_cmd           <= last_cmd;
                last_cmd           <= 8'h66;
                reset_enable_count <= reset_enable_count + 1;
                reset_enable_seen <= 1'b1;
                state             <= PM_IDLE;
              end

              8'h99: begin
                prev_cmd    <= last_cmd;
                last_cmd    <= 8'h99;
                reset_count <= reset_count + 1;
                reset_enable_seen <= 1'b0;
                state             <= PM_IDLE;
              end

              8'h02,
              8'h03: begin
                prev_cmd <= last_cmd;
                last_cmd <= {cmd_shift_reg[6:0], mosi};
                if (reset_enable_seen) begin
                  reset_enable_seen <= 1'b0;
                end
                state <= PM_ADDR;
              end

              default: begin
                reset_enable_seen <= 1'b0;
                state             <= PM_IDLE;
              end
            endcase
          end
        end

        PM_ADDR: begin
          addr_shift_reg <= {addr_shift_reg[22:0], mosi};
          bit_count      <= bit_count + 1'b1;

          if (bit_count == 6'd23) begin
            bit_count <= '0;
            last_addr <= {addr_shift_reg[22:0], mosi};

            if (cmd_shift_reg == 8'h02) begin
              write_count <= write_count + 1;
              state <= PM_WRITE_DATA;
            end else begin
              read_count <= read_count + 1;
              data_shift_reg <= mem[{addr_shift_reg[6:0], mosi}];
              state          <= PM_READ_DATA;
            end
          end
        end

        PM_WRITE_DATA: begin
          data_shift_reg <= {data_shift_reg[6:0], mosi};
          bit_count      <= bit_count + 1'b1;

          if (bit_count == 6'd7) begin
            mem[addr_shift_reg[7:0]] <= {data_shift_reg[6:0], mosi};
            bit_count                <= '0;
            state                    <= PM_IDLE;
          end
        end

        default: begin
        end
      endcase
    end else begin
      // Output timing on falling edge: data becomes available after the falling edge.
      if (state == PM_READ_DATA) begin
        miso           <= data_shift_reg[7];
        data_shift_reg <= {data_shift_reg[6:0], 1'b0};
        bit_count      <= bit_count + 1'b1;

        if (bit_count == 6'd7) begin
          bit_count <= '0;
          state     <= PM_IDLE;
        end
      end else begin
        miso <= 1'b0;
      end
    end
  end

endmodule


module tb_spi_psram_ctrl;

  localparam int WAIT_TIMEOUT_CYCLES = 500;

  logic              clk;
  logic              rst_n;

  logic              req_valid;
  logic              req_rw;
  logic [ADDR_W-1:0] req_addr;
  logic [DATA_W-1:0] req_wdata;
  logic              req_ready;

  logic              rsp_valid;
  logic [DATA_W-1:0] rsp_rdata;
  logic              busy;

  logic              spi_clk;
  logic              spi_cs_n;
  logic              spi_mosi;
  logic              spi_miso;

  spi_psram_ctrl #(
    .RESET_CYCLES(8),
    .RESET_RECOVERY_CYCLES(6)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .req_valid(req_valid),
    .req_rw(req_rw),
    .req_addr(req_addr),
    .req_wdata(req_wdata),
    .req_ready(req_ready),
    .rsp_valid(rsp_valid),
    .rsp_rdata(rsp_rdata),
    .busy(busy),
    .spi_clk(spi_clk),
    .spi_cs_n(spi_cs_n),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso)
  );

  psram_model mem (
    .cs_n(spi_cs_n),
    .sclk(spi_clk),
    .mosi(spi_mosi),
    .miso(spi_miso)
  );

  always #5 clk = ~clk;

  task automatic fail_test(input string msg);
    begin
      $display("FAIL: %s", msg);
      $finish;
    end
  endtask

  task automatic wait_for_req_ready;
    int cycles;
    begin
      cycles = 0;
      while (req_ready !== 1'b1) begin
        @(posedge clk);
        cycles = cycles + 1;
        if (cycles > WAIT_TIMEOUT_CYCLES) begin
          fail_test("Timed out waiting for req_ready");
        end
      end
    end
  endtask

  task automatic wait_for_busy_value(input logic expected, input string what);
    int cycles;
    begin
      cycles = 0;
      while (busy !== expected) begin
        @(posedge clk);
        cycles = cycles + 1;
        if (cycles > WAIT_TIMEOUT_CYCLES) begin
          fail_test(what);
        end
      end
    end
  endtask

  task automatic wait_for_rsp_valid;
    int cycles;
    begin
      cycles = 0;
      while (rsp_valid !== 1'b1) begin
        @(posedge clk);
        cycles = cycles + 1;
        if (cycles > WAIT_TIMEOUT_CYCLES) begin
          fail_test("Timed out waiting for rsp_valid");
        end
      end
    end
  endtask

  task automatic issue_write(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] data
  );
    begin
      @(posedge clk);
      wait_for_req_ready();
      req_addr  <= addr;
      req_wdata <= data;
      req_rw    <= 1'b1;
      req_valid <= 1'b1;

      @(posedge clk);
      req_valid <= 1'b0;

      wait_for_busy_value(1'b1, "Timed out waiting for busy to assert during write");
      wait_for_busy_value(1'b0, "Timed out waiting for busy to deassert after write");
    end
  endtask

  task automatic issue_read(
    input  logic [ADDR_W-1:0] addr,
    output logic [DATA_W-1:0] data
  );
    begin
      @(posedge clk);
      wait_for_req_ready();
      req_addr  <= addr;
      req_wdata <= '0;
      req_rw    <= 1'b0;
      req_valid <= 1'b1;

      @(posedge clk);
      req_valid <= 1'b0;

      wait_for_busy_value(1'b1, "Timed out waiting for busy to assert during read");
      wait_for_rsp_valid();
      data = rsp_rdata;

      @(posedge clk);
      wait_for_busy_value(1'b0, "Timed out waiting for busy to deassert after read");
    end
  endtask

  logic [7:0] readback;
  logic [7:0] readback2;
  logic [7:0] readback3;

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    req_valid = 1'b0;
    req_rw = 1'b0;
    req_addr = '0;
    req_wdata = '0;
    readback = '0;
    readback2 = '0;
    readback3 = '0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    wait_for_req_ready();

    if (mem.reset_enable_count != 1 || mem.reset_count != 1) begin
      fail_test("Did not observe exactly one reset-enable and one reset command before idle");
    end

    if (mem.prev_cmd != 8'h66 || mem.last_cmd != 8'h99) begin
      fail_test("Reset sequence was not 0x66 immediately followed by 0x99");
    end

    if (spi_cs_n !== 1'b1 || spi_clk !== 1'b0) begin
      fail_test("SPI pins were not in idle state after initialization");
    end

    issue_write(24'h000010, 8'hAB);
    issue_read (24'h000010, readback);
    issue_write(24'h00007F, 8'h3C);
    issue_read (24'h00007F, readback2);
    issue_write(24'h800055, 8'h5A);
    issue_read (24'h800055, readback3);

    $display("Readback[0x000010] = 0x%02h", readback);
    $display("Readback[0x00007F] = 0x%02h", readback2);
    $display("Readback[0x800055] = 0x%02h", readback3);

    if (readback != 8'hAB) begin
      fail_test("Incorrect readback at address 0x000010");
    end

    if (readback2 != 8'h3C) begin
      fail_test("Incorrect readback at address 0x00007F");
    end

    if (readback3 != 8'h5A) begin
      fail_test("Incorrect readback when address[23] was high");
    end

    if (mem.last_addr[23] != 1'b0) begin
      fail_test("Controller did not force the transmitted address MSB low");
    end

    if (mem.mem[8'h55] != 8'h5A) begin
      fail_test("PSRAM model did not receive masked address 0x000055 on the wire");
    end

    if (mem.write_count != 3 || mem.read_count != 3) begin
      fail_test("Unexpected number of memory read/write commands observed");
    end

    if (spi_cs_n !== 1'b1 || spi_clk !== 1'b0) begin
      fail_test("SPI pins did not return to idle state after transactions");
    end

    $display("PASS");

    repeat (10) @(posedge clk);
    $finish;
  end

endmodule
