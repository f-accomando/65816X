// cpu65816x.v - core "65816X-lite": sottoinsieme del 65816 + estensioni WDM
// Bus a 8 bit come l'originale. Ogni lettura costa 2 cicli (ph=0 invia indirizzo,
// ph=1 cattura il dato registrato dalla memoria). Le scritture costano 1 ciclo.
// Limiti noti: niente interrupt/NMI, modalita' decimale assente, set di opcode ridotto,
// opcode sconosciuti trattati come NOP, tempi NON cycle-accurate.
module cpu65816x (
  input clk,
  input rst,
  input halt,
  output reg [23:0] addr,
  output reg rd,
  output reg wr,
  output reg [7:0] wdata,
  input [7:0] din,
  output [15:0] dbg_pc,
  output [15:0] dbg_a,
  output [15:0] dbg_x,
  output [15:0] dbg_y
);
  localparam ST_FETCH = 4'd0;
  localparam ST_OPR   = 4'd1;
  localparam ST_EA    = 4'd2;
  localparam ST_DRD   = 4'd3;
  localparam ST_DWR   = 4'd4;
  localparam ST_EXEC  = 4'd5;
  localparam ST_PUSH  = 4'd6;
  localparam ST_PULL  = 4'd7;
  localparam ST_RST   = 4'd8;

  localparam CL_IMPL  = 4'd0;
  localparam CL_IMM8  = 4'd1;
  localparam CL_IMMM  = 4'd2;
  localparam CL_IMMX  = 4'd3;
  localparam CL_ABS   = 4'd4;
  localparam CL_ABSX  = 4'd5;
  localparam CL_LONG  = 4'd6;
  localparam CL_REL   = 4'd7;
  localparam CL_JABS  = 4'd8;
  localparam CL_JLONG = 4'd9;

  reg [3:0] st;
  reg ph;
  reg [1:0] n;
  reg [1:0] nops;
  reg [15:0] a, x, y, s, pc, tmp, wval;
  reg [7:0] pb, db, op, o0, o1, o2;
  reg [23:0] ea;
  reg [31:0] acc;
  reg fn, fv, fm, fx, fi, fz, fc, fe;

  reg [16:0] sum17;
  reg [8:0] sum9;
  reg [15:0] r16;
  reg [7:0] r8;
  reg [31:0] prod;

  assign dbg_pc = pc;
  assign dbg_a = a;
  assign dbg_x = x;
  assign dbg_y = y;

  // ---- decodifica (da din durante il fetch, da op dopo) ----
  reg [7:0] dec_in;
  reg [3:0] dcls;
  reg dst;
  reg dxy;
  always @* begin
    dec_in = (st == ST_FETCH) ? din : op;
    dcls = CL_IMPL;
    dst = 1'b0;
    dxy = 1'b0;
    case (dec_in)
      8'hC2, 8'hE2, 8'h42: dcls = CL_IMM8;
      8'hA9, 8'h69, 8'hE9, 8'hC9, 8'h29, 8'h09, 8'h49: dcls = CL_IMMM;
      8'hA2, 8'hA0: begin dcls = CL_IMMX; dxy = 1'b1; end
      8'hAD, 8'h6D, 8'hCD: dcls = CL_ABS;
      8'h8D: begin dcls = CL_ABS; dst = 1'b1; end
      8'hAE, 8'hAC: begin dcls = CL_ABS; dxy = 1'b1; end
      8'h8E, 8'h8C: begin dcls = CL_ABS; dst = 1'b1; dxy = 1'b1; end
      8'hBD: dcls = CL_ABSX;
      8'h9D: begin dcls = CL_ABSX; dst = 1'b1; end
      8'hAF: dcls = CL_LONG;
      8'h8F: begin dcls = CL_LONG; dst = 1'b1; end
      8'h80, 8'hD0, 8'hF0, 8'h90, 8'hB0, 8'h10, 8'h30: dcls = CL_REL;
      8'h4C, 8'h20: dcls = CL_JABS;
      8'h5C: dcls = CL_JLONG;
      default: dcls = CL_IMPL;
    endcase
  end

  reg [1:0] onum;
  always @* begin
    case (dcls)
      CL_IMM8, CL_REL: onum = 2'd1;
      CL_IMMM: onum = fm ? 2'd1 : 2'd2;
      CL_IMMX: onum = fx ? 2'd1 : 2'd2;
      CL_ABS, CL_ABSX, CL_JABS: onum = 2'd2;
      CL_LONG, CL_JLONG: onum = 2'd3;
      default: onum = 2'd0;
    endcase
  end

  wire dwide = dxy ? !fx : !fm;
  wire isimm = (dcls == CL_IMMM) || (dcls == CL_IMMX);
  wire [15:0] val = isimm ? {o1, o0} : tmp;

  // ---- bus (combinatorio dallo stato) ----
  always @* begin
    addr = 24'h000000;
    rd = 1'b0;
    wr = 1'b0;
    wdata = 8'h00;
    case (st)
      ST_RST:   begin addr = n[0] ? 24'h00FFFD : 24'h00FFFC; rd = (ph == 1'b0); end
      ST_FETCH: begin addr = {pb, pc}; rd = (ph == 1'b0) && !halt; end
      ST_OPR:   begin addr = {pb, pc}; rd = (ph == 1'b0); end
      ST_DRD:   begin addr = ea + {22'd0, n}; rd = (ph == 1'b0); end
      ST_DWR:   begin addr = ea + {22'd0, n}; wr = 1'b1; wdata = n[0] ? wval[15:8] : wval[7:0]; end
      ST_PUSH:  begin addr = {8'h00, s}; wr = 1'b1; wdata = n[0] ? wval[15:8] : wval[7:0]; end
      ST_PULL:  begin addr = {8'h00, s + 16'd1}; rd = (ph == 1'b0); end
      default: ;
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      st <= ST_RST; ph <= 1'b0; n <= 2'd0; nops <= 2'd0;
      a <= 16'd0; x <= 16'd0; y <= 16'd0; s <= 16'h01FF; pc <= 16'd0;
      tmp <= 16'd0; wval <= 16'd0; ea <= 24'd0; acc <= 32'd0;
      pb <= 8'd0; db <= 8'd0; op <= 8'd0; o0 <= 8'd0; o1 <= 8'd0; o2 <= 8'd0;
      fn <= 1'b0; fv <= 1'b0; fm <= 1'b1; fx <= 1'b1; fi <= 1'b1; fz <= 1'b0; fc <= 1'b0; fe <= 1'b1;
    end else begin
      case (st)
        ST_RST: begin
          if (ph == 1'b0) ph <= 1'b1;
          else begin
            ph <= 1'b0;
            if (n[0] == 1'b0) begin pc[7:0] <= din; n <= 2'd1; end
            else begin pc[15:8] <= din; n <= 2'd0; st <= ST_FETCH; end
          end
        end

        ST_FETCH: begin
          if (!halt) begin
            if (ph == 1'b0) ph <= 1'b1;
            else begin
              ph <= 1'b0; op <= din; pc <= pc + 16'd1; n <= 2'd0; nops <= onum;
              o0 <= 8'h00; o1 <= 8'h00; o2 <= 8'h00;
              if (dcls == CL_IMPL) st <= ST_EXEC; else st <= ST_OPR;
            end
          end
        end

        ST_OPR: begin
          if (ph == 1'b0) ph <= 1'b1;
          else begin
            ph <= 1'b0; pc <= pc + 16'd1;
            if (n == 2'd0) o0 <= din;
            else if (n == 2'd1) o1 <= din;
            else o2 <= din;
            if (n + 2'd1 == nops) begin
              n <= 2'd0;
              case (dcls)
                CL_ABS, CL_ABSX, CL_LONG: st <= ST_EA;
                default: st <= ST_EXEC;
              endcase
            end else n <= n + 2'd1;
          end
        end

        ST_EA: begin
          case (dcls)
            CL_ABS:  ea <= {db, o1, o0};
            CL_ABSX: ea <= {db, o1, o0} + {8'h00, x};
            default: ea <= {o2, o1, o0};
          endcase
          case (op)
            8'h8D, 8'h9D, 8'h8F: wval <= a;
            8'h8E: wval <= x;
            default: wval <= y;
          endcase
          n <= 2'd0; ph <= 1'b0;
          if (dst) st <= ST_DWR; else st <= ST_DRD;
        end

        ST_DRD: begin
          if (ph == 1'b0) ph <= 1'b1;
          else begin
            ph <= 1'b0;
            if (n == 2'd0) begin
              tmp[7:0] <= din; tmp[15:8] <= 8'h00;
              if (dwide) n <= 2'd1; else st <= ST_EXEC;
            end else begin
              tmp[15:8] <= din; n <= 2'd0; st <= ST_EXEC;
            end
          end
        end

        ST_DWR: begin
          if (n == 2'd0 && dwide) n <= 2'd1;
          else begin n <= 2'd0; st <= ST_FETCH; end
        end

        ST_PUSH: begin
          s <= s - 16'd1;
          if (n == 2'd0) begin
            st <= ST_FETCH;
            if (op == 8'h20) pc <= {o1, o0};
          end else n <= n - 2'd1;
        end

        ST_PULL: begin
          if (ph == 1'b0) ph <= 1'b1;
          else begin
            ph <= 1'b0; s <= s + 16'd1;
            if (n == 2'd0) tmp[7:0] <= din; else tmp[15:8] <= din;
            if (n + 2'd1 == nops) begin
              n <= 2'd0; st <= ST_FETCH;
              if (op == 8'h60) pc <= {din, tmp[7:0]} + 16'd1;
              else begin
                if (fm) begin a[7:0] <= din; fz <= (din == 8'h00); fn <= din[7]; end
                else begin a <= {din, tmp[7:0]}; fz <= ({din, tmp[7:0]} == 16'h0000); fn <= din[7]; end
              end
            end else n <= n + 2'd1;
          end
        end

        ST_EXEC: begin
          st <= ST_FETCH; ph <= 1'b0; n <= 2'd0;
          case (op)
            // ---- caricamenti ----
            8'hA9, 8'hAD, 8'hBD, 8'hAF: begin
              if (fm) begin a[7:0] <= val[7:0]; fz <= (val[7:0] == 8'h00); fn <= val[7]; end
              else begin a <= val; fz <= (val == 16'h0000); fn <= val[15]; end
            end
            8'hA2, 8'hAE: begin
              if (fx) begin x <= {8'h00, val[7:0]}; fz <= (val[7:0] == 8'h00); fn <= val[7]; end
              else begin x <= val; fz <= (val == 16'h0000); fn <= val[15]; end
            end
            8'hA0, 8'hAC: begin
              if (fx) begin y <= {8'h00, val[7:0]}; fz <= (val[7:0] == 8'h00); fn <= val[7]; end
              else begin y <= val; fz <= (val == 16'h0000); fn <= val[15]; end
            end
            // ---- aritmetica ----
            8'h69, 8'h6D: begin
              if (fm) begin
                sum9 = {1'b0, a[7:0]} + {1'b0, val[7:0]} + {8'h00, fc};
                a[7:0] <= sum9[7:0]; fc <= sum9[8]; fz <= (sum9[7:0] == 8'h00); fn <= sum9[7];
                fv <= (~(a[7] ^ val[7])) & (a[7] ^ sum9[7]);
              end else begin
                sum17 = {1'b0, a} + {1'b0, val} + {16'h0000, fc};
                a <= sum17[15:0]; fc <= sum17[16]; fz <= (sum17[15:0] == 16'h0000); fn <= sum17[15];
                fv <= (~(a[15] ^ val[15])) & (a[15] ^ sum17[15]);
              end
            end
            8'hE9: begin
              if (fm) begin
                sum9 = {1'b0, a[7:0]} + {1'b0, ~val[7:0]} + {8'h00, fc};
                a[7:0] <= sum9[7:0]; fc <= sum9[8]; fz <= (sum9[7:0] == 8'h00); fn <= sum9[7];
                fv <= (a[7] ^ val[7]) & (a[7] ^ sum9[7]);
              end else begin
                sum17 = {1'b0, a} + {1'b0, ~val} + {16'h0000, fc};
                a <= sum17[15:0]; fc <= sum17[16]; fz <= (sum17[15:0] == 16'h0000); fn <= sum17[15];
                fv <= (a[15] ^ val[15]) & (a[15] ^ sum17[15]);
              end
            end
            8'hC9, 8'hCD: begin
              if (fm) begin
                sum9 = {1'b0, a[7:0]} + {1'b0, ~val[7:0]} + 9'd1;
                fc <= sum9[8]; fz <= (sum9[7:0] == 8'h00); fn <= sum9[7];
              end else begin
                sum17 = {1'b0, a} + {1'b0, ~val} + 17'd1;
                fc <= sum17[16]; fz <= (sum17[15:0] == 16'h0000); fn <= sum17[15];
              end
            end
            8'h29: begin
              if (fm) begin r8 = a[7:0] & val[7:0]; a[7:0] <= r8; fz <= (r8 == 8'h00); fn <= r8[7]; end
              else begin r16 = a & val; a <= r16; fz <= (r16 == 16'h0000); fn <= r16[15]; end
            end
            8'h09: begin
              if (fm) begin r8 = a[7:0] | val[7:0]; a[7:0] <= r8; fz <= (r8 == 8'h00); fn <= r8[7]; end
              else begin r16 = a | val; a <= r16; fz <= (r16 == 16'h0000); fn <= r16[15]; end
            end
            8'h49: begin
              if (fm) begin r8 = a[7:0] ^ val[7:0]; a[7:0] <= r8; fz <= (r8 == 8'h00); fn <= r8[7]; end
              else begin r16 = a ^ val; a <= r16; fz <= (r16 == 16'h0000); fn <= r16[15]; end
            end
            // ---- incrementi, trasferimenti ----
            8'hE8: begin
              if (fx) begin r8 = x[7:0] + 8'd1; x <= {8'h00, r8}; fz <= (r8 == 8'h00); fn <= r8[7]; end
              else begin r16 = x + 16'd1; x <= r16; fz <= (r16 == 16'h0000); fn <= r16[15]; end
            end
            8'hCA: begin
              if (fx) begin r8 = x[7:0] - 8'd1; x <= {8'h00, r8}; fz <= (r8 == 8'h00); fn <= r8[7]; end
              else begin r16 = x - 16'd1; x <= r16; fz <= (r16 == 16'h0000); fn <= r16[15]; end
            end
            8'hC8: begin
              if (fx) begin r8 = y[7:0] + 8'd1; y <= {8'h00, r8}; fz <= (r8 == 8'h00); fn <= r8[7]; end
              else begin r16 = y + 16'd1; y <= r16; fz <= (r16 == 16'h0000); fn <= r16[15]; end
            end
            8'h88: begin
              if (fx) begin r8 = y[7:0] - 8'd1; y <= {8'h00, r8}; fz <= (r8 == 8'h00); fn <= r8[7]; end
              else begin r16 = y - 16'd1; y <= r16; fz <= (r16 == 16'h0000); fn <= r16[15]; end
            end
            8'h1A: begin
              if (fm) begin r8 = a[7:0] + 8'd1; a[7:0] <= r8; fz <= (r8 == 8'h00); fn <= r8[7]; end
              else begin r16 = a + 16'd1; a <= r16; fz <= (r16 == 16'h0000); fn <= r16[15]; end
            end
            8'h3A: begin
              if (fm) begin r8 = a[7:0] - 8'd1; a[7:0] <= r8; fz <= (r8 == 8'h00); fn <= r8[7]; end
              else begin r16 = a - 16'd1; a <= r16; fz <= (r16 == 16'h0000); fn <= r16[15]; end
            end
            8'hAA: begin
              if (fx) begin x <= {8'h00, a[7:0]}; fz <= (a[7:0] == 8'h00); fn <= a[7]; end
              else begin x <= a; fz <= (a == 16'h0000); fn <= a[15]; end
            end
            8'hA8: begin
              if (fx) begin y <= {8'h00, a[7:0]}; fz <= (a[7:0] == 8'h00); fn <= a[7]; end
              else begin y <= a; fz <= (a == 16'h0000); fn <= a[15]; end
            end
            8'h8A: begin
              if (fm) begin a[7:0] <= x[7:0]; fz <= (x[7:0] == 8'h00); fn <= x[7]; end
              else begin a <= x; fz <= (x == 16'h0000); fn <= x[15]; end
            end
            8'h98: begin
              if (fm) begin a[7:0] <= y[7:0]; fz <= (y[7:0] == 8'h00); fn <= y[7]; end
              else begin a <= y; fz <= (y == 16'h0000); fn <= y[15]; end
            end
            // ---- flag e modo ----
            8'h18: fc <= 1'b0;
            8'h38: fc <= 1'b1;
            8'h78: fi <= 1'b1;
            8'h58: fi <= 1'b0;
            8'hFB: begin
              fc <= fe; fe <= fc;
              if (fc) begin fm <= 1'b1; fx <= 1'b1; x[15:8] <= 8'h00; y[15:8] <= 8'h00; end
            end
            8'hC2: begin
              if (o0[7]) fn <= 1'b0;
              if (o0[6]) fv <= 1'b0;
              if (o0[5] & !fe) fm <= 1'b0;
              if (o0[4] & !fe) fx <= 1'b0;
              if (o0[2]) fi <= 1'b0;
              if (o0[1]) fz <= 1'b0;
              if (o0[0]) fc <= 1'b0;
            end
            8'hE2: begin
              if (o0[7]) fn <= 1'b1;
              if (o0[6]) fv <= 1'b1;
              if (o0[5]) fm <= 1'b1;
              if (o0[4]) begin fx <= 1'b1; x[15:8] <= 8'h00; y[15:8] <= 8'h00; end
              if (o0[2]) fi <= 1'b1;
              if (o0[1]) fz <= 1'b1;
              if (o0[0]) fc <= 1'b1;
            end
            // ---- salti ----
            8'h80: pc <= pc + {{8{o0[7]}}, o0};
            8'hD0: if (!fz) pc <= pc + {{8{o0[7]}}, o0};
            8'hF0: if (fz) pc <= pc + {{8{o0[7]}}, o0};
            8'h90: if (!fc) pc <= pc + {{8{o0[7]}}, o0};
            8'hB0: if (fc) pc <= pc + {{8{o0[7]}}, o0};
            8'h10: if (!fn) pc <= pc + {{8{o0[7]}}, o0};
            8'h30: if (fn) pc <= pc + {{8{o0[7]}}, o0};
            8'h4C: pc <= {o1, o0};
            8'h5C: begin pc <= {o1, o0}; pb <= o2; end
            8'h20: begin wval <= pc - 16'd1; n <= 2'd1; st <= ST_PUSH; end
            8'h60: begin n <= 2'd0; nops <= 2'd2; st <= ST_PULL; end
            8'h48: begin wval <= a; n <= fm ? 2'd0 : 2'd1; st <= ST_PUSH; end
            8'h68: begin n <= 2'd0; nops <= fm ? 2'd1 : 2'd2; st <= ST_PULL; end
            // ---- estensioni enhanced: WDM #sub (assumono A e X a 16 bit) ----
            8'h42: begin
              case (o0)
                8'h01: begin
                  prod = {16'h0000, a} * {16'h0000, x};
                  a <= prod[15:0]; y <= prod[31:16]; fz <= (prod == 32'd0); fn <= prod[31];
                end
                8'h02: begin
                  if (x == 16'h0000) begin a <= 16'hFFFF; y <= a; fv <= 1'b1; end
                  else begin a <= a / x; y <= a % x; fv <= 1'b0; end
                end
                8'h03: begin
                  prod = {16'h0000, a} * {16'h0000, x};
                  acc <= acc + prod;
                end
                8'h04: begin a <= acc[15:0]; y <= acc[31:16]; end
                8'h05: acc <= 32'd0;
                default: ;
              endcase
            end
            default: ;
          endcase
        end

        default: st <= ST_FETCH;
      endcase
    end
  end
endmodule
