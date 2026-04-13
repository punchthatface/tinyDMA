# tinyDMA
TinyDMA-2C is a programmable two-channel direct memory access (DMA) engine that autonomously transfers blocks of data between memory locations stored in external memory. Each channel can be configured independently with a source address, destination address, transfer length, and address increment mode.

## External Device
This project uses [QSPI Pmod](https://store.tinytapeout.com/products/QSPI-Pmod-p716541602) \
Specifically, the 64M bit QSPI PRAM (APS6404L-3SQR)


## Plan
1. Implement the SPI controller first.
2. Test the SPI controller in simulation.
3. Bring the SPI controller up on the FPGA with the QSPI Pmod.
4. After SPI is working, start DMA development.
5. Integrate the full system and expand testing.