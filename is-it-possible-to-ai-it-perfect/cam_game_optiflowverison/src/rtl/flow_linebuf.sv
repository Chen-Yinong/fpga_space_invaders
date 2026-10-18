// flow_linebuf.sv — 处理域行缓冲（SRL 推断），en 每拍推进一次
//   输出 q = 延迟 DEPTH 个使能周期后的输入。
`timescale 1ns/1ps
module flow_linebuf #(
  parameter int DEPTH = 320,
  parameter int W     = 8
)(
  input  logic         clk,
  input  logic         rst_n,
  input  logic         en,
  input  logic [W-1:0] d,
  output logic [W-1:0] q
);
  (* srl_style = "srl" *) logic [W-1:0] mem [0:DEPTH-1];
  integer i;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < DEPTH; i = i + 1)
        mem[i] <= '0;
    end else if (en) begin
      for (i = DEPTH-1; i > 0; i = i - 1)
        mem[i] <= mem[i-1];
      mem[0] <= d;
    end
  end

  assign q = mem[DEPTH-1];
endmodule
