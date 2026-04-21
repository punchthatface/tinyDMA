# FPGA Bring-Up Notes

Known-good board test top:

- Source file: `src/ChipInterface_psram_bringup.sv`
- Dedicated build flow: `build_fpga_bringup.sh`
- Current `src/ChipInterface.sv` is also the same simple PSRAM bring-up harness, but the
  dedicated script preserves this checkpoint explicitly.

Known-good PMOD observation from EX2 task 5:

- Lower female-header row corresponds to `GP`
- Upper female-header row corresponds to `GN`

Bring-up button actions:

- `btn_up`: write `0xA5` to `0x000010`
- `btn_down`: write `0x3C` to `0x000010`
- `btn_left` or `btn_right`: read from `0x000010`

Bring-up LEDs:

- `D3..D0`: low nibble of last data byte
- `D4`: read response seen
- `D5`: read matched expected value
- `D6`: controller busy
- `D7`: heartbeat
