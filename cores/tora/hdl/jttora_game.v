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
    Date: 12-10-2019 */

`timescale 1ns/1ps

module jttora_game(
    input           rst,
    input           clk,
    output          cen12,      // 12   MHz
    output          cen6,       //  6   MHz
    output          cen3,       //  3   MHz
    output          cen1p5,     //  1.5 MHz
    output   [3:0]  red,
    output   [3:0]  green,
    output   [3:0]  blue,
    output          LHBL,
    output          LVBL,
    output          LHBL_dly,
    output          LVBL_dly,
    output          HS,
    output          VS,
    // cabinet I/O
    input   [ 1:0]  start_button,
    input   [ 1:0]  coin_input,
    input   [ 6:0]  joystick1,
    input   [ 6:0]  joystick2,
    // SDRAM interface
    input           downloading,
    output          dwnld_busy,
    input           loop_rst,
    output          sdram_req,
    output  [21:0]  sdram_addr,
    input   [31:0]  data_read,
    input           data_rdy,
    input           sdram_ack,
    output          refresh_en,
    // ROM LOAD
    input   [21:0]  ioctl_addr,
    input   [ 7:0]  ioctl_data,
    input           ioctl_wr,
    output  [21:0]  prog_addr,
    output  [ 7:0]  prog_data,
    output  [ 1:0]  prog_mask,
    output          prog_we,
    output          prog_rd,
    // DIP switches
    input   [31:0]  status,     // only bits 31:16 are looked at
    input           dip_pause,
    input           dip_flip,
    input           dip_test,
    input   [ 1:0]  dip_fxlevel, // Not a DIP on the original PCB    
    // Sound output
    output  signed [15:0] snd,
    output          sample,
    input           enable_psg,
    input           enable_fm,
    // Debug
    input   [3:0]   gfx_en
);

parameter CLK_SPEED=48;

wire [ 8:0] V;
wire [ 8:0] H;
wire        HINIT;

wire [13:1] cpu_AB;
wire        snd_cs, snd2_cs;
wire        char_cs, col_uw, col_lw;
wire        flip;
wire [15:0] char_dout, cpu_dout;
wire        rd, cpu_cen;
wire        char_busy;
wire        service = 1'b1;

// ROM data
wire [15:0] char_data, scr_data, obj_data;
wire [15:0] main_data, map_data;
wire [ 7:0] snd_data, snd2_data;
// MCU interface
wire [ 7:0] snd_din, snd_dout;
wire        snd_mcu_wr;
wire        mcu_brn;
wire [ 7:0] mcu_din, mcu_dout;
wire [16:1] mcu_addr;
wire        mcu_wr, mcu_DMAn, mcu_DMAONn;

// ROM address
wire [17:1] main_addr;
wire [14:0] snd_addr;
wire [15:0] snd2_addr;
wire [13:0] map_addr;
wire [13:0] char_addr;
wire [18:0] scr_addr;
wire [14:0] scr2_addr;
wire [17:0] obj_addr;
wire [ 7:0] dipsw_a, dipsw_b;
wire        cen10, cen10b, cen6b, cenfm, cenp384;

wire        rom_ready;
wire        main_ok, scr_ok, snd_ok, snd2_ok, obj_ok, char_ok;

`ifdef MISTER

reg rst_game;

always @(negedge clk)
    rst_game <= rst || !rom_ready;

`else

reg rst_game=1'b1;

always @(posedge clk) begin : rstgame_gen
    reg rst_aux;
    if( rst || !rom_ready ) begin
        {rst_game,rst_aux} <= 2'b11;
    end
    else begin
        {rst_game,rst_aux} <= {rst_aux, downloading };
    end
end

`endif

wire cen8;

jtgng_cen #(.CLK_SPEED(CLK_SPEED)) u_cen(
    .clk    ( clk       ),
    .cen12  ( cen12     ),
    .cen12b (           ),
    .cen8   ( cen8      ),
    .cen6   ( cen6      ),
    .cen6b  ( cen6b     ),
    .cen3   ( cen3      ),
    .cen1p5 ( cen1p5    )
);

jtgng_cen10 u_cen10(
    .clk    ( clk       ),
    .cen10  ( cen10     ),
    .cen10b ( cen10b    )
);

jtgng_cen3p57 u_cen3p57(
    .clk      ( clk       ),
    .cen_3p57 ( cenfm     ),
    .cen_1p78 (           )     // unused
);

jtgng_cenp384 u_cenp384(
    .clk      ( clk       ),
    .cen_p384 ( cenp384   )
);

jttora_dip u_dip(
    .clk        ( clk           ),
    .status     ( status        ),
    .dip_pause  ( dip_pause     ),
    .dip_test   ( dip_test      ),
    .dip_flip   ( dip_flip      ),
    .dipsw_a    ( dipsw_a       ),
    .dipsw_b    ( dipsw_b       )
);

