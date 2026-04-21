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

  initial begin
    integer i;
    for (i = 0; i < 256; i = i + 1) begin
      mem[i] = 8'h00;
    end

    state = PM_IDLE;
    cmd_shift_reg = '0;
    addr_shift_reg = '0;
    data_shift_reg = '0;
    bit_count = '0;
    miso = 1'b0;
    reset_enable_seen = 1'b0;
  end

  always_ff @(posedge cs_n) begin
    state <= PM_CMD;
    cmd_shift_reg <= '0;
    addr_shift_reg <= '0;
    data_shift_reg <= '0;
    bit_count <= '0;
    miso <= 1'b0;
  end

  always_ff @(posedge sclk) begin
    if (!cs_n) begin
      case (state)
        PM_CMD: begin
          cmd_shift_reg <= {cmd_shift_reg[6:0], mosi};
          bit_count <= bit_count + 1'b1;

          if (bit_count == 6'd7) begin
            bit_count <= '0;

            case ({cmd_shift_reg[6:0], mosi})
              8'h66: begin
                reset_enable_seen <= 1'b1;
                state <= PM_IDLE;
              end

              8'h99: begin
                if (reset_enable_seen) begin
                  reset_enable_seen <= 1'b0;
                end
                state <= PM_IDLE;
              end

              8'h02,
              8'h03: begin
                state <= PM_ADDR;
              end

              default: begin
                state <= PM_IDLE;
              end
            endcase
          end
        end

        PM_ADDR: begin
          addr_shift_reg <= {addr_shift_reg[22:0], mosi};
          bit_count <= bit_count + 1'b1;

          if (bit_count == 6'd23) begin
            bit_count <= '0;

            if (cmd_shift_reg == 8'h02) begin
              state <= PM_WRITE_DATA;
            end else begin
              data_shift_reg <= mem[{addr_shift_reg[6:0], mosi}];
              state <= PM_READ_DATA;
            end
          end
        end

        PM_WRITE_DATA: begin
          data_shift_reg <= {data_shift_reg[6:0], mosi};
          bit_count <= bit_count + 1'b1;

          if (bit_count == 6'd7) begin
            mem[addr_shift_reg[7:0]] <= {data_shift_reg[6:0], mosi};
            bit_count <= '0;
            state <= PM_IDLE;
          end
        end

        default: begin
        end
      endcase
    end
  end

  always_ff @(negedge sclk) begin
    if (!cs_n && state == PM_READ_DATA) begin
      miso <= data_shift_reg[7];
      data_shift_reg <= {data_shift_reg[6:0], 1'b0};
      bit_count <= bit_count + 1'b1;

      if (bit_count == 6'd7) begin
        bit_count <= '0;
        state <= PM_IDLE;
      end
    end else begin
      miso <= 1'b0;
    end
  end

endmodule


module tb_spi_psram_ctrl;

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
    .RESET_CYCLES(8)
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

  task automatic issue_write(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] data
  );
    begin
      @(posedge clk);
      wait (req_ready == 1'b1);
      req_addr  <= addr;
      req_wdata <= data;
      req_rw    <= 1'b1;
      req_valid <= 1'b1;

      @(posedge clk);
      req_valid <= 1'b0;

      wait (busy == 1'b0);
    end
  endtask

  task automatic issue_read(
    input  logic [ADDR_W-1:0] addr,
    output logic [DATA_W-1:0] data
  );
    begin
      @(posedge clk);
      wait (req_ready == 1'b1);
      req_addr  <= addr;
      req_wdata <= '0;
      req_rw    <= 1'b0;
      req_valid <= 1'b1;

      @(posedge clk);
      req_valid <= 1'b0;

      wait (rsp_valid == 1'b1);
      data = rsp_rdata;

      @(posedge clk);
      wait (busy == 1'b0);
    end
  endtask

  logic [7:0] readback;

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    req_valid = 1'b0;
    req_rw = 1'b0;
    req_addr = '0;
    req_wdata = '0;
    readback = '0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    wait (req_ready == 1'b1);

    issue_write(24'h000010, 8'hAB);
    issue_read(24'h000010, readback);

    $display("Readback = 0x%02h", readback);

    if (readback == 8'hAB) begin
      $display("PASS");
    end else begin
      $display("FAIL");
    end

    repeat (10) @(posedge clk);
    $finish;
  end

endmodule