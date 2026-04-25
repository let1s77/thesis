`ifndef SOC_ADDR_MAP_VH
`define SOC_ADDR_MAP_VH

// -----------------------------------------------------------------------------
// SoC global memory map
// Follow memory_mapping.xlsx exactly, only add definitions if needed.
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Boot / Local Memory
// -----------------------------------------------------------------------------
`define BOOT_MEM_BASE           32'h0000_0000
`define BOOT_MEM_END            32'h0000_FFFF
`define BOOT_MEM_SIZE_BYTES     32'h0001_0000   // 64 KB

// -----------------------------------------------------------------------------
// On-chip BRAM Frame Memory
// -----------------------------------------------------------------------------
`define FRAME_MEM_BASE          32'h0001_0000
`define FRAME_MEM_END           32'h0007_FFFF
`define FRAME_MEM_SIZE_BYTES    32'h0003_0000   // 192 KB (3 x 64 KB for 128x128)

// IMG_IN buffer : 64 KB  (128x128 = 16384 words)
`define IMG_IN_BUF_BASE         32'h0001_0000
`define IMG_IN_BUF_END          32'h0001_FFFF
`define IMG_IN_BUF_SIZE_BYTES   32'h0001_0000
`define IMG_IN_BUF_DEPTH_WORD   16'd16384

// IMG_OUT buffer : 64 KB  (128x128 = 16384 words)
`define IMG_OUT_BUF_BASE        32'h0004_0000
`define IMG_OUT_BUF_END         32'h0004_FFFF
`define IMG_OUT_BUF_SIZE_BYTES  32'h0001_0000
`define IMG_OUT_BUF_DEPTH_WORD  16'd16384

// IMG_TMP buffer : 64 KB  (128x128 = 16384 words)
`define IMG_TMP_BUF_BASE        32'h0007_0000
`define IMG_TMP_BUF_END         32'h0007_FFFF
`define IMG_TMP_BUF_SIZE_BYTES  32'h0001_0000
`define IMG_TMP_BUF_DEPTH_WORD  16'd16384

// -----------------------------------------------------------------------------
// Peripheral region
// -----------------------------------------------------------------------------
`define PERI_BASE               32'h1000_0000
`define PERI_END                32'h1000_FFFF
`define PERI_SIZE_BYTES         32'h0001_0000   // 64 KB

// Peripheral detail map
`define PERI_RED_LED_ADDR       32'h1000_0000
`define PERI_GREEN_LED_ADDR     32'h1000_0004
`define PERI_HEX0_3_ADDR        32'h1000_0010
`define PERI_HEX4_7_ADDR        32'h1000_0014
`define PERI_LCD_ADDR           32'h1000_0020
`define PERI_SWITCH_ADDR        32'h1000_0030
`define PERI_KEY_ADDR           32'h1000_0034

// -----------------------------------------------------------------------------
// DMA register block
// -----------------------------------------------------------------------------
`define DMA_BASE                32'h1001_0000
`define DMA_END                 32'h1001_0FFF
`define DMA_SIZE_BYTES          32'h0000_1000   // 4 KB

// DMA register offsets
`define DMA_CTRL_OFS            32'h0000_0000
`define DMA_STATUS_OFS          32'h0000_0004
`define DMA_SRC_ADDR_OFS        32'h0000_0008
`define DMA_DST_ADDR_OFS        32'h0000_000C
`define DMA_XSIZE_OFS           32'h0000_0010
`define DMA_YSIZE_OFS           32'h0000_0014

// Added from memory_mapping.xlsx detail map
`define DMA_SRC_STRIDE_OFS      32'h0000_0018
`define DMA_DST_STRIDE_OFS      32'h0000_001C
`define DMA_CFG_OFS             32'h0000_0020
`define DMA_IRQ_EN_OFS          32'h0000_0024
`define DMA_IRQ_STATUS_OFS      32'h0000_0028
`define DMA_ID_OFS              32'h0000_002C

// DMA absolute register addresses
`define DMA_CTRL                (`DMA_BASE + `DMA_CTRL_OFS)
`define DMA_STATUS              (`DMA_BASE + `DMA_STATUS_OFS)
`define DMA_SRC_ADDR            (`DMA_BASE + `DMA_SRC_ADDR_OFS)
`define DMA_DST_ADDR            (`DMA_BASE + `DMA_DST_ADDR_OFS)
`define DMA_XSIZE               (`DMA_BASE + `DMA_XSIZE_OFS)
`define DMA_YSIZE               (`DMA_BASE + `DMA_YSIZE_OFS)

// Added from memory_mapping.xlsx detail map
`define DMA_SRC_STRIDE          (`DMA_BASE + `DMA_SRC_STRIDE_OFS)
`define DMA_DST_STRIDE          (`DMA_BASE + `DMA_DST_STRIDE_OFS)
`define DMA_CFG                 (`DMA_BASE + `DMA_CFG_OFS)
`define DMA_IRQ_EN              (`DMA_BASE + `DMA_IRQ_EN_OFS)
`define DMA_IRQ_STATUS          (`DMA_BASE + `DMA_IRQ_STATUS_OFS)
`define DMA_ID                  (`DMA_BASE + `DMA_ID_OFS)

// -----------------------------------------------------------------------------
// IPU register block base
// -----------------------------------------------------------------------------
`define IPU_BASE                32'h1002_0000
`define IPU_END                 32'h1002_0FFF
`define IPU_SIZE_BYTES          32'h0000_1000   // 4 KB

// -----------------------------------------------------------------------------
// System / IRQ Control (reserved)
// -----------------------------------------------------------------------------
`define SYS_IRQ_CTRL_BASE       32'h1003_0000
`define SYS_IRQ_CTRL_END        32'h1003_0FFF
`define SYS_IRQ_CTRL_SIZE_BYTES 32'h0000_1000   // 4 KB

// -----------------------------------------------------------------------------
// Reserved / future expansion
// -----------------------------------------------------------------------------
`define RESERVED_BASE           32'h1004_0000
`define RESERVED_END            32'hFFFF_FFFF

`endif