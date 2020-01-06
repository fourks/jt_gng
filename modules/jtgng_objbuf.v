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
    Date: 11-1-2019 */

// Original hardware had at least two variants:
// 24 sprites per line: GnG, Commando... the buffer ran at 6MHz
// 32 sprites per line: Tiger Road, Bionic Commando... ran at 8MHz

module jtgng_objbuf #(parameter
    DW          = 8,
    AW          = 9,
    OBJMAX      = 10'h180, // 180h for 96 objects (GnG) 
    OBJMAX_LINE = 6'd24
) (
    input               rst,
    input               clk,
    (*direct_enable*) input draw_cen,
    // screen
    input               HINIT_draw,
    input               LVBL,
    input       [7:0]   V,
    output reg  [7:0]   VF,
    input               flip,
    // sprite data scan
    output reg [AW-1:0] pre_scan,
    input      [DW-1:0] dma_dout,
    // sprite data buffer
    output reg [DW-1:0] objbuf_data,
    input       [4:0]   objcnt,
    input       [3:0]   pxlcnt,
    input               rom_wait,
    output reg          line
);

// sprite buffer
reg          fill;
reg  [5:0]   post_scan;
reg          line_obj_we;

localparam lineA=1'b0, lineB=1'b1;
wire [DW-1:0] q_a, q_b;
wire [6:0] hscan = { objcnt, pxlcnt[1:0] };

reg trf_state;

localparam SEARCH=1'b0, TRANSFER=1'b1;

always @(posedge clk, posedge rst) begin
    if( rst )
        line <= lineA;
    else if(draw_cen) begin
        if( HINIT_draw ) begin
            VF <= {8{flip}} ^ V;
            line <= ~line;
        end
    end
end

reg pre_scan_msb;

reg [8:0] Vsum;
reg       MATCH;
localparam BIT8 = DW-4; // This will be 8 when DW==12. (Verilator workaround)

always @(*) begin
    Vsum  = {1'b0, dma_dout[7:0]} + {1'b0,(~VF + { {6{~flip}}, 2'b10 })};
    MATCH = DW==8 ? (&Vsum[7:4]) // 8-bit games: GnG, GunSmoke...
        : ( &{ ~^{dma_dout[BIT8],Vsum[8]}, Vsum[7:4] } ); // 16-bit games: Tora, Biocom...
end

localparam DMAEND = OBJMAX-4;
wire dmaend = {pre_scan_msb,pre_scan}>=DMAEND;
wire [5:0] objcnt_end = OBJMAX_LINE-6'd1;

always @(posedge clk, posedge rst)
    if( rst ) begin
        trf_state <= SEARCH;
        line_obj_we <= 1'b0;
    end
    else if(draw_cen) begin
        case( trf_state )
            SEARCH: begin
                line_obj_we <= 1'b0;
                if( !LVBL || fill || dmaend ) begin
                    {pre_scan_msb, pre_scan} <= 2;
                    post_scan<= 6'd0; // store obj data in reverse order
                    // so we can print them in straight order while taking
                    // advantage of horizontal blanking to avoid graphic clash
                    fill <= ~HINIT_draw;
                end
                else begin
                    //if( dma_dout<=(VF+'d3) && (dma_dout+8'd12)>=VF  ) begin
                    if( MATCH ) begin
                        pre_scan[1:0] <= 2'd0;
                        line_obj_we <= 1'b1;
                        trf_state <= TRANSFER;
                    end
                    else begin
                        if( dmaend ) begin
                            fill <= 1'b1;
                        end else begin
                            {pre_scan_msb,pre_scan} <= {pre_scan_msb,pre_scan} + 4;
                        end
                    end
                end
            end
            TRANSFER: begin
                // line_obj_we <= 1'b0;
                if( pre_scan[1:0]==2'b11 ) begin
                    if( post_scan == objcnt_end ) begin // Transfer done before the end of the line
                        line_obj_we <= 1'b0;
                        trf_state <= SEARCH;
                        fill <= 1'd1;
                    end else begin
                        post_scan <= post_scan+1'b1;
                        pre_scan <= pre_scan + 3;
                        trf_state  <= SEARCH;
                        line_obj_we <= 1'b0;
                    end
                end
                else begin
                    pre_scan[1:0] <= pre_scan[1:0]+1'b1;
                end
            end
        endcase
    end

reg [6:0] address_a, address_b;
reg we_a, we_b;
reg [DW-1:0] data_a, data_b;

reg [2:0] we_clr;
always @(posedge clk, posedge rst) begin
    if( rst ) we_clr <= 3'b0;
    else begin
        we_clr <= { we_clr[1:0], draw_cen & ~rom_wait};
        if( we_clr[1] ) objbuf_data <= line==lineA ? q_b : q_a;
    end
end

always @(*) begin
    if( line == lineA ) begin
        address_a = { ~post_scan[4:0], pre_scan[1:0] };
        address_b = hscan;
        data_a    = dma_dout;
        data_b    = 8'hf8;
        we_a      = line_obj_we;
        we_b      = we_clr[2];
    end
    else begin
        address_a = hscan;
        address_b = { ~post_scan[4:0], pre_scan[1:0] };
        data_a    = 8'hf8;
        data_b    = dma_dout;
        we_a      = we_clr[2];
        we_b      = line_obj_we;
    end
end

jtframe_ram #(.aw(7),.dw(DW)/*,.simfile("obj_buf.hex")*/) objbuf_a(
    .clk   ( clk       ),
    .cen   ( 1'b1      ),
    .addr  ( address_a ),
    .data  ( data_a    ),
    .we    ( we_a      ),
    .q     ( q_a       )
);

jtframe_ram #(.aw(7),.dw(DW)/*,.simfile("obj_buf.hex")*/) objbuf_b(
    .clk   ( clk       ),
    .cen   ( 1'b1      ),
    .addr  ( address_b ),
    .data  ( data_b    ),
    .we    ( we_b      ),
    .q     ( q_b       )
);


endmodule // jtgng_objbuf