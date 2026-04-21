module ChipInterface (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       btn_left,
  input  logic       btn_right,
  input  logic       btn_up,
  input  logic       btn_down,
  output logic [7:0] led
);

  localparam int unsigned BLINK_PERIOD = 25_000_000;
  localparam int unsigned BLINK_W      = $clog2(BLINK_PERIOD);

  logic [BLINK_W-1:0] blink_count;
  logic [7:0]         blink_leds;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      blink_count <= '0;
      blink_leds  <= 8'h01;
    end else begin
      if (blink_count == BLINK_PERIOD - 1) begin
        blink_count <= '0;
        blink_leds  <= {blink_leds[6:0], blink_leds[7]};
      end else begin
        blink_count <= blink_count + 1'b1;
      end
    end
  end

  always_comb begin
    led = blink_leds;

    if (btn_left) begin
      led[0] = 1'b1;
    end

    if (btn_right) begin
      led[1] = 1'b1;
    end

    if (btn_up) begin
      led[2] = 1'b1;
    end

    if (btn_down) begin
      led[3] = 1'b1;
    end
  end

endmodule
