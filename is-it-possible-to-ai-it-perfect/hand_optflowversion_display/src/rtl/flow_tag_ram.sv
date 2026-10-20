// flow_tag_ram.sv — 块运动标签双口 RAM（300 深 × 2bit）
//   写侧 pclk：0=静止/低能，1=明显左移，2=明显右移
//   读侧 clk_disp：供 HDMI 运动场可视化
`timescale 1ns/1ps
module flow_tag_ram #(
  parameter int DEPTH = 300
)(
  input  logic        wclk,
  input  logic        we,
  input  logic [8:0]  waddr,
  input  logic [1:0]  wdata,
  input  logic        rclk,
  input  logic [8:0]  raddr,
  output logic [1:0]  rdata
);
  (* ram_style = "block" *) logic [1:0] mem [0:DEPTH-1];

  always_ff @(posedge wclk) begin
    if (we) mem[waddr] <= wdata;
  end

  always_ff @(posedge rclk) begin
    rdata <= mem[raddr];
  end
endmodule