wire LHBL_obj, LVBL_obj;

jtgng_timer u_timer(
    .clk       ( clk      ),
    .cen6      ( cen6     ),
    .rst       ( rst      ),
    .V         ( V        ),
    .H         ( H        ),
    .Hinit     ( HINIT    ),
    .LHBL      ( LHBL     ),
    .LHBL_obj  ( LHBL_obj ),
    .LVBL      ( LVBL     ),
    .LVBL_obj  ( LVBL_obj ),
    .HS        ( HS       ),
    .VS        ( VS       ),
    .Vinit     (          )
);

wire RnW;
// sound
wire [7:0] snd_latch;

wire        main_cs;
// OBJ
wire OKOUT, blcnten, obj_br, bus_ack;
wire [13:1] obj_AB;     // 1 more bit than older games
wire [15:0] oram_dout;

wire [1:0]  prom_we;
wire        jap;        // high if Japanese ROM was loaded

jttora_dwnld u_dwnld(
    .clk         ( clk             ),
    .downloading ( downloading     ),
    .jap         ( jap             ),

    .ioctl_wr    ( ioctl_wr        ),
    .ioctl_addr  ( ioctl_addr      ),
    .ioctl_data  ( ioctl_data      ),

    .prog_data   ( prog_data       ),
    .prog_mask   ( prog_mask       ),
    .prog_addr   ( prog_addr       ),
    .prog_we     ( prog_we         ),
    .prog_rd     ( prog_rd         ),

    .prom_we     ( prom_we         ),
    .sdram_dout  ( data_read[15:0] ),
    .dwnld_busy  ( dwnld_busy      )
);

wire [15:0] scrposh, scrposv;
wire UDSWn, LDSWn;

`ifndef NOMAIN
jttora_main u_main(
    .rst        ( rst_game      ),
    .clk        ( clk           ),
    .cen10      ( cen10         ),
    .cen10b     ( cen10b        ),
    .cpu_cen    ( cpu_cen       ),
    // Timing
    .flip       ( flip          ),
    .V          ( V             ),
    .LHBL       ( LHBL          ),
    .LVBL       ( LVBL          ),
    // sound
    .snd_latch  ( snd_latch     ),
    // CHAR
    .char_dout  ( char_dout     ),
    .cpu_dout   ( cpu_dout      ),
    .char_cs    ( char_cs       ),
    .char_busy  ( char_busy     ),
    .UDSWn      ( UDSWn         ),
    .LDSWn      ( LDSWn         ),
    // SCROLL 
    .scrposh    ( scrposh       ),
    .scrposv    ( scrposv       ),
    .scr_bank   ( scr_addr[18]  ),
    // OBJ - bus sharing
    .obj_AB     ( obj_AB        ),
    .cpu_AB     ( cpu_AB        ),
    .oram_dout  ( oram_dout     ),
    .OKOUT      ( OKOUT         ),
    .blcnten    ( blcnten       ),
    .obj_br     ( obj_br        ),
    .bus_ack    ( bus_ack       ),
    .col_uw     ( col_uw        ),
    .col_lw     ( col_lw        ),
    // MCU interface
    .mcu_brn    (  mcu_brn      ),
    .mcu_din    (  mcu_din      ),
    .mcu_dout   (  mcu_dout     ),
    .mcu_addr   (  mcu_addr     ),
    .mcu_wr     (  mcu_wr       ),
    .mcu_DMAn   (  mcu_DMAn     ),
    .mcu_DMAONn (  mcu_DMAONn   ),
    // ROM
    .rom_cs     ( main_cs       ),
    .rom_addr   ( main_addr     ),
    .rom_data   ( main_data     ),
    .rom_ok     ( main_ok       ),
    // Cabinet input
    .start_button( start_button ),
    .service     ( service      ),
    .coin_input  ( coin_input   ),
    .joystick1   ( joystick1    ),
    .joystick2   ( joystick2    ),

    .RnW        ( RnW           ),
    // DIP switches
    .dip_pause  ( dip_pause     ),
    .dipsw_a    ( dipsw_a       ),
    .dipsw_b    ( dipsw_b       )
);
`else
    `ifndef SIM_SCR_VPOS
    `define SIM_SCR_HPOS 16'd0
    `define SIM_SCR_VPOS 16'd0
    `define SIM_SCR_BANK 1'b0
    `endif
    `ifndef SIM_SND_LATCH
    `define SIM_SND_LATCH 8'd0
    `endif
    assign main_addr   = 17'd0;
    assign cpu_AB      = 13'd0;
    assign cpu_dout    = 16'd0;
    assign char_cs     = 1'b0;
    assign bus_ack     = 1'b0;
    assign flip        = 1'b0;
    assign RnW         = 1'b1;
    assign scrposh     = `SIM_SCR_HPOS;
    assign scrposv     = `SIM_SCR_VPOS;
    assign scr_addr[18]= `SIM_SCR_BANK;
    assign cpu_cen     = cen12;
    assign OKOUT       = 1'b0;
    assign snd_latch   = `SIM_SND_LATCH;
