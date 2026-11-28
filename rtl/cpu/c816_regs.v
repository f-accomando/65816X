// c816_regs.v - registers of the c816 core (docs/design/cpu-core.md, section 3.1).
// The width and emulation rules apply to the next value at every clock, after all write ports:
//   E = 1: P.M = P.X = 1 and S[15:8] = $01;  P.X = 1: X[15:8] = Y[15:8] = 0.
// Priority when two ports write one register: mv_we, wr_en, then ext_we_*, then s_inc / s_dec.
// Instructions of the 65816 that leave page 1 on the stack set s_wide (16-bit stack steps) and
// s_open (keep S[15:8] until the last clock of the instruction).
// An 8-bit write (wr_w16 = 0) changes only bits 7:0 of the register.
// f_we has the mask order N V Z C (bit 3 = N, bit 0 = C). f_we has priority over p_we.
module c816_regs (
  input clk,
  input rst,
  input wr_en,
  input [3:0] wr_sel,
  input [15:0] wr_val,
  input wr_w16,
  input ext_we_a,
  input ext_we_y,
  input [15:0] ext_a,
  input [15:0] ext_y,
  input [3:0] f_we,
  input f_n,
  input f_v,
  input f_z,
  input f_c,
  input p_we,
  input [7:0] p_val,
  input e_we,
  input e_val,
  input pc_we,
  input [15:0] pc_val,
  input pbr_we,
  input [7:0] pbr_val,
  input s_inc,
  input s_dec,
  input s_wide,
  input s_open,
  input mv_we,
  input [15:0] mv_a,
  input [15:0] mv_x,
  input [15:0] mv_y,
  input [7:0] mv_dbr,
  output reg [15:0] a, x, y, s, d, pc,
  output reg [7:0] pbr, dbr, p,
  output reg e
);
  reg [15:0] a_n, x_n, y_n, s_n, d_n;
  reg [7:0] p_n, dbr_n;
  reg e_n;
  wire [15:0] wlo_a = {a[15:8], wr_val[7:0]};
  wire [15:0] wlo_x = {x[15:8], wr_val[7:0]};
  wire [15:0] wlo_y = {y[15:8], wr_val[7:0]};
  wire [15:0] wlo_s = {s[15:8], wr_val[7:0]};
  wire [15:0] wlo_d = {d[15:8], wr_val[7:0]};

  always @* begin
    a_n = a;
    x_n = x;
    y_n = y;
    s_n = s;
    d_n = d;
    p_n = p;
    e_n = e;
    dbr_n = dbr;
    // stack pointer: in emulation mode only S[7:0] changes, except in a wide instruction
    if (s_inc) s_n = (e && !s_wide) ? {s[15:8], s[7:0] + 8'd1} : s + 16'd1;
    if (s_dec) s_n = (e && !s_wide) ? {s[15:8], s[7:0] - 8'd1} : s - 16'd1;
    if (ext_we_a) a_n = ext_a;
    if (ext_we_y) y_n = ext_y;
    if (wr_en) begin
      case (wr_sel)
        4'd1: a_n = wr_w16 ? wr_val : wlo_a;
        4'd2: x_n = wr_w16 ? wr_val : wlo_x;
        4'd3: y_n = wr_w16 ? wr_val : wlo_y;
        4'd4: s_n = wr_w16 ? wr_val : wlo_s;
        4'd5: d_n = wr_w16 ? wr_val : wlo_d;
        4'd7: dbr_n = wr_val[7:0];
        default: ;
      endcase
    end
    if (mv_we) begin
      a_n = mv_a;
      x_n = mv_x;
      y_n = mv_y;
      dbr_n = mv_dbr;
    end
    if (p_we) p_n = p_val;
    if (f_we[3]) p_n[7] = f_n;
    if (f_we[2]) p_n[6] = f_v;
    if (f_we[1]) p_n[1] = f_z;
    if (f_we[0]) p_n[0] = f_c;
    if (e_we) e_n = e_val;
    // width and emulation rules
    if (e_n) begin
      p_n[5] = 1'b1;
      p_n[4] = 1'b1;
      if (!s_open) s_n[15:8] = 8'h01;
    end
    if (p_n[4]) begin
      x_n[15:8] = 8'h00;
      y_n[15:8] = 8'h00;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      a <= 16'h0000;
      x <= 16'h0000;
      y <= 16'h0000;
      s <= 16'h01FF;
      d <= 16'h0000;
      pc <= 16'h0000;
      pbr <= 8'h00;
      dbr <= 8'h00;
      p <= 8'h34;
      e <= 1'b1;
    end else begin
      a <= a_n;
      x <= x_n;
      y <= y_n;
      s <= s_n;
      d <= d_n;
      p <= p_n;
      e <= e_n;
      dbr <= dbr_n;
      if (pc_we) pc <= pc_val;
      if (pbr_we) pbr <= pbr_val;
    end
  end
endmodule
