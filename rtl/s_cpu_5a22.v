// s_cpu_5a22.v - equivalente del Ricoh 5A22: core + registri $42xx + DMA ($43xx)
// Moltiplicazione e divisione: un bit per ciclo di CPU, 8 e 16 cicli come l'originale; il
// risultato letto prima e' quello parziale. Semplificazioni:
// DMA generale con modi 0-7 (niente HDMA), registri joypad assenti.
module s_cpu_5a22 (
  input clk,
  input rst,
  input ext_en,
  output [23:0] bus_addr,
  output bus_rd,
  output bus_wr,
  output [7:0] bus_wdata,
  input [7:0] bus_rdata,
  input vblank,
  output reg [7:0] regs_rdata,
  output regs_hit,
  output [15:0] dbg_pc,
  output [15:0] dbg_a,
  output [15:0] dbg_x,
  output [15:0] dbg_y,
  output dbg_illegal
);
  wire [23:0] c_addr;
  wire c_rd, c_wr;
  wire [7:0] c_wdata;
  reg dma_pending, dma_active;
  wire halt = dma_pending | dma_active;

  // the core stops at the next CPU cycle while halt = 1, also inside an instruction
  wire c_vda, c_vpa, c_sync, c_cyc_end;
  c816_core u_core (
    .clk(clk), .rst(rst), .halt(halt), .bus_wait(1'b0), .ext_en(ext_en), .nmi(nmi_flag && nmitimen[7]), .irq(1'b0),
    .din(bus_rdata), .addr(c_addr), .rd(c_rd), .wr(c_wr), .wdata(c_wdata),
    .vda(c_vda), .vpa(c_vpa), .sync(c_sync), .cyc_end(c_cyc_end), .dbg_illegal(dbg_illegal),
    .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_x(dbg_x), .dbg_y(dbg_y)
  );

  // ---- registri DMA per canale ----
  reg [7:0] d_ctrl [0:7];
  reg [7:0] d_b    [0:7];
  reg [7:0] d_al   [0:7];
  reg [7:0] d_ah   [0:7];
  reg [7:0] d_ab   [0:7];
  reg [7:0] d_cl   [0:7];
  reg [7:0] d_ch   [0:7];
  reg [7:0] mdmaen, hdmaen, nmitimen;
  reg [2:0] dch;
  reg dph;
  reg [1:0] dpat;

  wire [7:0] cur_ctrl = d_ctrl[dch];
  wire [7:0] cur_b = d_b[dch];
  wire [23:0] a_addr = {d_ab[dch], d_ah[dch], d_al[dch]};
  wire [15:0] cnt_cur = {d_ch[dch], d_cl[dch]};
  wire [15:0] a_next = cur_ctrl[4] ? ({d_ah[dch], d_al[dch]} - 16'd1) : ({d_ah[dch], d_al[dch]} + 16'd1);
  wire [15:0] cnt_next = cnt_cur - 16'd1;

  reg [7:0] boff;
  always @* begin
    case (cur_ctrl[2:0])
      3'd1: boff = {7'd0, dpat[0]};
      3'd3, 3'd7: boff = {7'd0, dpat[1]};
      3'd4: boff = {6'd0, dpat};
      3'd5: boff = {7'd0, dpat[0]};
      default: boff = 8'd0;
    endcase
  end
  wire [23:0] b_addr = 24'h002100 + {16'h0000, cur_b + boff};

  reg [23:0] d_addr;
  reg d_rd, d_wr;
  reg [7:0] d_wdata;
  always @* begin
    d_addr = 24'h000000; d_rd = 1'b0; d_wr = 1'b0; d_wdata = 8'h00;
    if (dma_active) begin
      if (dph == 1'b0) begin
        d_addr = cur_ctrl[7] ? b_addr : a_addr; d_rd = 1'b1;
      end else begin
        d_addr = cur_ctrl[7] ? a_addr : b_addr; d_wr = 1'b1; d_wdata = bus_rdata;
      end
    end
  end

  assign bus_addr  = dma_active ? d_addr  : c_addr;
  assign bus_rd    = dma_active ? d_rd    : c_rd;
  assign bus_wr    = dma_active ? d_wr    : c_wr;
  assign bus_wdata = dma_active ? d_wdata : c_wdata;

  // ---- registri $42xx ----
  reg [7:0] wrmpya, wrdiv_l, wrdiv_h;
  reg [15:0] rddiv, rdmpy;
  reg [23:0] alu_shift;
  reg [3:0] mpy_left;
  reg [4:0] div_left;
  reg alu_wait;                  // il calcolo comincia dal ciclo dopo la scrittura
  wire [23:0] div_next = {1'b0, alu_shift[23:1]};
  wire div_fits = ({8'h00, rdmpy} >= div_next);
  reg nmi_flag, vblank_q;

  assign regs_hit = (bus_addr[22] == 1'b0) && ((bus_addr[15:5] == 11'h210) || (bus_addr[15:7] == 9'h086));

  reg [7:0] rb;
  always @* begin
    rb = 8'h00;
    if (bus_addr[15:5] == 11'h210) begin
      case (bus_addr[4:0])
        5'h10: rb = {nmi_flag, 3'b000, 4'h2};
        5'h12: rb = {vblank, 7'h00};
        5'h14: rb = rddiv[7:0];
        5'h15: rb = rddiv[15:8];
        5'h16: rb = rdmpy[7:0];
        5'h17: rb = rdmpy[15:8];
        default: rb = 8'h00;
      endcase
    end else begin
      case (bus_addr[3:0])
        4'h0: rb = d_ctrl[bus_addr[6:4]];
        4'h1: rb = d_b[bus_addr[6:4]];
        4'h2: rb = d_al[bus_addr[6:4]];
        4'h3: rb = d_ah[bus_addr[6:4]];
        4'h4: rb = d_ab[bus_addr[6:4]];
        4'h5: rb = d_cl[bus_addr[6:4]];
        4'h6: rb = d_ch[bus_addr[6:4]];
        default: rb = 8'h00;
      endcase
    end
  end

  always @(posedge clk) begin
    regs_rdata <= rb;
    if (rst) begin
      dma_pending <= 1'b0; dma_active <= 1'b0; mdmaen <= 8'd0; hdmaen <= 8'd0; nmitimen <= 8'd0;
      dch <= 3'd0; dph <= 1'b0; dpat <= 2'd0;
      wrmpya <= 8'd0; wrdiv_l <= 8'd0; wrdiv_h <= 8'd0; rddiv <= 16'd0; rdmpy <= 16'd0;
      alu_shift <= 24'd0; mpy_left <= 4'd0; div_left <= 5'd0; alu_wait <= 1'b0;
      nmi_flag <= 1'b0; vblank_q <= 1'b0;
    end else begin
      vblank_q <= vblank;
      if (vblank && !vblank_q) nmi_flag <= 1'b1;
      if (bus_rd && bus_addr[22] == 1'b0 && bus_addr[15:0] == 16'h4210) nmi_flag <= 1'b0;

      // motore DMA
      if (dma_pending && !dma_active) begin
        if (mdmaen == 8'd0) dma_pending <= 1'b0;
        else begin
          dma_active <= 1'b1; dph <= 1'b0; dpat <= 2'd0;
          if (mdmaen[0]) dch <= 3'd0;
          else if (mdmaen[1]) dch <= 3'd1;
          else if (mdmaen[2]) dch <= 3'd2;
          else if (mdmaen[3]) dch <= 3'd3;
          else if (mdmaen[4]) dch <= 3'd4;
          else if (mdmaen[5]) dch <= 3'd5;
          else if (mdmaen[6]) dch <= 3'd6;
          else dch <= 3'd7;
        end
      end else if (dma_active) begin
        if (dph == 1'b0) dph <= 1'b1;
        else begin
          dph <= 1'b0; dpat <= dpat + 2'd1;
          if (!cur_ctrl[3]) begin d_al[dch] <= a_next[7:0]; d_ah[dch] <= a_next[15:8]; end
          d_cl[dch] <= cnt_next[7:0]; d_ch[dch] <= cnt_next[15:8];
          if (cnt_cur == 16'd1) begin
            mdmaen <= mdmaen & ~(8'h01 << dch);
            dma_active <= 1'b0;
          end
        end
      end

      // un passo di moltiplicazione o divisione alla fine di ogni ciclo di CPU
      if (c_cyc_end) begin
        if (alu_wait) alu_wait <= 1'b0;
        else if (mpy_left != 4'd0) begin
          if (rddiv[0]) rdmpy <= rdmpy + alu_shift[15:0];
          rddiv <= {1'b0, rddiv[15:1]};
          alu_shift <= {alu_shift[22:0], 1'b0};
          mpy_left <= mpy_left - 4'd1;
        end else if (div_left != 5'd0) begin
          if (div_fits) rdmpy <= rdmpy - div_next[15:0];
          rddiv <= {rddiv[14:0], div_fits};
          alu_shift <= div_next;
          div_left <= div_left - 5'd1;
        end
      end

      // scritture ai registri
      if (bus_wr && bus_addr[22] == 1'b0) begin
        if (bus_addr[15:5] == 11'h210) begin
          case (bus_addr[4:0])
            5'h00: nmitimen <= bus_wdata;
            5'h02: wrmpya <= bus_wdata;
            5'h03: begin
              rdmpy <= 16'd0; rddiv <= {bus_wdata, wrmpya}; alu_shift <= {16'd0, bus_wdata};
              mpy_left <= 4'd8; div_left <= 5'd0; alu_wait <= 1'b1;
            end
            5'h04: wrdiv_l <= bus_wdata;
            5'h05: wrdiv_h <= bus_wdata;
            5'h06: begin
              rdmpy <= {wrdiv_h, wrdiv_l}; alu_shift <= {bus_wdata, 16'd0};
              div_left <= 5'd16; mpy_left <= 4'd0; alu_wait <= 1'b1;
            end
            5'h0B: begin mdmaen <= bus_wdata; dma_pending <= (bus_wdata != 8'h00); end
            5'h0C: hdmaen <= bus_wdata;
            default: ;
          endcase
        end
        if (bus_addr[15:7] == 9'h086) begin
          case (bus_addr[3:0])
            4'h0: d_ctrl[bus_addr[6:4]] <= bus_wdata;
            4'h1: d_b[bus_addr[6:4]] <= bus_wdata;
            4'h2: d_al[bus_addr[6:4]] <= bus_wdata;
            4'h3: d_ah[bus_addr[6:4]] <= bus_wdata;
            4'h4: d_ab[bus_addr[6:4]] <= bus_wdata;
            4'h5: d_cl[bus_addr[6:4]] <= bus_wdata;
            4'h6: d_ch[bus_addr[6:4]] <= bus_wdata;
            default: ;
          endcase
        end
      end
    end
  end
endmodule