`endif

`ifdef F1DREAM
`ifndef NOMCU
`define MCU
`endif
`endif

`ifdef MCU
jtbiocom_mcu u_mcu(
    .rst        ( rst_game        ),
    .clk        ( clk             ),
    .cen6a      ( cen6            ),       //  6   MHz
    .cen6b      ( cen6b           ),       //  6   MHz
    // Main CPU interface
    .DMAONn     ( mcu_DMAONn      ),
    .mcu_din    ( mcu_din         ),
    .mcu_dout   ( mcu_dout        ),
    .mcu_wr     ( mcu_wr          ),   // always write to low bytes
    .mcu_addr   ( mcu_addr        ),
    .mcu_brn    ( mcu_brn         ), // RQBSQn
    .DMAn       ( mcu_DMAn        ),

    // Sound CPU interface
    .snd_din    ( snd_din         ),
    .snd_dout   ( snd_dout        ),
    .snd_mcu_wr ( snd_mcu_wr      ),
    // ROM programming
    .prog_addr  ( prog_addr[11:0] ),
    .prom_din   ( prog_data       ),
    .prom_we    ( prom_we[1]      )
);
`else 
assign mcu_DMAn = 1'b1;
assign mcu_brn  = 1'b1;
assign mcu_wr   = 1'b0;
assign mcu_addr = 16'd0;
assign mcu_dout =  8'd0;
`endif


`ifndef NOSOUND
reg [7:0] psg_gain;
always @(posedge clk) begin
    case( dip_fxlevel )
        2'd0: psg_gain <= 8'h1F;
        2'd1: psg_gain <= 8'h3F;
        2'd2: psg_gain <= 8'h7F;
        2'd3: psg_gain <= 8'hFF;
    endcase // dip_fxlevel
end

jttora_sound u_sound (
    .rst            ( rst_game       ),
    .clk            ( clk            ),
    .cen3           ( cen3           ),
    .cenfm          ( cenfm          ),
    .cenp384        ( cenp384        ),
    .jap            ( jap            ),
    // Interface with main CPU
    .snd_latch      ( snd_latch      ),
    // Interface with MCU
    .snd_din        ( snd_din        ),
    .snd_dout       ( snd_dout       ),
    .snd_mcu_wr     ( snd_mcu_wr     ),
    // sound control
    .enable_psg     ( enable_psg     ),
    .enable_fm      ( enable_fm      ),
    .psg_gain       ( psg_gain       ),
    // ROM
    .rom_addr       ( snd_addr       ),
    .rom_data       ( snd_data       ),
    .rom_cs         ( snd_cs         ),
    .rom_ok         ( snd_ok         ),
    // ROM 2
    .rom2_addr      ( snd2_addr      ),
    .rom2_data      ( snd2_data      ),
    .rom2_cs        ( snd2_cs        ),
    .rom2_ok        ( snd2_ok        ),
    // sound output
    .ym_snd         ( snd            ),
    .sample         ( sample         )
);
`else
assign snd_addr  = 15'd0;
assign snd2_addr = 15'd0;
assign snd_cs    = 1'b0;
assign snd2_cs   = 1'b0;
assign snd       = 16'b0;
`endif

reg pause;
always @(posedge clk) pause <= ~dip_pause;

