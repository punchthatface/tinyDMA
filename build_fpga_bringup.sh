#!/bin/sh

set -eu

BUILD_DIR=build_fpga

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

yosys -p 'read_verilog -sv src/dma_pkg.sv src/spi_master.sv src/spi_psram_ctrl.sv fpga/ChipInterface_psram_bringup.sv; synth_ecp5 -json build_fpga/synth_out.json -top ChipInterface'

nextpnr-ecp5 --12k --json "$BUILD_DIR"/synth_out.json --lpf constraints.lpf --textcfg "$BUILD_DIR"/pnr_out.config

ecppack --compress "$BUILD_DIR"/pnr_out.config "$BUILD_DIR"/bitstream.bit

echo "Bring-up bitstream written to $BUILD_DIR/bitstream.bit"
echo "Upload with: fujprog $BUILD_DIR/bitstream.bit"
