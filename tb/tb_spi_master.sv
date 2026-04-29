module tb_spi_master;

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

  logic [7:0] expected_tx;
  logic [7:0] observed_tx;
  logic [7:0] slave_tx;
  logic [7:0] expected_rx;

  int tx_bit_count;
  int rx_bit_count;

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

  always #5 clk = ~clk;

  always @(posedge spi_sck or posedge spi_cs_n) begin
    if (spi_cs_n) begin
      observed_tx  <= '0;
      tx_bit_count <= 0;
    end else begin
      observed_tx  <= {observed_tx[6:0], spi_mosi};
      tx_bit_count <= tx_bit_count + 1;
    end
  end

  always @(negedge spi_cs_n) begin
    if (rx_en) begin
      spi_miso     <= slave_tx[7];
      slave_tx     <= {slave_tx[6:0], 1'b0};
      rx_bit_count <= 1;
    end else begin
      spi_miso <= 1'b0;
    end
  end

  always @(negedge spi_sck or posedge spi_cs_n) begin
    if (spi_cs_n) begin
      spi_miso    <= 1'b0;
      rx_bit_count <= 0;
    end else if (rx_en) begin
      spi_miso     <= slave_tx[7];
      slave_tx     <= {slave_tx[6:0], 1'b0};
      rx_bit_count <= rx_bit_count + 1;
    end else begin
      spi_miso <= 1'b0;
    end
  end

  initial begin
    clk         = 1'b0;
    rst_n       = 1'b0;
    start       = 1'b0;
    nbits       = '0;
    tx_data     = '0;
    rx_en       = 1'b0;
    spi_miso    = 1'b0;
    expected_tx = 8'hA5;
    expected_rx = 8'h3C;
    observed_tx = '0;
    slave_tx    = expected_rx;
    tx_bit_count = 0;
    rx_bit_count = 0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    $display("");
    $display("[tb_spi_master] Test 1: transmit 8'h%02h on MOSI", expected_tx);

    @(posedge clk);
    tx_data <= {8'h00, expected_tx};
    nbits   <= 6'd8;
    rx_en   <= 1'b0;
    start   <= 1'b1;

    @(posedge clk);
    start <= 1'b0;

    wait (done == 1'b1);

    if (observed_tx != expected_tx) begin
      $display("FAIL: MOSI mismatch, expected 0x%02h got 0x%02h", expected_tx, observed_tx);
      $finish;
    end

    if (tx_bit_count != 8) begin
      $display("FAIL: expected 8 transmitted bits, got %0d", tx_bit_count);
      $finish;
    end

    $display("  observed MOSI byte = 0x%02h, transmitted bits = %0d", observed_tx, tx_bit_count);

    $display("[tb_spi_master] Test 2: receive 8'h%02h on MISO", expected_rx);

    @(posedge clk);
    observed_tx <= '0;
    slave_tx    <= expected_rx;

    tx_data <= {8'h00, 8'h00};
    nbits   <= 6'd8;
    rx_en   <= 1'b1;
    start   <= 1'b1;

    @(posedge clk);
    start <= 1'b0;

    wait (done == 1'b1);

    if (rx_data[7:0] != expected_rx) begin
      $display("FAIL: MISO mismatch, expected 0x%02h got 0x%02h", expected_rx, rx_data[7:0]);
      $finish;
    end

    if (spi_cs_n != 1'b1 || spi_sck != 1'b0) begin
      $display("FAIL: SPI pins did not return to idle state");
      $finish;
    end

    $display("  observed rx_data[7:0] = 0x%02h", rx_data[7:0]);
    $display("  idle pins: cs_n=%0b sck=%0b", spi_cs_n, spi_sck);
    $display("[tb_spi_master] PASS");
    $finish;
  end

endmodule