`ifndef NOVIDEO
jttora_video u_video(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen12      ( cen12         ),
    .cen8       ( cen8          ),
    .cen6       ( cen6          ),
    .cpu_cen    ( cpu_cen       ),
    .cpu_AB     ( cpu_AB        ),
    .V          ( V             ),
    .H          ( H             ),
    .RnW        ( RnW           ),
    .UDSWn      ( UDSWn         ),
    .LDSWn      ( LDSWn         ),
    .flip       ( flip          ),
    .cpu_dout   ( cpu_dout      ),
    .pause      ( pause         ),
    // CHAR
    .char_cs    ( char_cs       ),
    .char_dout  ( char_dout     ),
    .char_addr  ( char_addr     ),
    .char_data  ( char_data     ),
    .char_busy  ( char_busy     ),
    .char_ok    ( char_ok       ),
    // SCROLL
    .map_data   ( map_data      ),
    .map_addr   ( map_addr      ),
    .scr_addr   ( scr_addr[17:0]),
    .scr_data   ( scr_data      ),
    .scrposh    ( scrposh       ),
    .scrposv    ( scrposv       ),
    .scr_ok     ( scr_ok        ),
    // OBJ
    .HINIT      ( HINIT         ),
    .obj_AB     ( obj_AB        ),
    .oram_dout  ( oram_dout[11:0] ),
    .obj_addr   ( obj_addr      ),
    .obj_data   ( obj_data      ),
    .OKOUT      ( OKOUT         ),
    .bus_req    ( obj_br        ), // Request bus
    .bus_ack    ( bus_ack       ), // bus acknowledge
    .blcnten    ( blcnten       ), // bus line counter enable
    .col_uw     ( col_uw        ),
    .col_lw     ( col_lw        ),
    .obj_ok     ( obj_ok        ),
    // PROMs
    .prog_addr    ( prog_addr[7:0]),
    .prom_prio_we ( prom_we[0]    ),
    .prom_din     ( prog_data[3:0]),
    // Color Mix
    .LHBL       ( LHBL          ),
    .LVBL       ( LVBL          ),
    .LHBL_obj   ( LHBL_obj      ),
    .LVBL_obj   ( LVBL_obj      ),
    .LHBL_dly   ( LHBL_dly      ),
    .LVBL_dly   ( LVBL_dly      ),
    .gfx_en     ( gfx_en        ),
    // Pixel Output
    .red        ( red           ),
    .green      ( green         ),
    .blue       ( blue          )
);
`else
// Video module may be ommitted for SDRAM load simulation
assign red       = 4'h0;
assign green     = 4'h0;
assign blue      = 4'h0;
assign obj_addr  = 0;
assign scr_addr  = 0;
assign char_addr = 0;
`endif

wire [ 7:0] scr_nc; // no connect
// // CPU addresses memory by words, not bytes:
wire [17:0] main_rom_addr = { main_addr,1'b0 };

// map2 ports are used for the ADPCM CPU (snd2)
jtgng_rom #(
    .main_dw    ( 16              ),
    .main_aw    ( 18              ),
    .char_aw    ( 14              ),
    .obj_aw     ( 18              ),
    .scr1_aw    ( 19              ),
    .snd_offset ( 22'h4_0000 >> 1 ),
    .char_offset( 22'h5_8000 >> 1 ),
    .map1_offset( 22'h6_0000 >> 1 ),
    .snd2_offset( 22'h4_8000 >> 1 ), // second sound CPU
    .scr1_offset( 22'h10_0000     ), // SCR and OBJ are not shifted
    .obj_offset ( 22'h20_0000     )
) u_rom (
    .rst         ( rst           ),
    .clk         ( clk           ),
    .LHBL        ( LHBL          ),
    .LVBL        ( LVBL          ),

    .pause       ( pause         ),
    .main_cs     ( main_cs       ),
    .snd_cs      ( snd_cs        ),
    .snd2_cs     ( snd2_cs       ),
    .main_ok     ( main_ok       ),
    .snd_ok      ( snd_ok        ),
    .snd2_ok     ( snd2_ok       ),
    .scr1_ok     ( scr_ok        ),
    .scr2_ok     (               ),
    .char_ok     ( char_ok       ),
    .obj_ok      ( obj_ok        ),
    .map1_ok     (               ),
    .map2_ok     (               ),

    .char_addr   ( char_addr     ),
    .main_addr   ( main_rom_addr ),
    .snd_addr    ( snd_addr      ),
    .snd2_addr   ( snd2_addr     ),
    .obj_addr    ( obj_addr      ),
    .scr1_addr   ( scr_addr      ),
    .scr2_addr   ( 15'd0         ),
    .map1_addr   ( map_addr      ),
    .map2_addr   ( 14'd0         ),

    .char_dout   ( char_data     ),
    .main_dout   ( main_data     ),
    .snd_dout    ( snd_data      ),
    .snd2_dout   ( snd2_data     ),
    .obj_dout    ( obj_data      ),
    .map1_dout   ( map_data      ),
    .map2_dout   (               ),
    .scr1_dout   ( scr_data      ),
    .scr2_dout   (               ),

    .ready       ( rom_ready     ),
    // SDRAM interface
    .sdram_req   ( sdram_req     ),
    .sdram_ack   ( sdram_ack     ),
    .data_rdy    ( data_rdy      ),
    .downloading ( downloading   ),
    .loop_rst    ( loop_rst      ),
    .sdram_addr  ( sdram_addr    ),
    .data_read   ( data_read     ),
    .refresh_en  ( refresh_en    ),

    .prog_data   ( prog_data     ),
    .prog_mask   ( prog_mask     ),
    .prog_addr   ( prog_addr     ),
    .prog_we     ( prog_we       )
);

endmodule