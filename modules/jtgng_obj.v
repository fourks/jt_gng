/*  This file is part of JT_GNG.
    JT_GNG program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JT_GNG program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JT_GNG.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 27-10-2017 */

module jtgng_obj #(parameter
    OBJMAX      = 9'h180,
    OBJMAX_LINE = 6'd24,
    DMA_DW      = 8,        // Data width of each DMA transfer
    DMA_AW      = 9,        // Data width of each DMA transfer
    PXL_DLY     = 7,
    ROM_AW      = 16,
    ROM_DW      = 16,
    LAYOUT      = 0,   // 0: GnG, Commando
                       // 1: 1943
                       // 2: GunSmoke
                       // 3: Bionic Commando
                       // 4: Black Tiger
    INVY        = 0,   // Invert Y position, used by Tiger Road
    PALW        = 2,
    PALETTE     = 0, // 1 if the palette PROM is used
    PALETTE1_SIMFILE = "", // only for simulation
    PALETTE0_SIMFILE = "", // only for simulation
    AVATAR_MAX  = 8, // only used if macro AVATARS is defined
    VERTICAL    = 1  // 1 vertical game, 0 otherwise. Used by AVATARS only.
) (
    input               rst,
    input               clk,
    input               dma_cen,   // use same as original PCB
    input               draw_cen,  // make it faster than original
    input               pxl_cen,   // use same as original PCB
    // screen
    input               HINIT,
    input               LHBL,
    input               LVBL,
    input               LVBL_obj,
    input   [ 7:0]      V,
    input   [ 8:0]      H,
    input               flip,
    // Pause screen
    input               pause,
    output  [ 3:0]      avatar_idx,
    // shared bus
    output [DMA_AW-1:0] AB,
    input  [DMA_DW-1:0] DB,
    input               OKOUT,
    output              bus_req,        // Request bus
    input               bus_ack,    // bus acknowledge
    output              blen,   // bus line counter enable
    // Palette PROM
    input               OBJON,
    input   [ 7:0]      prog_addr,
    input               prom_hi_we,
    input               prom_lo_we,
    input   [ 3:0]      prog_din,
    // SDRAM interface
    output [ROM_AW-1:0] obj_addr,
    input  [ROM_DW-1:0] obj_data,
    input               rom_ok,
    // pixel output
    output  [(PALETTE?7:(PALW+4-1)):0] obj_pxl
);

wire [DMA_AW-1:0] pre_scan;
wire [DMA_DW-1:0] objbuf_data;

wire line, fill, line_obj_we;
wire [4:0] post_scan;
wire [7:0] VF;

wire [4:0] objcnt;
wire [3:0] pxlcnt;
wire       rom_wait, draw_over, HINIT_draw;

jtgng_objcnt #(.OBJMAX_LINE(OBJMAX_LINE)) u_cnt(
    .rst        ( rst         ),
    .clk        ( clk         ),
    .draw_cen   ( draw_cen    ),
    .rom_ok     ( rom_ok      ),
    .rom_wait   ( rom_wait    ),
    .draw_over  ( draw_over   ),
    .HINIT      ( HINIT       ),
    .HINIT_draw ( HINIT_draw  ),
    .objcnt     ( objcnt      ),
    .pxlcnt     ( pxlcnt      )
);

// DMA to 6809 RAM memory to copy the sprite data
wire [DMA_DW-1:0] dma_dout, dma_muxed;
jtgng_objdma #(
    .DW         ( DMA_DW     ),
    .AW         ( DMA_AW     ),
    .OBJMAX     ( OBJMAX     ),
    .INVY       ( INVY       ))
 u_dma(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( dma_cen   ),
    // screen
    .LVBL       ( LVBL       ),
    // shared bus
    .AB         ( AB        ),
    .DB         ( DB        ),
    .OKOUT      ( OKOUT     ),
    .bus_req    ( bus_req   ),  // Request bus
    .bus_ack    ( bus_ack   ),  // bus acknowledge
    .blen       ( blen      ),  // bus line counter enable
    // output data
    .pre_scan   ( pre_scan  ),
    .dma_dout   ( dma_dout  )
);

