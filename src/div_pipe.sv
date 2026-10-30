// div_pipe.sv — 流水线恢复除法器：signed / signed -> 32bit 定点商（Q=QF）
//   被除数 = |num| << QF（W+QF 位），除数 = |den|（W 位），
//   N = W+QF 拍后得到无符号商，再按符号位取反并饱和到 32bit。
`timescale 1ns/1ps
module div_pipe #(
  parameter int W  = 54,   // 数值位宽（signed）
  parameter int QF = 16    // 定点小数位
)(
  input  logic                clk,
  input  logic                rst_n,
  input  logic                start,
  input  logic signed [W-1:0] num,
  input  logic signed [W-1:0] den,
  output logic                done,
  output logic signed [31:0]  quot,
  output logic                div_by_zero
);
  localparam int N = W + QF;

  logic          busy;
  logic [6:0]    step;
  logic [W-1:0]  den_abs;
  logic [N-1:0]  quo_reg;
  logic [W:0]    rem;
  logic          neg;

  wire [W-1:0] num_abs_w = num[W-1] ? (~num + 1'b1) : num;
  wire [W-1:0] den_abs_w = den[W-1] ? (~den + 1'b1) : den;
  wire [N-1:0] num_sh    = {num_abs_w, {QF{1'b0}}};

  wire [W:0] rem_sh = {rem[W-1:0], quo_reg[N-1]};
  wire [W:0] rem_su = rem_sh - {1'b0, den_abs};
  wire borrow = rem_su[W];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy        <= 1'b0;
      step        <= '0;
      done        <= 1'b0;
      quot        <= 32'sd0;
      div_by_zero <= 1'b0;
      rem         <= '0;
      quo_reg     <= '0;
      den_abs     <= '0;
      neg         <= 1'b0;
    end else begin
      done <= 1'b0;
      if (start && !busy) begin
        busy        <= 1'b1;
        step        <= '0;
        rem         <= '0;
        den_abs     <= den_abs_w;
        quo_reg     <= num_sh;
        neg         <= (num[W-1] ^ den[W-1]) && (den != 0) && (num != 0);
        div_by_zero <= (den == 0);
      end else if (busy) begin
        if (step < N) begin
          step <= step + 1'b1;
          if (borrow) begin
            rem     <= rem_su + {1'b0, den_abs};
            quo_reg <= {quo_reg[N-2:0], 1'b0};
          end else begin
            rem     <= rem_su;
            quo_reg <= {quo_reg[N-2:0], 1'b1};
          end
        end else begin
          busy <= 1'b0;
          done <= 1'b1;
          if (neg) begin
            if (quo_reg[31:0] > 32'h7FFFFFFF)
              quot <= 32'h80000000;
            else
              quot <= -$signed(quo_reg[31:0]);
          end else begin
            if (quo_reg[31:0] > 32'h7FFFFFFF)
              quot <= 32'h7FFFFFFF;
            else
              quot <= $signed(quo_reg[31:0]);
          end
        end
      end
    end
  end
endmodule
