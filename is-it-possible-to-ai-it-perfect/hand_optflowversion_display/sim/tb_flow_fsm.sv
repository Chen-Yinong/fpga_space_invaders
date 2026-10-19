// tb_flow_fsm.sv — 方向投票 + 漏桶积分器自检
//   乱闪（左右交替）-> 不点亮；连续右移 -> right；连续静止 -> stop；连续左移 -> left
`timescale 1ns/1ps
module tb_flow_fsm;
  reg pclk = 1'b0;
  reg rst_n = 1'b0;
  reg flow_valid = 1'b0;
  reg signed [31:0] flow_u = 0;
  reg signed [31:0] flow_v = 0;
  reg [31:0] flow_energy = 0;
  reg [4:0] flow_bx = 0;
  reg [3:0] flow_by = 0;
  reg vsync = 1'b0;
  reg clk_disp = 1'b0;
  reg [11:0] px = 0, py = 0;
  wire [1:0] tag_out;
  wire led_stop, led_left, led_right;

  flow_fsm u_fsm (
    .pclk(pclk), .rst_n(rst_n),
    .flow_valid(flow_valid), .flow_u(flow_u), .flow_v(flow_v),
    .flow_energy(flow_energy), .flow_bx(flow_bx), .flow_by(flow_by),
    .vsync(vsync),
    .clk_disp(clk_disp), .px(px), .py(py), .tag_out(tag_out),
    .led_stop(led_stop), .led_left(led_left), .led_right(led_right)
  );

  always #20 pclk = ~pclk;
  always #40 clk_disp = ~clk_disp;

  task feed_blocks(input integer n, input integer uval);
    integer i;
    begin
      for (i = 0; i < n; i = i + 1) begin
        flow_valid  <= 1'b1;
        flow_u      <= uval;
        flow_energy <= 32'd20000;
        flow_bx     <= i[4:0];
        flow_by     <= 4'd0;
        @(posedge pclk);
      end
      flow_valid <= 1'b0;
      @(posedge pclk);
    end
  endtask

  task end_frame;
    begin
      vsync <= 1'b1; @(posedge pclk);
      vsync <= 1'b0; @(posedge pclk);
    end
  endtask

  initial begin
    repeat (4) @(posedge pclk);
    rst_n <= 1'b1;
    @(posedge pclk);

    // 1. 乱闪：左右交替 6 帧，不应点亮
    repeat (3) begin
      feed_blocks(10, -8 * 65536); end_frame();
      feed_blocks(10,  8 * 65536); end_frame();
    end
    $display("after jitter    : stop/left/right = %b %b %b  (expect 1 0 0)",
             led_stop, led_left, led_right);

    // 2. 连续右移 3 帧
    repeat (3) begin
      feed_blocks(10, 8 * 65536); end_frame();
    end
    $display("after 3x right  : stop/left/right = %b %b %b  (expect 0 0 1)",
             led_stop, led_left, led_right);

    // 3. 连续静止 3 帧
    repeat (3) begin
      feed_blocks(0, 0); end_frame();
    end
    $display("after 3x still  : stop/left/right = %b %b %b  (expect 1 0 0)",
             led_stop, led_left, led_right);

    // 4. 连续左移 3 帧
    repeat (3) begin
      feed_blocks(10, -8 * 65536); end_frame();
    end
    $display("after 3x left   : stop/left/right = %b %b %b  (expect 0 1 0)",
             led_stop, led_left, led_right);

    $finish;
  end
endmodule
