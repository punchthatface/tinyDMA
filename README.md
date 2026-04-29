# tinyDMA

TinyDMA-2C is a two-channel byte DMA engine that moves data between addresses in external PSRAM over a single-bit SPI link. The repo is the reusable core/design workspace; Tiny Tapeout wrapper and submission-specific files live separately.

## Current Architecture

- [src/spi_master.sv](/Users/andrewkim/Desktop/Andrew%20Kim/Y5%20Sem%202/ASIC%20FPGA/18644/tinyDMA/src/spi_master.sv): low-level SPI bit engine
- [src/spi_psram_ctrl.sv](/Users/andrewkim/Desktop/Andrew%20Kim/Y5%20Sem%202/ASIC%20FPGA/18644/tinyDMA/src/spi_psram_ctrl.sv): PSRAM transaction controller with power-up wait and `0x66`/`0x99` reset
- [src/cfg_reg.sv](/Users/andrewkim/Desktop/Andrew%20Kim/Y5%20Sem%202/ASIC%20FPGA/18644/tinyDMA/src/cfg_reg.sv): two-channel configuration register bank
- [src/dma_scheduler.sv](/Users/andrewkim/Desktop/Andrew%20Kim/Y5%20Sem%202/ASIC%20FPGA/18644/tinyDMA/src/dma_scheduler.sv): simple round-robin channel selector
- [src/dma_controller.sv](/Users/andrewkim/Desktop/Andrew%20Kim/Y5%20Sem%202/ASIC%20FPGA/18644/tinyDMA/src/dma_controller.sv): byte-wise read/write DMA FSM
- [src/tinydma_top.sv](/Users/andrewkim/Desktop/Andrew%20Kim/Y5%20Sem%202/ASIC%20FPGA/18644/tinyDMA/src/tinydma_top.sv): integration top connecting config, scheduler, controller, and PSRAM interface

## External Device

This project targets the Tiny Tapeout [QSPI Pmod](https://store.tinytapeout.com/products/QSPI-Pmod-p716541602), specifically the APS6404 PSRAM used in single-bit SPI mode during bring-up.

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

Passing benches:

- [tb/tb_spi_master.sv](/Users/andrewkim/Desktop/Andrew%20Kim/Y5%20Sem%202/ASIC%20FPGA/18644/tinyDMA/tb/tb_spi_master.sv)
- [tb/tb_spi_psram_ctrl.sv](/Users/andrewkim/Desktop/Andrew%20Kim/Y5%20Sem%202/ASIC%20FPGA/18644/tinyDMA/tb/tb_spi_psram_ctrl.sv)
- [tb/tb_spi_read_id.sv](/Users/andrewkim/Desktop/Andrew%20Kim/Y5%20Sem%202/ASIC%20FPGA/18644/tinyDMA/tb/tb_spi_read_id.sv)
- [tb/tb_dma_subsystem.sv](/Users/andrewkim/Desktop/Andrew%20Kim/Y5%20Sem%202/ASIC%20FPGA/18644/tinyDMA/tb/tb_dma_subsystem.sv)
- [tb/tb_tinydma_top.sv](/Users/andrewkim/Desktop/Andrew%20Kim/Y5%20Sem%202/ASIC%20FPGA/18644/tinyDMA/tb/tb_tinydma_top.sv)

DMA cases currently covered:

- incrementing source and destination copy
- fixed-source fill
- fixed-destination overwrite
- zero-length completion
- simultaneous two-channel scheduling

## FPGA Bring-Up

The known-good ULX3S/QSPI-Pmod bring-up harness is preserved in:

- [fpga/ChipInterface_psram_bringup.sv](/Users/andrewkim/Desktop/Andrew%20Kim/Y5%20Sem%202/ASIC%20FPGA/18644/tinyDMA/fpga/ChipInterface_psram_bringup.sv)
- [README_FPGA_BRINGUP.md](/Users/andrewkim/Desktop/Andrew%20Kim/Y5%20Sem%202/ASIC%20FPGA/18644/tinyDMA/README_FPGA_BRINGUP.md)
