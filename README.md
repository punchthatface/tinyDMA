# tinyDMA

TinyDMA-2C is a compact two-channel SystemVerilog DMA engine designed for a resource-constrained Tiny Tapeout/Sky130 implementation. It transfers data between addresses in external PSRAM over a single-bit SPI interface.

The design emphasizes useful functionality within a small hardware footprint: two programmable DMA channels, round-robin scheduling, configurable source/destination address behavior, and an external PSRAM controller.

The project was developed and validated across RTL simulation, FPGA hardware bring-up, and the Tiny Tapeout ASIC implementation flow.

This repository contains the reusable RTL core, verification environment, and FPGA bring-up infrastructure. The Tiny Tapeout/Sky130 submission wrapper is maintained separately in [ttsky-tinyDMA](https://github.com/punchthatface/ttsky-tinyDMA).

## Architecture

- [src/spi_master.sv](src/spi_master.sv): low-level SPI bit engine
- [src/spi_psram_ctrl.sv](src/spi_psram_ctrl.sv): PSRAM transaction controller with power-up wait and `0x66`/`0x99` reset
- [src/cfg_reg.sv](src/cfg_reg.sv): two-channel configuration register bank
- [src/dma_scheduler.sv](src/dma_scheduler.sv): round-robin channel selector
- [src/dma_controller.sv](src/dma_controller.sv): byte-wise read/write DMA FSM
- [src/tinydma_top.sv](src/tinydma_top.sv): integration top connecting configuration, scheduling, DMA control, and the PSRAM interface

## External Device

This project targets the Tiny Tapeout [QSPI Pmod](https://store.tinytapeout.com/products/QSPI-Pmod-p716541602), specifically the APS6404 PSRAM used in single-bit SPI mode.

## Register Map

Each DMA channel exposes four logical registers:

- register 0: `src_base`
- register 1: `dst_base`
- register 2: `len`
- register 3: control/status

Control bits:

- bit 0: `start`
- bit 1: `inc_src`
- bit 2: `inc_dst`
- bit 8: `active` status
- bit 9: `done` status

For the current development top:

- channel 0 uses addresses `0..3`
- channel 1 uses addresses `4..7`

## Verification

The reusable RTL was verified with module-level and subsystem-level SystemVerilog testbenches.

Passing benches:

- [tb/tb_spi_master.sv](tb/tb_spi_master.sv)
- [tb/tb_spi_psram_ctrl.sv](tb/tb_spi_psram_ctrl.sv)
- [tb/tb_spi_read_id.sv](tb/tb_spi_read_id.sv)
- [tb/tb_dma_subsystem.sv](tb/tb_dma_subsystem.sv)
- [tb/tb_tinydma_top.sv](tb/tb_tinydma_top.sv)

DMA cases covered include:

- incrementing source and destination copy
- fixed-source fill
- fixed-destination overwrite
- zero-length completion
- simultaneous two-channel scheduling

The Tiny Tapeout integration is additionally verified with cocotb using Verilator as the simulation backend.

## FPGA Bring-Up

Before integrating the full DMA datapath, the PSRAM interface was validated on a ULX3S FPGA using the Tiny Tapeout QSPI Pmod.

A small standalone hardware harness issues known reads and writes to the APS6404 PSRAM using board buttons and reports transaction status and returned data through LEDs. This provided a known-good checkpoint for debugging the physical SPI/PSRAM interface independently of the DMA controller.

Relevant files:

- [FPGA bring-up top](fpga/ChipInterface_psram_bringup.sv)
- [FPGA bring-up notes](README_FPGA_BRINGUP.md)
- `build_fpga_bringup.sh`

## Tiny Tapeout / ASIC Implementation

The Tiny Tapeout integration targets the Sky130 process and was optimized around a tight tile-area budget.

The design completed the Tiny Tapeout flow, including RTL verification, synthesis, placement and routing, and GDS generation.

The Tiny Tapeout-specific wrapper and submission flow are maintained in [ttsky-tinyDMA](https://github.com/punchthatface/ttsky-tinyDMA).

## Design Goals

TinyDMA was primarily an exercise in fitting useful functionality into a constrained hardware budget rather than maximizing clock frequency.

The design trades hardware resources against functionality while still providing:

- two independently configurable DMA channels
- shared access to a single external PSRAM interface
- round-robin scheduling between active channels
- configurable increment/fixed-address transfer modes
- hardware validation on FPGA
- ASIC implementation through the Tiny Tapeout/Sky130 flow
