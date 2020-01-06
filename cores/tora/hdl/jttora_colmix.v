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
    Date: 22-9-2019 */

`timescale 1ns/1ps

module jttora_colmix(
    input            rst,
    input            clk,
    input            cen6 /* synthesis direct_enable = 1 */,
    input            cpu_cen,
    // pixel input from generator modules
    input [5:0]      char_pxl,        // character color code
    input [8:0]      scr_pxl,
    input [7:0]      obj_pxl,
    input            LVBL,
    input            LHBL,
    output  reg      LHBL_dly,
    output  reg      LVBL_dly,
    // Priority PROM
    input [7:0]      prog_addr,
    input            prom_prio_we,
    input [3:0]      prom_din,
    // Avatars
    input [3:0]      avatar_idx,
    input            pause,
    // CPU inteface
    input [10:1]     AB,
    input            col_uw,
    input            col_lw,
    input [15:0]     DB,

    output reg [3:0] red,
    output reg [3:0] green,
    output reg [3:0] blue,
    // Debug
    input      [3:0] gfx_en
);

parameter SIM_PRIO = "../../../rom/tora/tr.9e";

reg [9:0] pixel_mux;

wire enable_char = gfx_en[0];
wire enable_scr  = gfx_en[1];
wire obj_blank   = &obj_pxl[3:0];
wire enable_obj  = gfx_en[3];

//reg  [2:0] obj_sel; // signals whether an object pixel is selected
wire [1:0] prio;
reg  [7:0] seladdr;
reg  [1:0] presel;
wire       char_blank_n = |(~char_pxl[1:0]);

always @(*) begin
    seladdr[7]   = 1'b1;
    seladdr[6]   = enable_char & char_blank_n;
    seladdr[5]   = enable_obj  & ~obj_blank;
    seladdr[4]   = scr_pxl[8]; // Scroll wins 8
    seladdr[3:0] = scr_pxl[3:0]; // for some colours, the background
        // will be imposed over the objects (colours 9 to 15)
end

reg       obj_sel;
reg [3:0] obj_pxl2;

always @(posedge clk) if(cen6) begin
    obj_sel  <= prio==2'b10;
    obj_pxl2 <= obj_pxl[3:0];
    case( prio )
        2'b11: pixel_mux[7:0] <= { 2'b0, char_pxl };
        2'b10: pixel_mux[7:0] <= obj_pxl; // 2301
        2'b01: pixel_mux[7:0] <= scr_pxl[7:0];
    endcase
    pixel_mux[9:8] <= prio;
end

// Blanking delay
wire [1:0] pre_BL;

jtframe_sh #(.width(2),.stages(5)) u_blank_dly(
    .clk    ( clk      ),
    .clk_en ( cen6     ),
    .din    ( {LHBL, LVBL}     ),
    .drop   ( pre_BL   )
);

// Address mux
reg  [9:0] pal_addr;
reg        pal_uwe, pal_lwe;
reg        coloff; // colour off
wire [3:0] pal_red, pal_green, pal_blue, pal_bright;

always @(*) begin
    if( pre_BL!=2'b11 ) begin
        pal_addr = AB;
        pal_uwe   = col_uw;
        pal_lwe   = col_lw;
    end else begin
        pal_addr = pixel_mux;
        pal_uwe  = 1'b0;
        pal_lwe  = 1'b0;
    end
end

always @(posedge clk) if(cen6) begin
    coloff <= pre_BL!=2'b11;
    {LHBL_dly, LVBL_dly} <= pre_BL;
end

// Palette is in RAM

jtframe_ram #(.aw(10),.dw(4),.simhexfile("palr.hex")) u_upal(
    .clk        ( clk         ),
    .cen        ( cpu_cen     ), // clock enable only applies to write operation
    .data       ( DB[11:8]    ),
    .addr       ( pal_addr    ),
    .we         ( pal_uwe     ),
    .q          ( pal_red     )
);

jtframe_ram #(.aw(10),.dw(8),.simhexfile("palgb.hex")) u_lpal(
    .clk        ( clk         ),
    .cen        ( cpu_cen     ), // clock enable only applies to write operation
    .data       ( DB[7:0]     ),
    .addr       ( pal_addr    ),
    .we         ( pal_lwe     ),
    .q          ( { pal_green, pal_blue } )
);

wire [11:0] avatar_mux;

jtgng_avatar_pal u_avatar(
    .clk        (  clk          ),
    .pause      (  pause        ),
    .avatar_idx (  avatar_idx   ),
    .obj_sel    (  obj_sel      ),
    .obj_pxl    (  obj_pxl2     ),
    .pal_red    (  pal_red      ),
    .pal_green  (  pal_green    ),
    .pal_blue   (  pal_blue     ),
    .avatar_mux (  avatar_mux   )
);

// Clock must be faster than 6MHz so prio is ready for the next
// 6MHz clock cycle:
jtframe_prom #(.aw(8),.dw(2),.simfile(SIM_PRIO)) u_prio(
    .clk    ( clk           ),
    .cen    ( 1'b1          ),
    .data   ( prom_din[1:0] ),
    .rd_addr( seladdr       ),
    .wr_addr( prog_addr     ),
    .we     ( prom_prio_we  ),
    .q      ( prio          )
);

always @(posedge clk) if (cen6)
    {red, green, blue } <= (!coloff /*&& !pal_bright[3]*/) ? 
        avatar_mux : 12'd0;

endmodule // jtgng_colmix