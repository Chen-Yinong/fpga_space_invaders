// debounce.sv — 按键消抖（电平稳定 CNT 个时钟才认可）
`timescale 1ns/1ps
module debounce #(
  parameter int CNT = 500000     // 5ms @100MHz
)(
  input  logic clk,
  input  logic rst_n,
  input  logic btn_in,
  output logic btn_out
);
  logic [31:0] cnt;
  logic        btn_sync;
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) btn_sync <= 1'b0; else btn_sync <= btn_in;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin cnt <= '0; btn_out <= 1'b0; end
    else if (btn_sync != btn_out) begin
      if (cnt == CNT-1) begin cnt <= '0; btn_out <= btn_sync; end
      else cnt <= cnt + 1'b1;
    end else cnt <= '0;
  end
endmodule