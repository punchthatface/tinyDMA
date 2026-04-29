import dma_pkg::*;

module ChipInterface (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       btn_left,
  input  logic       btn_right,
  input  logic       btn_up,
  input  logic       btn_down,
  input  logic       pmod_sd1,
  output logic [7:0] led,
  output logic       pmod_cs0_n,
  output logic       pmod_sd0,
  output logic       pmod_sck,
  output logic       pmod_sd2,
  output logic       pmod_sd3,
  output logic       pmod_cs1_n,
  output logic       pmod_cs2_n
);

  localparam logic [ADDR_W-1:0] TEST_ADDR  = 24'h000010;
  localparam logic [DATA_W-1:0] TEST_DATA0 = 8'hA5;
  localparam logic [DATA_W-1:0] TEST_DATA1 = 8'h3C;

  logic up_pulse;
  logic down_pulse;
  logic left_pulse;
  logic right_pulse;

  logic              req_valid;
  logic              req_rw;
  logic [ADDR_W-1:0] req_addr;
  logic [DATA_W-1:0] req_wdata;
  logic              req_ready;

  logic              rsp_valid;
  logic [DATA_W-1:0] rsp_rdata;
  logic              ctrl_busy;

  logic              op_pending, op_pending_next;
  logic              op_rw, op_rw_next;
  logic [ADDR_W-1:0] op_addr, op_addr_next;
  logic [DATA_W-1:0] op_wdata, op_wdata_next;
  logic [DATA_W-1:0] expected_data, expected_data_next;

  logic [DATA_W-1:0] last_data, last_data_next;
  logic              last_read_ok, last_read_ok_next;
  logic              last_read_valid, last_read_valid_next;
  logic              req_seen, req_seen_next;
  logic              read_seen, read_seen_next;
  logic              read_ok_latched, read_ok_latched_next;
  logic [23:0]       heartbeat_count;

  debounce_one_shot #(
    .COUNT_MAX(250_000)
  ) u_db_up (
    .clk(clk),
    .rst_n(rst_n),
    .button_in(btn_up),
    .pressed_pulse(up_pulse)
  );

  debounce_one_shot #(
    .COUNT_MAX(250_000)
  ) u_db_down (
    .clk(clk),
    .rst_n(rst_n),
    .button_in(btn_down),
    .pressed_pulse(down_pulse)
  );

  debounce_one_shot #(
    .COUNT_MAX(250_000)
  ) u_db_left (
    .clk(clk),
    .rst_n(rst_n),
    .button_in(btn_left),
    .pressed_pulse(left_pulse)
  );

  debounce_one_shot #(
    .COUNT_MAX(250_000)
  ) u_db_right (
    .clk(clk),
    .rst_n(rst_n),
    .button_in(btn_right),
    .pressed_pulse(right_pulse)
  );

  spi_psram_ctrl #(
    .RESET_CYCLES(16'd3750),
    .RESET_RECOVERY_CYCLES(16'd4)
  ) u_psram_ctrl (
    .clk      (clk),
    .rst_n    (rst_n),
    .req_valid(req_valid),
    .req_rw   (req_rw),
    .req_addr (req_addr),
    .req_wdata(req_wdata),
    .req_ready(req_ready),
    .rsp_valid(rsp_valid),
    .rsp_rdata(rsp_rdata),
    .busy     (ctrl_busy),
    .spi_clk  (pmod_sck),
    .spi_cs_n (pmod_cs1_n),
    .spi_mosi (pmod_sd0),
    .spi_miso (pmod_sd1)
  );

  assign req_valid = op_pending;
  assign req_rw    = op_rw;
  assign req_addr  = op_addr;
  assign req_wdata = op_wdata;

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      op_pending       <= 1'b0;
      op_rw            <= 1'b0;
      op_addr          <= '0;
      op_wdata         <= '0;
      expected_data    <= TEST_DATA0;
      last_data        <= 8'h00;
      last_read_ok     <= 1'b0;
      last_read_valid  <= 1'b0;
      req_seen         <= 1'b0;
      read_seen        <= 1'b0;
      read_ok_latched  <= 1'b0;
      heartbeat_count  <= '0;
    end else begin
      op_pending       <= op_pending_next;
      op_rw            <= op_rw_next;
      op_addr          <= op_addr_next;
      op_wdata         <= op_wdata_next;
      expected_data    <= expected_data_next;
      last_data        <= last_data_next;
      last_read_ok     <= last_read_ok_next;
      last_read_valid  <= last_read_valid_next;
      req_seen         <= req_seen_next;
      read_seen        <= read_seen_next;
      read_ok_latched  <= read_ok_latched_next;
      heartbeat_count  <= heartbeat_count + 1'b1;
    end
  end

  always_comb begin
    op_pending_next      = op_pending;
    op_rw_next           = op_rw;
    op_addr_next         = op_addr;
    op_wdata_next        = op_wdata;
    expected_data_next   = expected_data;
    last_data_next       = last_data;
    last_read_ok_next    = last_read_ok;
    last_read_valid_next = last_read_valid;
    req_seen_next        = req_seen;
    read_seen_next       = read_seen;
    read_ok_latched_next = read_ok_latched;

    if (!op_pending && req_ready) begin
      if (up_pulse) begin
        op_pending_next      = 1'b1;
        op_rw_next           = 1'b1;
        op_addr_next         = TEST_ADDR;
        op_wdata_next        = TEST_DATA0;
        expected_data_next   = TEST_DATA0;
        last_data_next       = TEST_DATA0;
        last_read_valid_next = 1'b0;
        req_seen_next        = 1'b0;
        read_seen_next       = 1'b0;
        read_ok_latched_next = 1'b0;
      end else if (down_pulse) begin
        op_pending_next      = 1'b1;
        op_rw_next           = 1'b1;
        op_addr_next         = TEST_ADDR;
        op_wdata_next        = TEST_DATA1;
        expected_data_next   = TEST_DATA1;
        last_data_next       = TEST_DATA1;
        last_read_valid_next = 1'b0;
        req_seen_next        = 1'b0;
        read_seen_next       = 1'b0;
        read_ok_latched_next = 1'b0;
      end else if (left_pulse || right_pulse) begin
        op_pending_next      = 1'b1;
        op_rw_next           = 1'b0;
        op_addr_next         = TEST_ADDR;
        op_wdata_next        = 8'h00;
        last_read_valid_next = 1'b0;
        req_seen_next        = 1'b0;
        read_seen_next       = 1'b0;
      end
    end

    if (op_pending && req_ready) begin
      op_pending_next = 1'b0;
      req_seen_next   = 1'b1;
    end

    if (rsp_valid) begin
      last_data_next       = rsp_rdata;
      last_read_ok_next    = (rsp_rdata == expected_data);
      last_read_valid_next = 1'b1;
      read_seen_next       = 1'b1;
      read_ok_latched_next = (rsp_rdata == expected_data);
    end
  end

  always_comb begin
    pmod_cs0_n = 1'b1;
    pmod_cs2_n = 1'b1;
    pmod_sd2   = 1'b1;
    pmod_sd3   = 1'b1;

    led[0] = last_data[0];
    led[1] = last_data[1];
    led[2] = last_data[2];
    led[3] = last_data[3];
    led[4] = read_seen;
    led[5] = read_ok_latched;
    led[6] = ctrl_busy;
    led[7] = heartbeat_count[23];
  end

endmodule


module debounce_one_shot #(
  parameter int unsigned COUNT_MAX = 250_000
) (
  input  logic clk,
  input  logic rst_n,
  input  logic button_in,
  output logic pressed_pulse
);

  localparam int unsigned COUNT_W = $clog2(COUNT_MAX + 1);

  logic sync_ff0, sync_ff1;
  logic stable_state, stable_state_next;
  logic [COUNT_W-1:0] count, count_next;
  logic pressed_pulse_next;

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      sync_ff0      <= 1'b0;
      sync_ff1      <= 1'b0;
      stable_state  <= 1'b0;
      count         <= '0;
      pressed_pulse <= 1'b0;
    end else begin
      sync_ff0      <= button_in;
      sync_ff1      <= sync_ff0;
      stable_state  <= stable_state_next;
      count         <= count_next;
      pressed_pulse <= pressed_pulse_next;
    end
  end

  always_comb begin
    stable_state_next  = stable_state;
    count_next         = count;
    pressed_pulse_next = 1'b0;

    if (sync_ff1 == stable_state) begin
      count_next = '0;
    end else begin
      if (count == COUNT_MAX[COUNT_W-1:0]) begin
        stable_state_next = sync_ff1;
        count_next        = '0;
        if (sync_ff1) begin
          pressed_pulse_next = 1'b1;
        end
      end else begin
        count_next = count + 1'b1;
      end
    end
  end

endmodule
