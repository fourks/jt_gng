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
    Date: 29-10-2019 */

// Converts 4bpp object data from an eight pixel packed format
// to a four pixel format

`timescale 1ns/1ps

module jtgng_obj32(
    input                clk,
    input                downloading,
    input      [15:0]    sdram_dout,

    output reg           convert,
    output reg [21:0]    prog_addr,
    output reg [ 7:0]    prog_data,
    output reg [ 1:0]    prog_mask, // active low
    output reg           prog_we,
    output reg           prog_rd
);

parameter [21:0] OBJ_START=22'h20_0000;
parameter [21:0] OBJ_END  =22'h24_0000;

`ifdef SIMULATION
`ifdef FAST_LOAD
`define JTGNG_OBJ32_FAST
`endif
`endif

`ifdef JTGNG_OBJ32_FAST
localparam OBJ_END1 = OBJ_START+((OBJ_END-OBJ_START)>>6); // make conversion length 32 times shorter
`else
localparam OBJ_END1 = OBJ_END;
`endif
`undef  JTGNG_OBJ32_FAST

reg [31:0] obj_data;
reg [7:0]  sdram_wait;
reg last_down;
reg [7:0]  state;

always @(posedge clk ) begin
    last_down <= downloading;
    if( downloading ) begin
        prog_addr <= 22'd0;
        prog_data <= 8'd0;
        prog_mask <= 2'd0;
        prog_we   <= 1'b0;
        state     <= 8'h1;
        sdram_wait<= 8'hff;
        prog_rd   <= 1'b0;
        convert   <= 1'b0;
    end else begin
        prog_we  <= 1'b0;
        prog_rd  <= 1'b0;
        if( !downloading && last_down ) begin
            prog_addr <= OBJ_START;
            convert   <= 1'b1;
            state     <= 8'h1;
        end
        else if( convert && prog_addr < OBJ_END1 ) begin
            if( !sdram_wait[7] ) begin
                sdram_wait <= { sdram_wait[6:0], 1'b1 };
            end else begin
                state <= state<<1;
                case( state )
                    8'd1: begin // read
                        prog_mask    <= 2'b11;
                        prog_we      <= 1'b0;
                        prog_rd      <= 1'b1;
                        prog_addr[0] <= 1'b0;
                        sdram_wait   <= 8'd0;                        
                    end
                    8'd2: begin
                        obj_data[15:0] <= sdram_dout;
                        prog_mask    <= 2'b11;
                        prog_we      <= 1'b0;
                        prog_rd      <= 1'b1;
                        prog_addr[0] <= 1'b1;
                        sdram_wait   <= 8'd0;                 
                    end
                    8'd4: begin
                        obj_data[31:16] <= sdram_dout;
                    end
                    8'd8: begin
                        prog_addr[0] <= 1'b0;
                        prog_data    <= { obj_data[7+8:4+8], obj_data[7:4]};
                        prog_mask    <= 2'b10;
                        prog_we      <= 1'b1;
                        sdram_wait   <= 8'd0;
                    end
                    8'h10: begin
                        prog_addr[0] <= 1'b0;
                        prog_data <= { obj_data[7+24:4+24], obj_data[7+16:4+16]};
                        prog_mask <= 2'b01;
                        prog_we   <= 1'b1;
                        sdram_wait <= 8'd0;
                    end
                    8'h20: begin
                        prog_addr[0] <= 1'b1;
                        prog_data <= { obj_data[3+8:0+8], obj_data[3:0]};
                        prog_mask <= 2'b10;
                        prog_we   <= 1'b1;
                        sdram_wait <= 8'd0;
                    end
                    8'h40: begin
                        prog_addr[0] <= 1'b1;
                        prog_data <= { obj_data[3+24:0+24], obj_data[3+16:0+16]};
                        prog_mask <= 2'b01;
                        prog_we   <= 1'b1;
                        sdram_wait <= 8'd0;
                    end
                    8'h80: begin
                        prog_addr[21:1] <= prog_addr[21:1]+21'h1;
                        state     <= 8'h1;
                    end
                endcase
            end
        end else convert<=1'b0;
    end
end

endmodule