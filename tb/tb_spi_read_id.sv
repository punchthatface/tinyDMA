module tb_spi_read_id;

  localparam int MAX_BITS = 16;

  logic clk;
  logic rst_n;

  logic                start;
  logic [5:0]          nbits;
  logic [MAX_BITS-1:0] tx_data;
  logic                rx_en;

  logic                busy;
  logic                done;
  logic [MAX_BITS-1:0] rx_data;

  logic spi_cs_n;
  logic spi_sck;
  logic spi_mosi;
  logic spi_miso;

  spi_master #(
    .MAX_BITS(MAX_BITS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .nbits(nbits),
    .tx_data(tx_data),
    .rx_en(rx_en),
    .busy(busy),
    .done(done),
    .rx_data(rx_data),
    .spi_cs_n(spi_cs_n),
    .spi_sck(spi_sck),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso)
  );

  psram_model mem (
    .cs_n (spi_cs_n),
    .sclk (spi_sck),
    .mosi (spi_mosi),
    .miso (spi_miso)
  );

  always #5 clk = ~clk;

  initial begin
    clk     = 1'b0;
    rst_n   = 1'b0;
    start   = 1'b0;
    nbits   = '0;
    tx_data = '0;
    rx_en   = 1'b0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    @(posedge clk);
    tx_data <= 16'h9F00;
    nbits   <= 6'd16;
    rx_en   <= 1'b1;
    start   <= 1'b1;

    @(posedge clk);
    start <= 1'b0;

    wait (done == 1'b1);

    if (rx_data[7:0] != 8'h0D) begin
      $display("FAIL: expected ID 0x0D, got 0x%02h", rx_data[7:0]);
      $finish;
    end

    $display("PASS");
    $finish;
  end

endmodule
