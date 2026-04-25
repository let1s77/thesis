`ifndef IPU_ADDR_MAP_VH
`define IPU_ADDR_MAP_VH

// -----------------------------------------------------------------------------
// Global BRAM buffer base addresses (from memory mapping)
// -----------------------------------------------------------------------------
`define IMG_IN_BUF_BASE   32'h0001_0000
`define IMG_OUT_BUF_BASE  32'h0004_0000
`define IMG_TMP_BUF_BASE  32'h0007_0000

// 192 KB per image buffer => 196,608 bytes => 49,152 words (32-bit / word)
`define IMG_BUF_SIZE_BYTES 32'h0003_0000
`define IMG_BUF_DEPTH_WORD 16'd49152

// -----------------------------------------------------------------------------
// IPU register block base
// -----------------------------------------------------------------------------
`define IPU_BASE         32'h1002_0000

// Register offsets
`define IPU_CTRL_OFS        32'h0000_0000
`define IPU_STATUS_OFS      32'h0000_0004
`define IPU_SRC_ADDR_OFS    32'h0000_0008
`define IPU_DST_ADDR_OFS    32'h0000_000C
`define IPU_TMP_ADDR_OFS    32'h0000_0010
`define IPU_IMG_WIDTH_OFS   32'h0000_0014
`define IPU_IMG_HEIGHT_OFS  32'h0000_0018
`define IPU_IMG_STRIDE_OFS  32'h0000_001C
`define IPU_IMG_FORMAT_OFS  32'h0000_0020
`define IPU_PARAM_0_OFS     32'h0000_0024
`define IPU_PARAM_1_OFS     32'h0000_0028
`define IPU_PARAM_2_OFS     32'h0000_002C
`define IPU_IRQ_EN_OFS      32'h0000_0030
`define IPU_IRQ_STATUS_OFS  32'h0000_0034
`define IPU_DEBUG_OFS       32'h0000_0038
`define IPU_ID_OFS          32'h0000_003C

// Absolute addresses
`define IPU_CTRL        (`IPU_BASE + `IPU_CTRL_OFS)
`define IPU_STATUS      (`IPU_BASE + `IPU_STATUS_OFS)
`define IPU_SRC_ADDR    (`IPU_BASE + `IPU_SRC_ADDR_OFS)
`define IPU_DST_ADDR    (`IPU_BASE + `IPU_DST_ADDR_OFS)
`define IPU_TMP_ADDR    (`IPU_BASE + `IPU_TMP_ADDR_OFS)
`define IPU_IMG_WIDTH   (`IPU_BASE + `IPU_IMG_WIDTH_OFS)
`define IPU_IMG_HEIGHT  (`IPU_BASE + `IPU_IMG_HEIGHT_OFS)
`define IPU_IMG_STRIDE  (`IPU_BASE + `IPU_IMG_STRIDE_OFS)
`define IPU_IMG_FORMAT  (`IPU_BASE + `IPU_IMG_FORMAT_OFS)
`define IPU_PARAM_0     (`IPU_BASE + `IPU_PARAM_0_OFS)
`define IPU_PARAM_1     (`IPU_BASE + `IPU_PARAM_1_OFS)
`define IPU_PARAM_2     (`IPU_BASE + `IPU_PARAM_2_OFS)
`define IPU_IRQ_EN      (`IPU_BASE + `IPU_IRQ_EN_OFS)
`define IPU_IRQ_STATUS  (`IPU_BASE + `IPU_IRQ_STATUS_OFS)
`define IPU_DEBUG       (`IPU_BASE + `IPU_DEBUG_OFS)
`define IPU_ID          (`IPU_BASE + `IPU_ID_OFS)

// CTRL bits
`define IPU_CTRL_EN_BIT         0
`define IPU_CTRL_START_BIT      1
`define IPU_CTRL_SOFT_RST_BIT   2
`define IPU_CTRL_CONT_MODE_BIT  3

// STATUS bits
`define IPU_STATUS_IDLE_BIT     0
`define IPU_STATUS_BUSY_BIT     1
`define IPU_STATUS_DONE_BIT     2
`define IPU_STATUS_ERROR_BIT    3

`endif