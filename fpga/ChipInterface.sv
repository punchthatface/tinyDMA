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

  localparam logic [ADDR_W-1:0] SRC_BASE = 24'h000020;
  localparam logic [ADDR_W-1:0] DST_BASE = 24'h000030;
  localparam logic [LEN_W-1:0]  DMA_LEN  = 16'd4;

  localparam logic [2:0] RAW_IDLE       = 3'd0;
  localparam logic [2:0] RAW_ISSUE      = 3'd1;
  localparam logic [2:0] RAW_WAIT_WRITE = 3'd2;
  localparam logic [2:0] RAW_WAIT_READ  = 3'd3;
  localparam logic [2:0] RAW_ADVANCE    = 3'd4;

  localparam logic [2:0] CFG_IDLE     = 3'd0;
  localparam logic [2:0] CFG_WRITE_0  = 3'd1;
  localparam logic [2:0] CFG_WRITE_1  = 3'd2;
  localparam logic [2:0] CFG_WRITE_2  = 3'd3;
  localparam logic [2:0] CFG_WRITE_3  = 3'd4;
  localparam logic [2:0] CFG_WAIT_DMA = 3'd5;

  logic up_pulse;
  logic down_pulse;
  logic left_pulse;
  logic right_pulse;

  logic                              cfg_we;
  logic [$clog2(N_CH*4)-1:0]         cfg_addr;
  logic [31:0]                       cfg_wdata;
  logic [31:0]                       cfg_rdata_unused;
  logic [N_CH-1:0]                   start_clear;
  logic [N_CH-1:0]                   chan_active;
  logic [N_CH-1:0]                   chan_done;
  logic                              sched_valid;
  logic [$clog2(N_CH)-1:0]           sched_idx;
  logic                              sched_advance;

  logic [ADDR_W-1:0]                 cfg0_src_base, cfg0_dst_base;
  logic [LEN_W-1:0]                  cfg0_len;
  logic                              cfg0_inc_src, cfg0_inc_dst, cfg0_start_en;
  logic [ADDR_W-1:0]                 cfg1_src_base, cfg1_dst_base;
  logic [LEN_W-1:0]                  cfg1_len;
  logic                              cfg1_inc_src, cfg1_inc_dst, cfg1_start_en;

  logic [ADDR_W-1:0]                 chan0_src_cur, chan0_dst_cur;
  logic [LEN_W-1:0]                  chan0_len_rem;
  logic                              chan0_inc_src, chan0_inc_dst, chan0_active, chan0_done;
  logic [ADDR_W-1:0]                 chan1_src_cur, chan1_dst_cur;
  logic [LEN_W-1:0]                  chan1_len_rem;
  logic                              chan1_inc_src, chan1_inc_dst, chan1_active, chan1_done;

  logic                              dma_mem_req_valid, dma_mem_req_rw;
  logic [ADDR_W-1:0]                 dma_mem_req_addr;
  logic [DATA_W-1:0]                 dma_mem_req_wdata;
  logic                              dma_mem_rsp_ready, dma_mem_rsp_valid;
  logic [DATA_W-1:0]                 dma_mem_rsp_rdata;

  logic [2:0]                        raw_state, raw_state_next;
  logic                              raw_is_write, raw_is_write_next;
  logic                              raw_verify_source, raw_verify_source_next;
  logic [2:0]                        raw_index, raw_index_next;
  logic                              raw_write_busy_seen, raw_write_busy_seen_next;
  logic [DATA_W-1:0]                 raw_last_data, raw_last_data_next;

  logic [2:0]                        cfg_state, cfg_state_next;

  logic                              preload_done, preload_done_next;
  logic                              dma_done_seen, dma_done_seen_next;
  logic                              verify_done, verify_done_next;
  logic                              verify_pass, verify_pass_next;
  logic                              verify_source_latched, verify_source_latched_next;

  logic [23:0]                       heartbeat_count;

  logic                              spi_req_valid, spi_req_rw;
  logic [ADDR_W-1:0]                 spi_req_addr;
  logic [DATA_W-1:0]                 spi_req_wdata;
  logic                              spi_req_ready;
  logic                              spi_rsp_valid;
  logic [DATA_W-1:0]                 spi_rsp_rdata;
  logic                              spi_ctrl_busy;

  logic                              raw_selected;
  logic                              raw_req_valid, raw_req_rw;
  logic [ADDR_W-1:0]                 raw_req_addr;
  logic [DATA_W-1:0]                 raw_req_wdata;
  logic                              raw_req_ready;
  logic                              raw_rsp_valid;
  logic [DATA_W-1:0]                 raw_rsp_rdata;

  function automatic logic [DATA_W-1:0] pattern_byte(input logic [1:0] idx);
    case (idx)
      2'd0:    pattern_byte = 8'hA5;
      2'd1:    pattern_byte = 8'h3C;
      2'd2:    pattern_byte = 8'h5A;
      default: pattern_byte = 8'hC3;
    endcase
  endfunction

  function automatic logic [ADDR_W-1:0] raw_addr_for_step(
    input logic        is_write,
    input logic        verify_source,
    input logic [2:0]  step
  );
    if (is_write) begin
      if (step < 3'd4) begin
        raw_addr_for_step = SRC_BASE + step;
      end else begin
        raw_addr_for_step = DST_BASE + (step - 3'd4);
      end
    end else begin
      raw_addr_for_step = (verify_source ? SRC_BASE : DST_BASE) + step;
    end
  endfunction

  function automatic logic [DATA_W-1:0] raw_wdata_for_step(input logic [2:0] step);
    if (step < 3'd4) begin
      raw_wdata_for_step = pattern_byte(step[1:0]);
    end else begin
      raw_wdata_for_step = 8'h00;
    end
  endfunction

  function automatic logic [DATA_W-1:0] raw_expected_for_step(input logic [2:0] step);
    raw_expected_for_step = pattern_byte(step[1:0]);
  endfunction

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

  assign chan_active[0] = chan0_active;
  assign chan_active[1] = chan1_active;
  assign chan_done[0]   = chan0_done;
  assign chan_done[1]   = chan1_done;

  cfg_reg u_cfg_reg (
    .clk          (clk),
    .rst_n        (rst_n),
    .cfg_we       (cfg_we),
    .cfg_re       (1'b0),
    .cfg_addr     (cfg_addr),
    .cfg_wdata    (cfg_wdata),
    .cfg_rdata    (cfg_rdata_unused),
    .start_clear  (start_clear),
    .chan_active  (chan_active),
    .chan_done    (chan_done),
    .cfg0_src_base(cfg0_src_base),
    .cfg0_dst_base(cfg0_dst_base),
    .cfg0_len     (cfg0_len),
    .cfg0_inc_src (cfg0_inc_src),
    .cfg0_inc_dst (cfg0_inc_dst),
    .cfg0_start_en(cfg0_start_en),
    .cfg1_src_base(cfg1_src_base),
    .cfg1_dst_base(cfg1_dst_base),
    .cfg1_len     (cfg1_len),
    .cfg1_inc_src (cfg1_inc_src),
    .cfg1_inc_dst (cfg1_inc_dst),
    .cfg1_start_en(cfg1_start_en)
  );

  dma_scheduler u_dma_scheduler (
    .clk           (clk),
    .rst_n         (rst_n),
    .grant_advance (sched_advance),
    .cfg0_start_en (cfg0_start_en),
    .cfg1_start_en (cfg1_start_en),
    .ch0_active    (chan0_active),
    .ch1_active    (chan1_active),
    .grant_valid   (sched_valid),
    .grant_idx     (sched_idx)
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
    .chan0_active  (chan0_active),
    .chan0_done    (chan0_done),
    .chan1_src_cur (chan1_src_cur),
    .chan1_dst_cur (chan1_dst_cur),
    .chan1_len_rem (chan1_len_rem),
    .chan1_inc_src (chan1_inc_src),
    .chan1_inc_dst (chan1_inc_dst),
    .chan1_active  (chan1_active),
    .chan1_done    (chan1_done),
    .mem_req_valid (dma_mem_req_valid),
    .mem_req_rw    (dma_mem_req_rw),
    .mem_req_addr  (dma_mem_req_addr),
    .mem_req_wdata (dma_mem_req_wdata),
    .mem_rsp_ready (dma_mem_rsp_ready),
    .mem_rsp_valid (dma_mem_rsp_valid),
    .mem_rsp_rdata (dma_mem_rsp_rdata)
  );

  spi_psram_ctrl #(
    .RESET_CYCLES(16'd3750),
    .RESET_RECOVERY_CYCLES(16'd4)
  ) u_spi_psram_ctrl (
    .clk      (clk),
    .rst_n    (rst_n),
    .req_valid(spi_req_valid),
    .req_rw   (spi_req_rw),
    .req_addr (spi_req_addr),
    .req_wdata(spi_req_wdata),
    .req_ready(spi_req_ready),
    .rsp_valid(spi_rsp_valid),
    .rsp_rdata(spi_rsp_rdata),
    .busy     (spi_ctrl_busy),
    .spi_clk  (pmod_sck),
    .spi_cs_n (pmod_cs1_n),
    .spi_mosi (pmod_sd0),
    .spi_miso (pmod_sd1)
  );

  assign raw_selected      = (raw_state != RAW_IDLE);
  assign spi_req_valid     = raw_selected ? raw_req_valid : dma_mem_req_valid;
  assign spi_req_rw        = raw_selected ? raw_req_rw    : dma_mem_req_rw;
  assign spi_req_addr      = raw_selected ? raw_req_addr  : dma_mem_req_addr;
  assign spi_req_wdata     = raw_selected ? raw_req_wdata : dma_mem_req_wdata;
  assign raw_req_ready     = spi_req_ready & raw_selected;
  assign raw_rsp_valid     = spi_rsp_valid & raw_selected;
  assign raw_rsp_rdata     = spi_rsp_rdata;
  assign dma_mem_rsp_ready = spi_req_ready & !raw_selected;
  assign dma_mem_rsp_valid = spi_rsp_valid & !raw_selected;
  assign dma_mem_rsp_rdata = spi_rsp_rdata;

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      raw_state             <= RAW_IDLE;
      raw_is_write          <= 1'b0;
      raw_verify_source     <= 1'b0;
      raw_index             <= '0;
      raw_write_busy_seen   <= 1'b0;
      raw_last_data         <= '0;
      cfg_state             <= CFG_IDLE;
      preload_done          <= 1'b0;
      dma_done_seen         <= 1'b0;
      verify_done           <= 1'b0;
      verify_pass           <= 1'b0;
      verify_source_latched <= 1'b0;
      heartbeat_count       <= '0;
    end else begin
      raw_state             <= raw_state_next;
      raw_is_write          <= raw_is_write_next;
      raw_verify_source     <= raw_verify_source_next;
      raw_index             <= raw_index_next;
      raw_write_busy_seen   <= raw_write_busy_seen_next;
      raw_last_data         <= raw_last_data_next;
      cfg_state             <= cfg_state_next;
      preload_done          <= preload_done_next;
      dma_done_seen         <= dma_done_seen_next;
      verify_done           <= verify_done_next;
      verify_pass           <= verify_pass_next;
      verify_source_latched <= verify_source_latched_next;
      heartbeat_count       <= heartbeat_count + 1'b1;
    end
  end

  always_comb begin
    raw_req_valid             = 1'b0;
    raw_req_rw                = raw_is_write;
    raw_req_addr              = raw_addr_for_step(raw_is_write, raw_verify_source, raw_index);
    raw_req_wdata             = raw_wdata_for_step(raw_index);

    raw_state_next            = raw_state;
    raw_is_write_next         = raw_is_write;
    raw_verify_source_next    = raw_verify_source;
    raw_index_next            = raw_index;
    raw_write_busy_seen_next  = raw_write_busy_seen;
    raw_last_data_next        = raw_last_data;

    cfg_we                    = 1'b0;
    cfg_addr                  = '0;
    cfg_wdata                 = 32'h0000_0000;
    cfg_state_next            = cfg_state;

    preload_done_next         = preload_done;
    dma_done_seen_next        = dma_done_seen;
    verify_done_next          = verify_done;
    verify_pass_next          = verify_pass;
    verify_source_latched_next = verify_source_latched;

    if ((raw_state == RAW_IDLE) && (cfg_state == CFG_IDLE)) begin
      if (up_pulse) begin
        raw_state_next             = RAW_ISSUE;
        raw_is_write_next          = 1'b1;
        raw_verify_source_next     = 1'b0;
        raw_index_next             = 3'd0;
        raw_write_busy_seen_next   = 1'b0;
        preload_done_next          = 1'b0;
        dma_done_seen_next         = dma_done_seen;
        verify_done_next           = 1'b0;
        verify_pass_next           = 1'b0;
        verify_source_latched_next = 1'b0;
      end else if (left_pulse) begin
        raw_state_next             = RAW_ISSUE;
        raw_is_write_next          = 1'b0;
        raw_verify_source_next     = 1'b0;
        raw_index_next             = 3'd0;
        verify_done_next           = 1'b0;
        verify_pass_next           = 1'b1;
        verify_source_latched_next = 1'b0;
      end else if (right_pulse) begin
        raw_state_next             = RAW_ISSUE;
        raw_is_write_next          = 1'b0;
        raw_verify_source_next     = 1'b1;
        raw_index_next             = 3'd0;
        verify_done_next           = 1'b0;
        verify_pass_next           = 1'b1;
        verify_source_latched_next = 1'b1;
      end else if (down_pulse) begin
        cfg_state_next             = CFG_WRITE_0;
        dma_done_seen_next         = 1'b0;
        verify_done_next           = 1'b0;
        verify_pass_next           = 1'b0;
      end
    end

    case (raw_state)
      RAW_IDLE: begin
      end

      RAW_ISSUE: begin
        raw_req_valid = 1'b1;
        if (raw_req_ready) begin
          if (raw_is_write) begin
            raw_write_busy_seen_next = 1'b0;
            raw_state_next = RAW_WAIT_WRITE;
          end else begin
            raw_state_next = RAW_WAIT_READ;
          end
        end
      end

      RAW_WAIT_WRITE: begin
        if (!raw_write_busy_seen) begin
          if (!raw_req_ready) begin
            raw_write_busy_seen_next = 1'b1;
          end
        end else if (raw_req_ready) begin
          raw_state_next = RAW_ADVANCE;
        end
      end

      RAW_WAIT_READ: begin
        if (raw_rsp_valid) begin
          raw_last_data_next = raw_rsp_rdata;
          if (raw_rsp_rdata != raw_expected_for_step(raw_index)) begin
            verify_pass_next = 1'b0;
          end
          raw_state_next = RAW_ADVANCE;
        end
      end

      RAW_ADVANCE: begin
        if (raw_is_write) begin
          if (raw_index == 3'd7) begin
            preload_done_next = 1'b1;
            raw_state_next    = RAW_IDLE;
          end else begin
            raw_index_next = raw_index + 1'b1;
            raw_state_next = RAW_ISSUE;
          end
        end else begin
          if (raw_index == 3'd3) begin
            verify_done_next = 1'b1;
            raw_state_next   = RAW_IDLE;
          end else begin
            raw_index_next = raw_index + 1'b1;
            raw_state_next = RAW_ISSUE;
          end
        end
      end

      default: begin
        raw_state_next = RAW_IDLE;
      end
    endcase

    case (cfg_state)
      CFG_IDLE: begin
      end

      CFG_WRITE_0: begin
        cfg_we         = 1'b1;
        cfg_addr       = 3'd0;
        cfg_wdata      = {8'h00, SRC_BASE};
        cfg_state_next = CFG_WRITE_1;
      end

      CFG_WRITE_1: begin
        cfg_we         = 1'b1;
        cfg_addr       = 3'd1;
        cfg_wdata      = {8'h00, DST_BASE};
        cfg_state_next = CFG_WRITE_2;
      end

      CFG_WRITE_2: begin
        cfg_we         = 1'b1;
        cfg_addr       = 3'd2;
        cfg_wdata      = {16'h0000, DMA_LEN};
        cfg_state_next = CFG_WRITE_3;
      end

      CFG_WRITE_3: begin
        cfg_we         = 1'b1;
        cfg_addr       = 3'd3;
        cfg_wdata      = 32'h0000_0007;
        cfg_state_next = CFG_WAIT_DMA;
      end

      CFG_WAIT_DMA: begin
        if (chan0_done) begin
          dma_done_seen_next = 1'b1;
          cfg_state_next     = CFG_IDLE;
        end
      end

      default: begin
        cfg_state_next = CFG_IDLE;
      end
    endcase
  end

  always_comb begin
    pmod_cs0_n = 1'b1;
    pmod_cs2_n = 1'b1;
    pmod_sd2   = 1'b1;
    pmod_sd3   = 1'b1;

    led[0] = verify_source_latched;
    led[1] = verify_pass;
    led[2] = verify_done;
    led[3] = preload_done;
    led[4] = dma_done_seen;
    led[5] = chan0_active;
    led[6] = spi_ctrl_busy;
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