`ifdef AVATARS
jtgng_avatar #(
    .VERTICAL   ( VERTICAL   ),
    .DW         ( DMA_DW     ),
    .AVATAR_MAX ( AVATAR_MAX ))
u_avatar (
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen        ( draw_cen      ),
    // screen
    .LVBL       ( LVBL          ),
    .pause      ( pause         ),
    .avatar_idx ( avatar_idx    ),
    // output data
    .pre_scan   ( pre_scan[8:0] ),
    .dma_dout   ( dma_dout      ),
    .muxed_dout ( dma_muxed     )
);
`else
assign dma_muxed  = dma_dout;
assign avatar_idx = 4'd0;
`endif

// Parse sprite data per line
jtgng_objbuf #(
    .DW         ( DMA_DW     ),
    .AW         ( DMA_AW     ),
    .OBJMAX     ( OBJMAX     ),
    .OBJMAX_LINE( OBJMAX_LINE))
u_buf(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .draw_cen       ( draw_cen      ),
    // screen
    .HINIT_draw     ( HINIT_draw    ),
    .LVBL           ( LVBL_obj      ),
    .V              ( V             ),
    .VF             ( VF            ),
    .flip           ( flip          ),
    // sprite data scan
    .pre_scan       ( pre_scan      ),
    .dma_dout       ( dma_muxed     ),
    // sprite data buffer
    .rom_wait       ( rom_wait      ),
    .objbuf_data    ( objbuf_data   ),
    .objcnt         ( objcnt        ),
    .pxlcnt         ( pxlcnt        ),
    .line           ( line          )
);

wire [8:0] posx;
localparam PXLW = PALETTE ? 8 : (PALW+4);

wire [PALW-1:0] pospal;
wire [(PALETTE?7:3):0] new_pxl;

// draw the sprite
jtgng_objdraw #(
    .DW               ( DMA_DW            ),
    .ROM_AW           ( ROM_AW            ),
    .LAYOUT           ( LAYOUT            ),
    .PALW             ( PALW              ),
    .PALETTE          ( PALETTE           ),
    .PALETTE1_SIMFILE ( PALETTE1_SIMFILE  ),
    .PALETTE0_SIMFILE ( PALETTE0_SIMFILE  ))
u_draw(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .cen            ( draw_cen      ),
    .OBJON          ( OBJON         ),
    // screen
    .VF             ( VF            ),
    .pxlcnt         ( pxlcnt        ),
    .flip           ( flip          ),
    .pause          ( pause         ),
    // per-line sprite data
    .objcnt         ( objcnt        ),
    .objbuf_data    ( objbuf_data   ),
    // SDRAM interface
    .obj_addr       ( obj_addr      ),
    .obj_data       ( obj_data      ),
    .rom_wait       ( rom_wait      ),
    .draw_over      ( draw_over     ),
    // PROMs
    .prog_addr      ( prog_addr     ),
    .prom_hi_we     ( prom_hi_we    ),
    .prom_lo_we     ( prom_lo_we    ),
    .prog_din       ( prog_din      ),
    // pixel data
    .posx           ( posx          ),
    .pospal         ( pospal        ),
    .new_pxl        ( new_pxl       )
);

// line buffers for pixel data
// obj_dly is not object pixel delay with respect to background
// instead, it is the internal delay from previous stages
wire [PXLW-1:0] pxl_data;
generate
    if( PALETTE==1 )
        assign pxl_data = new_pxl;
    else
        assign pxl_data = {pospal, new_pxl};
endgenerate

jtgng_objpxl #(.dw(PXLW),.palw(PALW),.PXL_DLY(PXL_DLY)) u_pxlbuf(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .pxl_cen        ( pxl_cen       ),
    .cen            ( draw_cen      ),
    // screen
    .LHBL           ( LHBL          ),
    .flip           ( flip          ),
    .posx           ( posx          ),
    .line           ( line          ),
    // pixel data
    .new_pxl        ( pxl_data      ),
    .obj_pxl        ( obj_pxl       )
);

endmodule