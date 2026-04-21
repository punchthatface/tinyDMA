import dma_pkg::*;

module spi_psram_ctrl #(
  parameter int RESET_CYCLES = 20000
)(
  input  logic              clk,
  input  logic              rst_n,

  // Request interface from DMA / top-level logic
  input  logic              req_valid,
  input  logic              req_rw,       // 0 = read, 1 = write
  input  logic [ADDR_W-1:0] req_addr,
  input  logic [DATA_W-1:0] req_wdata,
  output logic              req_ready,

  // Response interface back to DMA / top-level logic
  output logic              rsp_valid,
  output logic [DATA_W-1:0] rsp_rdata,
  output logic              busy,

  // External SPI pins to PSRAM
  output logic              spi_clk,
  output logic              spi_cs_n,
  output logic              spi_mosi,
  input  logic              spi_miso
);

  typedef enum logic [3:0] {
    ST_POWER_UP_WAIT,
    ST_LOAD_RESET_ENABLE,
    ST_SHIFT_RESET_ENABLE,
    ST_LOAD_RESET,
    ST_SHIFT_RESET,
    ST_IDLE,
    ST_LOAD_COMMAND,
    ST_SHIFT_COMMAND,
    ST_LOAD_ADDRESS,
    ST_SHIFT_ADDRESS,
    ST_LOAD_WRITE_DATA,
    ST_SHIFT_WRITE_DATA,
    ST_SHIFT_READ_DATA,
    ST_FINISH
  } state_t;

  state_t state, state_next;

  // Wait counter used during initial power-up delay
  logic [15:0] reset_wait_count, reset_wait_count_next;

  // Bit counter for current SPI phase
  logic [5:0] bit_count, bit_count_next;

  // Shift register for command / reset / write-data bytes
  logic [7:0] byte_shift_reg, byte_shift_reg_next;

  // Shift register for outgoing address bits
  logic [ADDR_W-1:0] addr_shift_reg, addr_shift_reg_next;

  // Shift register for incoming read data from MISO
  logic [DATA_W-1:0] rx_shift_reg, rx_shift_reg_next;

  // Latched request fields for current transaction
  logic [ADDR_W-1:0] request_addr_reg, request_addr_reg_next;
  logic [DATA_W-1:0] request_wdata_reg, request_wdata_reg_next;
  logic              request_rw_reg, request_rw_reg_next;

  // Registered SPI outputs
  logic spi_clk_reg, spi_clk_reg_next;
  logic spi_cs_n_reg, spi_cs_n_reg_next;
  logic spi_mosi_reg, spi_mosi_reg_next;

  // Registered status / handshake outputs
  logic              req_ready_next;
  logic              rsp_valid_next;
  logic [DATA_W-1:0] rsp_rdata_next;
  logic              busy_next;

  assign spi_clk  = spi_clk_reg;
  assign spi_cs_n = spi_cs_n_reg;
  assign spi_mosi = spi_mosi_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_POWER_UP_WAIT;

      reset_wait_count <= '0;
      bit_count <= '0;
      byte_shift_reg <= '0;
      addr_shift_reg <= '0;
      rx_shift_reg <= '0;

      request_addr_reg <= '0;
      request_wdata_reg <= '0;
      request_rw_reg <= 1'b0;

      spi_clk_reg <= 1'b0;
      spi_cs_n_reg <= 1'b1;
      spi_mosi_reg <= 1'b0;

      req_ready <= 1'b0;
      rsp_valid <= 1'b0;
      rsp_rdata <= '0;
      busy <= 1'b1;
    end else begin
      state <= state_next;

      reset_wait_count <= reset_wait_count_next;
      bit_count <= bit_count_next;
      byte_shift_reg <= byte_shift_reg_next;
      addr_shift_reg <= addr_shift_reg_next;
      rx_shift_reg <= rx_shift_reg_next;

      request_addr_reg <= request_addr_reg_next;
      request_wdata_reg <= request_wdata_reg_next;
      request_rw_reg <= request_rw_reg_next;

      spi_clk_reg <= spi_clk_reg_next;
      spi_cs_n_reg <= spi_cs_n_reg_next;
      spi_mosi_reg <= spi_mosi_reg_next;

      req_ready <= req_ready_next;
      rsp_valid <= rsp_valid_next;
      rsp_rdata <= rsp_rdata_next;
      busy <= busy_next;
    end
  end

  always_comb begin
    state_next = state;

    reset_wait_count_next = reset_wait_count;
    bit_count_next = bit_count;
    byte_shift_reg_next = byte_shift_reg;
    addr_shift_reg_next = addr_shift_reg;
    rx_shift_reg_next = rx_shift_reg;

    request_addr_reg_next = request_addr_reg;
    request_wdata_reg_next = request_wdata_reg;
    request_rw_reg_next = request_rw_reg;

    spi_clk_reg_next = spi_clk_reg;
    spi_cs_n_reg_next = spi_cs_n_reg;
    spi_mosi_reg_next = spi_mosi_reg;

    req_ready_next = 1'b0;
    rsp_valid_next = 1'b0;
    rsp_rdata_next = rsp_rdata;
    busy_next = 1'b1;

    case (state)
      ST_POWER_UP_WAIT: begin
        spi_cs_n_reg_next = 1'b1;
        spi_clk_reg_next = 1'b0;
        spi_mosi_reg_next = 1'b0;

        if (reset_wait_count == RESET_CYCLES - 1) begin
          reset_wait_count_next = '0;
          state_next = ST_LOAD_RESET_ENABLE;
        end else begin
          reset_wait_count_next = reset_wait_count + 1'b1;
        end
      end

      ST_LOAD_RESET_ENABLE: begin
        spi_cs_n_reg_next = 1'b0;
        spi_clk_reg_next = 1'b0;
        byte_shift_reg_next = 8'h66;
        bit_count_next = 6'd8;
        state_next = ST_SHIFT_RESET_ENABLE;
      end

      ST_SHIFT_RESET_ENABLE: begin
        if (spi_clk_reg == 1'b0) begin
          spi_mosi_reg_next = byte_shift_reg[7];
          spi_clk_reg_next = 1'b1;
        end else begin
          spi_clk_reg_next = 1'b0;
          byte_shift_reg_next = {byte_shift_reg[6:0], 1'b0};
          bit_count_next = bit_count - 1'b1;

          if (bit_count == 6'd1) begin
            spi_cs_n_reg_next = 1'b1;
            state_next = ST_LOAD_RESET;
          end
        end
      end

      ST_LOAD_RESET: begin
        spi_cs_n_reg_next = 1'b0;
        spi_clk_reg_next = 1'b0;
        byte_shift_reg_next = 8'h99;
        bit_count_next = 6'd8;
        state_next = ST_SHIFT_RESET;
      end

      ST_SHIFT_RESET: begin
        if (spi_clk_reg == 1'b0) begin
          spi_mosi_reg_next = byte_shift_reg[7];
          spi_clk_reg_next = 1'b1;
        end else begin
          spi_clk_reg_next = 1'b0;
          byte_shift_reg_next = {byte_shift_reg[6:0], 1'b0};
          bit_count_next = bit_count - 1'b1;

          if (bit_count == 6'd1) begin
            spi_cs_n_reg_next = 1'b1;
            state_next = ST_IDLE;
          end
        end
      end

      ST_IDLE: begin
        spi_cs_n_reg_next = 1'b1;
        spi_clk_reg_next = 1'b0;
        spi_mosi_reg_next = 1'b0;
        req_ready_next = 1'b1;
        busy_next = 1'b0;

        if (req_valid) begin
          request_addr_reg_next = req_addr;
          request_wdata_reg_next = req_wdata;
          request_rw_reg_next = req_rw;
          state_next = ST_LOAD_COMMAND;
        end
      end

      ST_LOAD_COMMAND: begin
        spi_cs_n_reg_next = 1'b0;
        spi_clk_reg_next = 1'b0;
        byte_shift_reg_next = request_rw_reg ? SPI_CMD_WRITE : SPI_CMD_READ;
        bit_count_next = 6'd8;
        state_next = ST_SHIFT_COMMAND;
      end

      ST_SHIFT_COMMAND: begin
        if (spi_clk_reg == 1'b0) begin
          spi_mosi_reg_next = byte_shift_reg[7];
          spi_clk_reg_next = 1'b1;
        end else begin
          spi_clk_reg_next = 1'b0;
          byte_shift_reg_next = {byte_shift_reg[6:0], 1'b0};
          bit_count_next = bit_count - 1'b1;

          if (bit_count == 6'd1) begin
            state_next = ST_LOAD_ADDRESS;
          end
        end
      end

      ST_LOAD_ADDRESS: begin
        spi_clk_reg_next = 1'b0;
        addr_shift_reg_next = request_addr_reg;
        bit_count_next = ADDR_W;
        state_next = ST_SHIFT_ADDRESS;
      end

      ST_SHIFT_ADDRESS: begin
        if (spi_clk_reg == 1'b0) begin
          spi_mosi_reg_next = addr_shift_reg[ADDR_W-1];
          spi_clk_reg_next = 1'b1;
        end else begin
          spi_clk_reg_next = 1'b0;
          addr_shift_reg_next = {addr_shift_reg[ADDR_W-2:0], 1'b0};
          bit_count_next = bit_count - 1'b1;

          if (bit_count == 6'd1) begin
            if (request_rw_reg) begin
              state_next = ST_LOAD_WRITE_DATA;
            end else begin
              rx_shift_reg_next = '0;
              bit_count_next = DATA_W;
              state_next = ST_SHIFT_READ_DATA;
            end
          end
        end
      end

      ST_LOAD_WRITE_DATA: begin
        spi_clk_reg_next = 1'b0;
        byte_shift_reg_next = request_wdata_reg;
        bit_count_next = DATA_W;
        state_next = ST_SHIFT_WRITE_DATA;
      end

      ST_SHIFT_WRITE_DATA: begin
        if (spi_clk_reg == 1'b0) begin
          spi_mosi_reg_next = byte_shift_reg[7];
          spi_clk_reg_next = 1'b1;
        end else begin
          spi_clk_reg_next = 1'b0;
          byte_shift_reg_next = {byte_shift_reg[6:0], 1'b0};
          bit_count_next = bit_count - 1'b1;

          if (bit_count == 6'd1) begin
            state_next = ST_FINISH;
          end
        end
      end

      ST_SHIFT_READ_DATA: begin
        if (spi_clk_reg == 1'b0) begin
          spi_clk_reg_next = 1'b1;
        end else begin
          spi_clk_reg_next = 1'b0;
          rx_shift_reg_next = {rx_shift_reg[DATA_W-2:0], spi_miso};
          bit_count_next = bit_count - 1'b1;

          if (bit_count == 6'd1) begin
            state_next = ST_FINISH;
          end
        end
      end

      ST_FINISH: begin
        spi_cs_n_reg_next = 1'b1;
        spi_clk_reg_next = 1'b0;
        spi_mosi_reg_next = 1'b0;

        if (!request_rw_reg) begin
          rsp_valid_next = 1'b1;
          rsp_rdata_next = rx_shift_reg;
        end

        state_next = ST_IDLE;
      end

      default: begin
        state_next = ST_POWER_UP_WAIT;
      end
    endcase
  end

endmodule