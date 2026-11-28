// ppu_timing.v - the line and frame timing of the SNES video chips.
// The master clock is not a clock net: it is the enable "mce", one clk pulse for each master clock.
// A dot lasts 4 master clocks. A line has 340 dots, and dots 323 and 327 last 6 (1364 clocks).
// One line of NTSC without interlace (field 1, line 240) has no long dot: 1360 clocks.
// One line of PAL with interlace (field 1, line 311) has one more dot: 1368 clocks.
// A frame has 262 lines (NTSC) or 312 (PAL); with interlace, field 0 has one line more.
// Sources and open points: docs/design/ppu-plan.md, section 1.5.
module ppu_timing (
  input clk,
  input rst,
  input mce,                    // master clock enable
  input pal,                    // 0 = NTSC, 1 = PAL
  input interlace,              // $2133 bit 0
  input overscan,               // $2133 bit 2
  output reg [10:0] hclk,       // master clock in the line, 0 to 1367
  output reg [8:0] hdot,        // dot in the line, 0 to 340
  output reg [8:0] vcnt,        // line in the frame, 0 to 312
  output reg field,             // changes in each frame, after dot 0 of line 0
  output reg dot_en,            // one clk pulse: first clk of a new dot
  output hblank,                // dots 274 to 339 (or 340), and dot 0
  output reg vblank,            // from line 225 (240 with overscan) to the end of the frame
  output reg frame_start        // one clk pulse: first clk of line 0
);
  reg [2:0] dcnt;               // master clock in the dot

  wire short_line = !pal && !interlace && field && (vcnt == 9'd240);
  wire long_line  = pal && interlace && field && (vcnt == 9'd311);

  wire long_dot = ((hdot == 9'd323) || (hdot == 9'd327)) && !short_line;
  wire [2:0] dlast = long_dot ? 3'd5 : 3'd3;
  wire [8:0] hlast = long_line ? 9'd340 : 9'd339;

  wire extra = interlace && !field;
  wire [8:0] vlast = (pal ? 9'd311 : 9'd261) + {8'd0, extra};

  // ">=" and not "==": a change of the inputs in the middle of a frame cannot lose a counter.
  wire dot_end = (dcnt >= dlast);
  wire line_end = dot_end && (hdot >= hlast);
  wire [8:0] vnext = (vcnt >= vlast) ? 9'd0 : (vcnt + 9'd1);
  wire [8:0] vfirst = overscan ? 9'd240 : 9'd225;

  assign hblank = (hdot >= 9'd274) || (hdot == 9'd0);

  always @(posedge clk) begin
    dot_en <= 1'b0;
    frame_start <= 1'b0;
    if (rst) begin
      dcnt <= 3'd0; hclk <= 11'd0; hdot <= 9'd0; vcnt <= 9'd0; vblank <= 1'b0;
      field <= 1'b1;            // thus the first frame after reset is field 0 from its dot 1
    end else if (mce) begin
      if (dot_end) begin
        dcnt <= 3'd0;
        dot_en <= 1'b1;
        if ((hdot == 9'd0) && (vcnt == 9'd0)) field <= !field;
        if (line_end) begin
          hclk <= 11'd0;
          hdot <= 9'd0;
          vcnt <= vnext;
          if (vnext == 9'd0) begin
            vblank <= 1'b0;
            frame_start <= 1'b1;
          end else if (vnext >= vfirst) vblank <= 1'b1;
        end else begin
          hclk <= hclk + 11'd1;
          hdot <= hdot + 9'd1;
        end
      end else begin
        dcnt <= dcnt + 3'd1;
        hclk <= hclk + 11'd1;
      end
    end
  end
endmodule
